#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
git_source_dir="$repo_dir/dot_config/git"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-check-git.XXXXXX")
tmp_marker="$tmp_dir/.chezmoi-check-git"
: >"$tmp_marker"

cleanup() {
    if [ -f "$tmp_marker" ]; then
        /usr/bin/rm -rf -- "$tmp_dir"
    else
        printf 'refusing unsafe test cleanup: %s\n' "$tmp_dir" >&2
        return 1
    fi
}
trap cleanup EXIT HUP INT TERM

git config --file "$repo_dir/dot_gitconfig" --list >/dev/null
[ "$(git config --file "$repo_dir/dot_gitconfig" --get include.path)" = \
    "~/.config/git/.gitconfig-identity" ]

expected_inventory=$(cat <<'EOF'
encrypted_private_dot_gitconfig-github.age
encrypted_private_dot_gitconfig-identity.age
encrypted_private_dot_gitconfig-person.age
encrypted_private_dot_gitconfig-work.age
ignore
EOF
)
actual_inventory=$(
    find "$git_source_dir" -maxdepth 1 -type f -printf '%f\n' | sort
)
[ "$actual_inventory" = "$expected_inventory" ] || {
    printf '%s\n' 'unexpected managed Git source inventory' >&2
    exit 1
}

for encrypted_source in "$git_source_dir"/encrypted_*.age; do
    [ "$(head -n 1 "$encrypted_source")" = \
        '-----BEGIN AGE ENCRYPTED FILE-----' ] || {
        printf '%s\n' 'Git identity source is not age armored' >&2
        exit 1
    }
done

if grep -ERq -- \
    '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' \
    "$repo_dir/dot_gitconfig" "$git_source_dir/ignore"
then
    printf '%s\n' 'unencrypted Git source contains an email address' >&2
    exit 1
fi

fixture_source="$tmp_dir/source"
fixture_home="$tmp_dir/home"
fixture_plain="$tmp_dir/plain"
mkdir -p "$fixture_source/dot_config/git" "$fixture_home" "$fixture_plain"
cp "$repo_dir/dot_gitconfig" "$fixture_source/dot_gitconfig"
cp "$git_source_dir/ignore" "$fixture_source/dot_config/git/ignore"

age-keygen -o "$tmp_dir/fixture-age-key.txt" >/dev/null 2>&1
fixture_recipient=$(age-keygen -y "$tmp_dir/fixture-age-key.txt")

cat >"$fixture_plain/identity" <<'EOF'
[user]
	name = Fixture Default
	email = default@example.invalid
EOF
cat >"$fixture_plain/work" <<'EOF'
[user]
	name = Fixture Work
	email = work@example.invalid
EOF
cat >"$fixture_plain/person" <<'EOF'
[user]
	name = Fixture Person
	email = person@example.invalid
[url "git@github-fixture-person:"]
	insteadOf = git@github.com:
EOF
cat >"$fixture_plain/github" <<'EOF'
[user]
	name = Fixture GitHub
	email = github@example.invalid
[url "git@github-fixture-primary:"]
	insteadOf = git@github.com:
EOF

for profile in identity work person github; do
    age -a -r "$fixture_recipient" \
        -o "$fixture_source/dot_config/git/encrypted_private_dot_gitconfig-$profile.age" \
        "$fixture_plain/$profile"
done

fixture_config="$tmp_dir/fixture.toml"
cat >"$fixture_config" <<EOF
encryption = "age"
mode = "file"
destDir = "$fixture_home"

[age]
    identity = "$tmp_dir/fixture-age-key.txt"
    recipient = "$fixture_recipient"

[template]
    options = ["missingkey=error"]

[data]
    role = "laptop"
    shell = "zsh"
    graphical = false
    niri = false
    niriOutputProfile = "auto"
    work = false
    sshAgent = false
    sshInboundIdentity = "none"
    secretBackend = "rbw"
EOF
chezmoi --cache "$tmp_dir/fixture-cache" \
    --config "$fixture_config" \
    --source "$fixture_source" \
    apply --exclude scripts >/dev/null 2>&1

git config --file "$fixture_home/.gitconfig" --list >/dev/null
for profile in identity work person github; do
    target="$fixture_home/.config/git/.gitconfig-$profile"
    cmp -s "$target" "$fixture_plain/$profile"
    [ "$(stat -c %a "$target")" = "600" ]
    git config --file "$target" --list >/dev/null
done

excluded_home="$tmp_dir/excluded-home"
excluded_config="$tmp_dir/excluded.toml"
mkdir -p "$excluded_home"
cat >"$excluded_config" <<EOF
encryption = "age"
mode = "file"
destDir = "$excluded_home"

[age]
    identity = "$tmp_dir/missing-age-identity.txt"
    recipient = "$fixture_recipient"

[template]
    options = ["missingkey=error"]

[data]
    role = "server"
    shell = "zsh"
    graphical = false
    niri = false
    niriOutputProfile = "auto"
    work = false
    sshAgent = false
    sshInboundIdentity = "none"
    secretBackend = "rbw"
EOF
chezmoi --cache "$tmp_dir/excluded-cache" \
    --config "$excluded_config" \
    --source "$fixture_source" \
    apply --exclude encrypted >/dev/null 2>&1
[ -f "$excluded_home/.gitconfig" ]
[ ! -e "$excluded_home/.config/git/.gitconfig-identity" ]
[ ! -e "$excluded_home/.config/git/.gitconfig-work" ]
[ ! -e "$excluded_home/.config/git/.gitconfig-person" ]
[ ! -e "$excluded_home/.config/git/.gitconfig-github" ]

validate_real_sources() {
    identity_file="$HOME/.config/chezmoi/age-identity.txt"
    mkdir -p "$tmp_dir/real"
    for profile in identity work person github; do
        age -d -i "$identity_file" \
            "$git_source_dir/encrypted_private_dot_gitconfig-$profile.age" \
            >"$tmp_dir/real/$profile"
        git config --file "$tmp_dir/real/$profile" --list >/dev/null
    done

    python3 - "$tmp_dir/real" <<'PY'
import configparser
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
routes = {}
users = {}
for profile in ("identity", "work", "person", "github"):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(root / profile)
    if not parser.has_section("user"):
        raise SystemExit("encrypted Git profile has no user section")
    if set(parser["user"]) != {"name", "email"}:
        raise SystemExit("unexpected encrypted Git user fields")
    if not parser["user"]["name"].strip():
        raise SystemExit("empty encrypted Git user name")
    if not re.fullmatch(
        r"[^@\s]+@[^@\s]+\.[^@\s]+",
        parser["user"]["email"].strip(),
    ):
        raise SystemExit("invalid encrypted Git email")
    users[profile] = dict(parser["user"])
    if profile != "work" and not re.fullmatch(
        r"\d+\+[^@\s]+@users\.noreply\.github\.com",
        parser["user"]["email"].strip(),
        re.IGNORECASE,
    ):
        raise SystemExit("public Git profile must use an ID-based noreply email")

    url_sections = [
        section for section in parser.sections()
        if section.startswith('url "git@') and section.endswith(':"')
    ]
    if profile in {"identity", "work"}:
        if url_sections or set(parser.sections()) != {"user"}:
            raise SystemExit("unexpected encrypted Git profile section")
        continue
    if len(url_sections) != 1 or set(parser.sections()) != {
        "user",
        url_sections[0],
    }:
        raise SystemExit("unexpected encrypted Git routing sections")
    if dict(parser[url_sections[0]]) != {"insteadof": "git@github.com:"}:
        raise SystemExit("unexpected encrypted Git URL rewrite")
    routes[profile] = url_sections[0]

if routes["person"] == routes["github"]:
    raise SystemExit("GitHub profiles must use distinct SSH aliases")
if users["identity"] != users["person"]:
    raise SystemExit("default and personal Git identities must match")
if users["person"]["email"].casefold() == users["github"]["email"].casefold():
    raise SystemExit("GitHub account profiles must use distinct identities")
PY
}

private_check=${CHECK_PRIVATE_CONFIG-auto}
case "$private_check" in
    1)
        [ -r "$HOME/.config/chezmoi/age-identity.txt" ] || {
            printf '%s\n' 'real Git validation requires the age identity' >&2
            exit 1
        }
        validate_real_sources
        ;;
    auto)
        if [ -r "$HOME/.config/chezmoi/age-identity.txt" ]; then
            validate_real_sources
        fi
        ;;
    0) ;;
    *)
        printf '%s\n' 'CHECK_PRIVATE_CONFIG must be 0, 1, or auto' >&2
        exit 1
        ;;
esac

printf '%s\n' "Git configs passed"

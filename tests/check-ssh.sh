#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ssh_source_dir="$repo_dir/private_dot_ssh"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-check-ssh.XXXXXX")
tmp_marker="$tmp_dir/.chezmoi-check-ssh"
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

identities=$(cat <<'EOF'
company_ai
company_dev
github_primary
github_secondary
private
uni
EOF
)

expected_source_inventory=$(cat <<'EOF'
encrypted_private_authorized_keys.tmpl.age
private_config
private_config.d/encrypted_private_10-private.conf.age
private_config.d/encrypted_private_30-company.conf.age
private_config.d/encrypted_private_40-github.conf.age
private_config.d/private_90-defaults.conf
private_identities/encrypted_company_ai.pub.age
private_identities/encrypted_company_dev.pub.age
private_identities/encrypted_github_primary.pub.age
private_identities/encrypted_github_secondary.pub.age
private_identities/encrypted_private.pub.age
private_identities/encrypted_uni.pub.age
EOF
)
actual_source_inventory=$(
    find "$ssh_source_dir" -type f -printf '%P\n' | sort
)
[ "$actual_source_inventory" = "$expected_source_inventory" ] || {
    printf '%s\n' 'unexpected managed SSH source inventory' >&2
    exit 1
}

encrypted_sources=$(
    find "$ssh_source_dir" -type f -name '*.age' | sort
)
[ "$(printf '%s\n' "$encrypted_sources" | wc -l)" -eq 10 ] || {
    printf '%s\n' 'unexpected encrypted SSH source count' >&2
    exit 1
}
for encrypted_source in $encrypted_sources; do
    [ "$(head -n 1 "$encrypted_source")" = \
        '-----BEGIN AGE ENCRYPTED FILE-----' ] || {
        printf '%s\n' 'SSH source is not age armored' >&2
        exit 1
    }
done

for public_source in $(
    find "$ssh_source_dir" -type f ! -name '*.age' | sort
); do
    if grep -Eq -- \
        '^ssh-(ed25519|rsa|ecdsa) |^[[:space:]]*(HostName|User|Port|IdentityFile)[[:space:]]' \
        "$public_source"
    then
        printf '%s\n' 'unencrypted SSH source contains private inventory data' >&2
        exit 1
    fi
done

expected_root_config=$(cat <<'EOF'
Include ~/.ssh/config.d/*.conf
Include ~/.ssh/config.local.d/*.conf
EOF
)
[ "$(cat "$ssh_source_dir/private_config")" = "$expected_root_config" ] || {
    printf '%s\n' 'managed SSH includes are missing or out of order' >&2
    exit 1
}

fixture_source="$tmp_dir/source"
fixture_home_root="$tmp_dir/homes"
fixture_plain="$tmp_dir/plain"
fixture_keys="$fixture_plain/keys"
mkdir -p \
    "$fixture_source/private_dot_ssh/private_config.d" \
    "$fixture_source/private_dot_ssh/private_identities" \
    "$fixture_source/dot_config/environment.d" \
    "$fixture_source/dot_config/shell" \
    "$fixture_home_root" \
    "$fixture_keys"
cp "$repo_dir/.chezmoiignore" "$fixture_source/.chezmoiignore"
cp "$ssh_source_dir/private_config" \
    "$fixture_source/private_dot_ssh/private_config"
cp "$ssh_source_dir/private_config.d/private_90-defaults.conf" \
    "$fixture_source/private_dot_ssh/private_config.d/private_90-defaults.conf"
cp "$repo_dir/dot_config/environment.d/20-rbw-ssh-agent.conf" \
    "$fixture_source/dot_config/environment.d/20-rbw-ssh-agent.conf"
cp "$repo_dir/dot_config/shell/profile.sh" \
    "$fixture_source/dot_config/shell/profile.sh"
cp "$repo_dir/dot_config/shell/ssh-agent.sh" \
    "$fixture_source/dot_config/shell/ssh-agent.sh"

age-keygen -o "$tmp_dir/fixture-age-key.txt" >/dev/null 2>&1
fixture_recipient=$(age-keygen -y "$tmp_dir/fixture-age-key.txt")

for identity in $identities; do
    ssh-keygen -q -t ed25519 -N '' -C "$identity" \
        -f "$fixture_keys/$identity"
    age -a -r "$fixture_recipient" \
        -o "$fixture_source/private_dot_ssh/private_identities/encrypted_$identity.pub.age" \
        "$fixture_keys/$identity.pub"
done

cat >"$fixture_plain/10-private.conf" <<'EOF'
Host fixture-private fixture-private-alt
    HostName private.example.invalid
    User private-user
    Port 2201
    IdentityFile ~/.ssh/identities/private.pub
    IdentitiesOnly yes

Host fixture-remote
    HostName remote.example.invalid
    User remote-user
    Port 2202
    IdentityFile ~/.ssh/identities/uni.pub
    IdentitiesOnly yes
EOF
cat >"$fixture_plain/30-company.conf" <<'EOF'
Host fixture-company-dev
    HostName dev.example.invalid
    User dev-user
    Port 2203
    IdentityFile ~/.ssh/identities/company_dev.pub
    IdentitiesOnly yes

Host fixture-company-ai
    HostName ai.example.invalid
    User ai-user
    Port 2204
    IdentityFile ~/.ssh/identities/company_ai.pub
    IdentitiesOnly yes
EOF
cat >"$fixture_plain/40-github.conf" <<'EOF'
Host fixture-github-primary
    HostName github.example.invalid
    User git
    Port 22
    IdentityFile ~/.ssh/identities/github_primary.pub
    IdentitiesOnly yes

Host fixture-github-secondary
    HostName github.example.invalid
    User git
    Port 22
    IdentityFile ~/.ssh/identities/github_secondary.pub
    IdentitiesOnly yes
EOF

for fragment in 10-private.conf 30-company.conf 40-github.conf; do
    age -a -r "$fixture_recipient" \
        -o "$fixture_source/private_dot_ssh/private_config.d/encrypted_private_$fragment.age" \
        "$fixture_plain/$fragment"
done

python3 - "$fixture_keys" "$fixture_plain/authorized_keys.tmpl" <<'PY'
import pathlib
import sys

key_dir = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
private_key = (key_dir / "private.pub").read_text().strip()
uni_key = (key_dir / "uni.pub").read_text().strip()
output.write_text(
    '{{- $sshInboundIdentity := "none" -}}\n'
    '{{- if hasKey . "sshInboundIdentity" -}}\n'
    '{{-   $sshInboundIdentity = .sshInboundIdentity -}}\n'
    '{{- end -}}\n'
    '{{- if eq $sshInboundIdentity "private" -}}\n'
    f"{private_key}\n"
    '{{- else if eq $sshInboundIdentity "uni" -}}\n'
    f"{uni_key}\n"
    '{{- else -}}\n'
    '{{ fail "authorized_keys requires sshInboundIdentity private or uni" }}\n'
    '{{- end -}}{{ "\\n" }}'
)
PY
age -a -r "$fixture_recipient" \
    -o "$fixture_source/private_dot_ssh/encrypted_private_authorized_keys.tmpl.age" \
    "$fixture_plain/authorized_keys.tmpl"

validate_key_set() {
    key_dir=$1
    : >"$tmp_dir/key-material"
    for identity in $identities; do
        key_file="$key_dir/$identity.pub"
        set -- $(cat "$key_file")
        [ "$#" -eq 3 ] || {
            printf 'invalid public-key fields: %s\n' "$identity" >&2
            exit 1
        }
        [ "$1" = "ssh-ed25519" ] || {
            printf 'non-Ed25519 public key: %s\n' "$identity" >&2
            exit 1
        }
        [ "$3" = "$identity" ] || {
            printf 'unexpected public-key comment: %s\n' "$identity" >&2
            exit 1
        }
        ssh-keygen -lf "$key_file" -E sha256 >/dev/null
        printf '%s\n' "$2" >>"$tmp_dir/key-material"
    done
    [ "$(sort -u "$tmp_dir/key-material" | wc -l)" -eq 6 ] || {
        printf '%s\n' 'SSH identities must use distinct public keys' >&2
        exit 1
    }
}
validate_key_set "$fixture_keys"

write_config() {
    config_file=$1
    home_dir=$2
    ssh_agent=$3
    inbound_identity=$4
    age_identity=$5
    cat >"$config_file" <<EOF
encryption = "age"
mode = "file"
destDir = "$home_dir"

[age]
    identity = "$age_identity"
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
    sshAgent = $ssh_agent
    sshInboundIdentity = "$inbound_identity"
    secretBackend = "rbw"
EOF
}

apply_profile() {
    profile=$1
    ssh_agent=$2
    inbound_identity=$3
    home_dir="$fixture_home_root/$profile"
    config_file="$tmp_dir/$profile.toml"
    mkdir -p "$home_dir"
    write_config "$config_file" "$home_dir" "$ssh_agent" \
        "$inbound_identity" "$tmp_dir/fixture-age-key.txt"
    chezmoi --cache "$tmp_dir/$profile-cache" \
        --config "$config_file" \
        --source "$fixture_source" \
        apply --exclude scripts >/dev/null 2>&1
}

verify_profile() {
    profile=$1
    ssh_agent=$2
    inbound_identity=$3
    home_dir="$fixture_home_root/$profile"

    if [ "$ssh_agent" = true ]; then
        [ -f "$home_dir/.ssh/config" ]
        [ -f "$home_dir/.ssh/config.d/10-private.conf" ]
        [ -f "$home_dir/.ssh/config.d/30-company.conf" ]
        [ -f "$home_dir/.ssh/config.d/40-github.conf" ]
        [ -f "$home_dir/.ssh/config.d/90-defaults.conf" ]
        [ -f "$home_dir/.config/environment.d/20-rbw-ssh-agent.conf" ]
        [ -f "$home_dir/.config/shell/ssh-agent.sh" ]
        for identity in $identities; do
            cmp -s "$home_dir/.ssh/identities/$identity.pub" \
                "$fixture_keys/$identity.pub"
        done
    else
        [ ! -e "$home_dir/.ssh/config" ]
        [ ! -e "$home_dir/.ssh/config.d" ]
        [ ! -e "$home_dir/.ssh/identities" ]
        [ ! -e "$home_dir/.config/environment.d/20-rbw-ssh-agent.conf" ]
        [ ! -e "$home_dir/.config/shell/ssh-agent.sh" ]
    fi

    case "$inbound_identity" in
        private | uni)
            cmp -s "$home_dir/.ssh/authorized_keys" \
                "$fixture_keys/$inbound_identity.pub"
            ;;
        none)
            [ ! -e "$home_dir/.ssh/authorized_keys" ]
            ;;
    esac
}

for ssh_agent in true false; do
    for inbound_identity in none private uni; do
        profile="$ssh_agent-$inbound_identity"
        apply_profile "$profile" "$ssh_agent" "$inbound_identity"
        verify_profile "$profile" "$ssh_agent" "$inbound_identity"
    done
done

agent_home="$fixture_home_root/true-private"
[ "$(stat -c %a "$agent_home/.ssh")" = "700" ]
[ "$(stat -c %a "$agent_home/.ssh/config")" = "600" ]
[ "$(stat -c %a "$agent_home/.ssh/config.d")" = "700" ]
[ "$(stat -c %a "$agent_home/.ssh/config.d/10-private.conf")" = "600" ]
[ "$(stat -c %a "$agent_home/.ssh/identities")" = "700" ]
[ "$(stat -c %a "$agent_home/.ssh/identities/private.pub")" = "644" ]
[ "$(stat -c %a "$agent_home/.ssh/authorized_keys")" = "600" ]

assembled_config="$tmp_dir/fixture-ssh-config"
for config_fragment in "$agent_home"/.ssh/config.d/*; do
    cat "$config_fragment" >>"$assembled_config"
    printf '\n' >>"$assembled_config"
done

assert_host() {
    host=$1
    expected_hostname=$2
    expected_user=$3
    expected_port=$4
    expected_identity=$5
    rendered="$tmp_dir/ssh-$host"

    ssh -F "$assembled_config" -G "$host" >"$rendered" 2>/dev/null
    [ "$(awk '$1 == "hostname" { print $2 }' "$rendered")" = "$expected_hostname" ]
    [ "$(awk '$1 == "user" { print $2 }' "$rendered")" = "$expected_user" ]
    [ "$(awk '$1 == "port" { print $2 }' "$rendered")" = "$expected_port" ]
    [ "$(awk '$1 == "identitiesonly" { print $2 }' "$rendered")" = "yes" ]
    [ "$(awk '$1 == "forwardagent" { print $2 }' "$rendered")" = "no" ]
    [ "$(awk '$1 == "hashknownhosts" { print $2 }' "$rendered")" = "yes" ]
    [ "$(awk '$1 == "identityfile" { print $2 }' "$rendered")" = \
        "~/.ssh/identities/$expected_identity.pub" ]
    [ "$(awk '$1 == "identityfile" { count++ } END { print count + 0 }' "$rendered")" -eq 1 ]
}

while IFS='|' read -r host hostname user port identity; do
    assert_host "$host" "$hostname" "$user" "$port" "$identity"
done <<'EOF'
fixture-private|private.example.invalid|private-user|2201|private
fixture-private-alt|private.example.invalid|private-user|2201|private
fixture-remote|remote.example.invalid|remote-user|2202|uni
fixture-company-dev|dev.example.invalid|dev-user|2203|company_dev
fixture-company-ai|ai.example.invalid|ai-user|2204|company_ai
fixture-github-primary|github.example.invalid|git|22|github_primary
fixture-github-secondary|github.example.invalid|git|22|github_secondary
EOF

transition_home="$fixture_home_root/false-uni"
transition_config="$tmp_dir/false-uni.toml"
write_config "$transition_config" "$transition_home" false none \
    "$tmp_dir/fixture-age-key.txt"
chezmoi --cache "$tmp_dir/false-uni-cache" \
    --config "$transition_config" \
    --source "$fixture_source" \
    apply --exclude scripts >/dev/null 2>&1
cmp -s "$transition_home/.ssh/authorized_keys" "$fixture_keys/uni.pub"

transition_home="$fixture_home_root/true-private"
transition_config="$tmp_dir/true-private.toml"
write_config "$transition_config" "$transition_home" false private \
    "$tmp_dir/fixture-age-key.txt"
chezmoi --cache "$tmp_dir/true-private-cache" \
    --config "$transition_config" \
    --source "$fixture_source" \
    apply --exclude scripts >/dev/null 2>&1
[ -f "$transition_home/.ssh/config" ]
[ -f "$transition_home/.ssh/identities/private.pub" ]
[ -f "$transition_home/.config/environment.d/20-rbw-ssh-agent.conf" ]
[ -f "$transition_home/.config/shell/ssh-agent.sh" ]

excluded_home="$tmp_dir/excluded-home"
excluded_config="$tmp_dir/excluded.toml"
mkdir -p "$excluded_home"
write_config "$excluded_config" "$excluded_home" true private \
    "$tmp_dir/missing-age-identity.txt"
chezmoi --cache "$tmp_dir/excluded-cache" \
    --config "$excluded_config" \
    --source "$fixture_source" \
    apply --exclude encrypted >/dev/null 2>&1
[ -f "$excluded_home/.ssh/config" ]
[ -f "$excluded_home/.ssh/config.d/90-defaults.conf" ]
[ ! -e "$excluded_home/.ssh/config.d/10-private.conf" ]
[ ! -e "$excluded_home/.ssh/identities/private.pub" ]
[ ! -e "$excluded_home/.ssh/authorized_keys" ]

legacy_home="$tmp_dir/legacy-home"
legacy_config="$tmp_dir/legacy.toml"
mkdir -p "$legacy_home/.ssh"
printf '%s\n' 'preserve-legacy-authorization' >"$legacy_home/.ssh/authorized_keys"
cat >"$legacy_config" <<EOF
mode = "file"
destDir = "$legacy_home"

[template]
    options = ["missingkey=error"]

[data]
    role = "server"
    shell = "zsh"
    graphical = false
    niri = false
    niriOutputProfile = "auto"
    work = false
    secretBackend = "rbw"
EOF
chezmoi --cache "$tmp_dir/legacy-cache" \
    --config "$legacy_config" \
    --source "$fixture_source" \
    apply --exclude scripts >/dev/null 2>&1
[ "$(cat "$legacy_home/.ssh/authorized_keys")" = \
    "preserve-legacy-authorization" ]
[ ! -e "$legacy_home/.ssh/config" ]
[ ! -e "$legacy_home/.config/environment.d/20-rbw-ssh-agent.conf" ]
[ ! -e "$legacy_home/.config/shell/ssh-agent.sh" ]

(
    unset SSH_AUTH_SOCK
    XDG_RUNTIME_DIR="/run/user/4242"
    export XDG_RUNTIME_DIR
    . "$repo_dir/dot_config/shell/ssh-agent.sh"
    [ "$SSH_AUTH_SOCK" = "/run/user/4242/rbw/ssh-agent-socket" ]
)
(
    SSH_AUTH_SOCK="/tmp/forwarded-agent"
    XDG_RUNTIME_DIR="/run/user/4242"
    export SSH_AUTH_SOCK XDG_RUNTIME_DIR
    . "$repo_dir/dot_config/shell/ssh-agent.sh"
    [ "$SSH_AUTH_SOCK" = "/tmp/forwarded-agent" ]
)

grep -Fq 'shell/ssh-agent.sh' "$repo_dir/dot_config/shell/profile.sh"
[ "$(cat "$repo_dir/dot_config/environment.d/20-rbw-ssh-agent.conf")" = \
    'SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/rbw/ssh-agent-socket' ]

for ignored_path in \
    '.ssh/config.pre-chezmoi*' \
    '.ssh/legacy/'
do
    grep -Fqx "$ignored_path" "$repo_dir/.chezmoiignore"
done

validate_real_sources() {
    identity_file="$HOME/.config/chezmoi/age-identity.txt"
    real_dir="$tmp_dir/real"
    mkdir -p "$real_dir/keys" "$real_dir/config"

    for identity in $identities; do
        age -d -i "$identity_file" \
            "$ssh_source_dir/private_identities/encrypted_$identity.pub.age" \
            >"$real_dir/keys/$identity.pub"
    done
    validate_key_set "$real_dir/keys"

    for fragment in 10-private.conf 30-company.conf 40-github.conf; do
        age -d -i "$identity_file" \
            "$ssh_source_dir/private_config.d/encrypted_private_$fragment.age" \
            >"$real_dir/config/$fragment"
    done
    age -d -i "$identity_file" \
        "$ssh_source_dir/encrypted_private_authorized_keys.tmpl.age" \
        >"$real_dir/authorized_keys.tmpl"

    python3 - "$real_dir" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
identities = {
    "company_ai",
    "company_dev",
    "github_primary",
    "github_secondary",
    "private",
    "uni",
}
aliases_seen = set()

for path in sorted((root / "config").glob("*.conf")):
    blocks = []
    block = None
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split()
        directive = parts[0].lower()
        values = parts[1:]
        if directive == "host":
            if block is not None:
                blocks.append(block)
            if not values or any(
                not re.fullmatch(r"[A-Za-z0-9._-]+", value)
                for value in values
            ):
                raise SystemExit("invalid encrypted Host aliases")
            if aliases_seen.intersection(values):
                raise SystemExit("duplicate encrypted Host alias")
            aliases_seen.update(values)
            block = {"host": values}
            continue
        if block is None:
            raise SystemExit("directive outside encrypted Host block")
        if directive not in {
            "hostname",
            "user",
            "port",
            "identityfile",
            "identitiesonly",
        }:
            raise SystemExit("unsafe directive in encrypted Host block")
        if directive in block or len(values) != 1:
            raise SystemExit("duplicate or malformed encrypted directive")
        block[directive] = values[0]
    if block is not None:
        blocks.append(block)
    if not blocks:
        raise SystemExit("empty encrypted SSH fragment")

    for item in blocks:
        required = {"host", "hostname", "user", "identityfile", "identitiesonly"}
        if not required <= item.keys():
            raise SystemExit("incomplete encrypted Host block")
        if not re.fullmatch(r"[A-Za-z0-9._:-]+", item["hostname"]):
            raise SystemExit("invalid encrypted HostName")
        if not re.fullmatch(r"[A-Za-z0-9._-]+", item["user"]):
            raise SystemExit("invalid encrypted User")
        if item["identitiesonly"].lower() != "yes":
            raise SystemExit("encrypted Host does not enforce IdentitiesOnly")
        identity_match = re.fullmatch(
            r"~/\.ssh/identities/([A-Za-z0-9_-]+)\.pub",
            item["identityfile"],
        )
        if not identity_match or identity_match.group(1) not in identities:
            raise SystemExit("invalid encrypted IdentityFile")
        if "port" in item:
            try:
                port = int(item["port"])
            except ValueError:
                raise SystemExit("invalid encrypted Port") from None
            if not 1 <= port <= 65535:
                raise SystemExit("encrypted Port is out of range")

key_dir = root / "keys"
private_key = (key_dir / "private.pub").read_text().strip()
uni_key = (key_dir / "uni.pub").read_text().strip()
expected_authorized = (
    '{{- $sshInboundIdentity := "none" -}}\n'
    '{{- if hasKey . "sshInboundIdentity" -}}\n'
    '{{-   $sshInboundIdentity = .sshInboundIdentity -}}\n'
    '{{- end -}}\n'
    '{{- if eq $sshInboundIdentity "private" -}}\n'
    f"{private_key}\n"
    '{{- else if eq $sshInboundIdentity "uni" -}}\n'
    f"{uni_key}\n"
    '{{- else -}}\n'
    '{{ fail "authorized_keys requires sshInboundIdentity private or uni" }}\n'
    '{{- end -}}{{ "\\n" }}'
)
if (root / "authorized_keys.tmpl").read_text() != expected_authorized:
    raise SystemExit("encrypted authorized_keys template is inconsistent")
PY
}

private_check=${CHECK_PRIVATE_CONFIG-auto}
case "$private_check" in
    1)
        [ -r "$HOME/.config/chezmoi/age-identity.txt" ] || {
            printf '%s\n' 'real SSH validation requires the age identity' >&2
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

printf '%s\n' "SSH configs passed"

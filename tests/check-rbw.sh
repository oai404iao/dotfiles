#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modifier="$repo_dir/dot_config/rbw/modify_private_config.json"
test_root=$(mktemp -d /tmp/chezmoi-rbw-test.XXXXXX)
marker="$test_root/.rbw-test-root"
: >"$marker"

cleanup() {
    if [ "${test_root-}" != "${test_root#/tmp/chezmoi-rbw-test.}" ] &&
        [ -f "$marker" ]
    then
        /usr/bin/rm -rf -- "$test_root"
    else
        printf 'refusing unsafe rbw test cleanup: %s\n' "${test_root-}" >&2
        return 1
    fi
}
trap cleanup EXIT

python3 - "$modifier" <<'PY'
import json
import pathlib
import subprocess
import sys

modifier = pathlib.Path(sys.argv[1])
compile(modifier.read_text(), str(modifier), "exec")
result = subprocess.run(
    [sys.executable, str(modifier)],
    input='{"email":"preserve@example.invalid","futureOption":true}',
    text=True,
    capture_output=True,
    check=True,
)
config = json.loads(result.stdout)
if config.get("email") != "preserve@example.invalid":
    raise SystemExit("rbw config modifier did not preserve the account")
if config.get("futureOption") is not True:
    raise SystemExit("rbw config modifier did not preserve unknown options")
if config.get("pinentry") != "pinentry-curses":
    raise SystemExit("rbw pinentry is not pinentry-curses")
PY

if grep -qxF '.config/rbw/' "$repo_dir/.chezmoiignore"; then
    printf '%s\n' "managed rbw config remains ignored" >&2
    exit 1
fi

mkdir -p "$test_root/bin"
cat >"$test_root/bin/tty" <<'EOF'
#!/bin/sh
printf '%s\n' /dev/pts/rbw-test
EOF
chmod +x "$test_root/bin/tty"

(
    PATH="$test_root/bin:/usr/bin:/bin"
    GPG_TTY="/dev/pts/stale"
    export PATH GPG_TTY

    . "$repo_dir/dot_config/shell/interactive.sh"
    [ "$GPG_TTY" = "/dev/pts/rbw-test" ]
)

printf '%s\n' "rbw config passed"

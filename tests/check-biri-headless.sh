#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v chezmoi >/dev/null 2>&1; then
    printf '%s\n' 'Biri headless rendering skipped: chezmoi unavailable'
    exit 0
fi

scratch_root="$HOME/.local/state/agents/tmp"
mkdir -p -- "$scratch_root"
task=$(umask 077; mktemp -d "$scratch_root/check-biri-headless.XXXXXXXX")
python3 - "$repo" "$task" <<'PY'
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

repo, task = map(Path, sys.argv[1:])
source = task / 'source'
home = task / 'home'
config = task / 'chezmoi.toml'
targets = ('.config/biri/headless.kdl', '.config/systemd/user/biri-headless.service')
unmanaged = (
    '.config/sunshine/sunshine.conf', '.config/sunshine/sunshine_state.json',
    '.config/sunshine/credentials/cakey.pem',
    '.config/systemd/user/default.target.wants/biri-headless.service',
)

for name in ('.chezmoi.toml.tmpl', '.chezmoiignore', *targets):
    relative = name.replace('.config/', 'dot_config/', 1)
    fixture = source / relative
    fixture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / relative, fixture)
for name in unmanaged:
    fixture = source / name.replace('.config/', 'dot_config/', 1)
    fixture.parent.mkdir(parents=True, exist_ok=True)
    fixture.write_text('application-owned fixture\n')
    target = home / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture, target)

def run(*args):
    return subprocess.check_output([
        'chezmoi', '--config', str(config), '--source', str(source),
        '--destination', str(home), '--persistent-state', str(task / 'state.boltdb'),
        '--no-tty', *args,
    ], text=True)

def init_data():
    return tomllib.loads(run('execute-template', '--init', '--stdinisatty=false',
                             '--file', str(source / '.chezmoi.toml.tmpl')))['data']

config.touch()
assert init_data()['biriHeadless'] is False
for graphical in ('true', 'false'):
    for enabled in (None, 'false', 'true'):
        config.write_text(f'[data]\ngraphical = {graphical}\nniri = {graphical}\n'
                          + (f'biriHeadless = {enabled}\n' if enabled is not None else ''))
        actual = set(run('managed', '--include=files', '--path-style=relative').splitlines())
        assert actual == (set(targets) if enabled == 'true' else set()), actual
        if enabled is not None:
            assert init_data()['biriHeadless'] is (enabled == 'true')

run('apply', '--exclude=scripts,encrypted')
assert all((home / path).is_file() for path in targets)
assert all((home / path).read_text() == 'application-owned fixture\n' for path in unmanaged)
if shutil.which('niri'):
    subprocess.run(['niri', 'validate', '--config', str(home / targets[0])], check=True)
else:
    print('Biri headless KDL validation skipped: niri unavailable')
print('Biri headless target checks passed')
PY

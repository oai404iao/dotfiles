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
import json
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

for relative in ('.chezmoi.toml.tmpl', '.chezmoiignore',
                 'dot_config/biri/headless.kdl.tmpl',
                 'dot_config/systemd/user/biri-headless.service'):
    fixture = source / relative
    fixture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(repo / relative, fixture)
for name in ('dot_config/niri', '.chezmoitemplates'):
    shutil.copytree(repo / name, source / name)
for name in unmanaged:
    fixture = source / name.replace('.config/', 'dot_config/', 1)
    fixture.parent.mkdir(parents=True, exist_ok=True)
    fixture.write_text('application-owned fixture\n')
    target = home / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fixture, target)

def run(*args, error=None):
    result = subprocess.run([
        'chezmoi', '--config', str(config), '--source', str(source),
        '--destination', str(home), '--persistent-state', str(task / 'state.boltdb'),
        '--no-tty', *args,
    ], text=True, capture_output=True, check=False)
    if error is None:
        assert result.returncode == 0, result.stderr
    else:
        assert result.returncode != 0 and error in result.stderr, result.stderr
    return result.stdout

def init_data():
    return tomllib.loads(run('execute-template', '--init', '--stdinisatty=false',
                             '--file', str(source / '.chezmoi.toml.tmpl')))['data']

def machine(compositor=None, enabled=None, graphical=False, niri=False, shell='custom'):
    data = {'graphical': graphical, 'niri': niri, 'desktopShell': shell}
    if compositor is not None:
        data['niriCompositor'] = compositor
    if enabled is not None:
        data['biriHeadless'] = enabled
    config.write_text('[data]\n' + ''.join(
        f'{key} = {json.dumps(value)}\n' for key, value in data.items()
    ))

list_files = ('managed', '--include=files', '--path-style=relative')
config.touch()
defaults = init_data()
assert defaults['biriHeadless'] is False and defaults['niriCompositor'] == 'niri'
for compositor in (None, 'niri', 'biri'):
    for enabled in (None, False, True):
        machine(compositor, enabled)
        if enabled and compositor != 'biri':
            run(*list_files, error='biriHeadless requires niriCompositor')
        else:
            actual = set(run(*list_files).splitlines())
            assert actual == (set(targets) if enabled else set()), actual
machine('invalid', False, graphical=True, niri=True)
run(*list_files, error='niriCompositor must be niri or biri')
machine('niri', True)
run('execute-template', '--init', '--stdinisatty=false', '--file',
    str(source / '.chezmoi.toml.tmpl'), error='biriHeadless requires niriCompositor')
machine('biri', True)
selected = init_data()
assert selected['niriCompositor'] == 'biri' and selected['biriHeadless'] is True

has_niri = shutil.which('niri')
for graphical, niri, shell, reuse in (
    (False, False, 'custom', False),
    (False, True, 'dms', False),
    (True, False, 'dms', False),
    (True, True, 'custom', False),
    (True, True, 'dms', True),
):
    machine('biri', True, graphical, niri, shell)
    run('apply', '--exclude=scripts,encrypted')
    assert all((home / path).is_file() for path in targets)
    kdl = home / targets[0]
    content = kdl.read_text()
    assert content.count('spawn-at-startup "/usr/bin/sunshine"') == 1
    assert '"output_name=HEADLESS-1"' in content
    assert ('include "../niri/config.kdl"' in content) is reuse
    assert ('spawn "fuzzel"' in content) is not reuse
    if reuse:
        assert '"DMS_SHELL_DIR" "dms" "run"' in (
            home / '.config/niri/conf.d/40-session.kdl').read_text()
    if has_niri:
        subprocess.run(['niri', 'validate', '--config', str(kdl)], check=True)

assert all((home / path).read_text() == 'application-owned fixture\n' for path in unmanaged)
if not has_niri:
    print('Biri headless KDL validation skipped: niri unavailable')
print('Biri headless target checks passed')
PY

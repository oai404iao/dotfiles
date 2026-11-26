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
seat_dropin = '.config/systemd/user/biri-headless.service.d/90-seat-stream.conf'
seat_rule = 'scripts/udev/72-sunshine-seat-stream.rules'
unmanaged = (
    '.config/sunshine/sunshine.conf', '.config/sunshine/sunshine_state.json',
    '.config/sunshine/credentials/cakey.pem',
    '.config/systemd/user/default.target.wants/biri-headless.service',
)

for relative in ('.chezmoi.toml.tmpl', '.chezmoiignore',
                 'dot_config/biri/headless.kdl.tmpl',
                 'dot_config/dms/modify_settings.json.tmpl',
                 'dot_config/systemd/user/biri-headless.service',
                 seat_dropin.replace('.config/', 'dot_config/', 1), seat_rule):
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

def machine(mode=None, graphical=False, niri=False, shell='custom', separate_input=None):
    data = {'graphical': graphical, 'niri': niri, 'desktopShell': shell}
    if mode is not None:
        data['biri'] = mode
    if separate_input is not None:
        data['biriSeparateInput'] = separate_input
    config.write_text('[data]\n' + ''.join(
        f'{key} = {json.dumps(value)}\n' for key, value in data.items()
    ))

list_files = ('managed', '--include=files', '--path-style=relative')
for mode in (None, 'none', 'headless'):
    machine(mode)
    assert init_data()['biri'] == (mode or 'none')
    assert init_data()['biriSeparateInput'] is False
    actual = set(run(*list_files).splitlines())
    assert actual == (set(targets) if mode == 'headless' else set()), actual
for mode, separate_input, manage_dropin in (
    (None, True, False),
    ('none', True, False),
    ('desktop', True, False),
    ('headless', False, False),
    ('headless', True, True),
):
    machine(mode, True, True, 'dms', separate_input)
    assert init_data()['biriSeparateInput'] is manage_dropin
    files = set(run(*list_files).splitlines())
    assert (seat_dropin in files) is manage_dropin
    assert seat_rule not in files
machine('headless', separate_input='false')
run(*list_files, error='biriSeparateInput must be a boolean')

if shutil.which('udevadm'):
    subprocess.run(['udevadm', 'verify', str(source / seat_rule)], check=True)
else:
    print('Sunshine udev rule validation skipped: udevadm unavailable')
for mode in ('', 'invalid', True):
    machine(mode)
    run(*list_files, error='biri must be none, headless, or desktop')
for graphical, niri, shell in (
    (True, True, 'custom'),
    (False, True, 'dms'),
    (True, False, 'dms'),
):
    machine('desktop', graphical, niri, shell)
    run(*list_files, error='requires graphical Niri with DMS')

has_niri = shutil.which('niri')
for graphical, niri, shell, reuse in (
    (False, False, 'custom', False),
    (False, True, 'dms', False),
    (True, False, 'dms', False),
    (True, True, 'custom', False),
    (True, True, 'dms', True),
):
    machine('headless', graphical, niri, shell)
    run('apply', '--exclude=scripts,encrypted')
    assert all((home / path).is_file() for path in targets)
    kdl = home / targets[0]
    content = kdl.read_text()
    assert content.count('"/usr/bin/sunshine"') == 1
    assert '"output_name=HEADLESS-1"' in content
    assert ('include "../niri/profile.kdl"' in content) is reuse
    assert ('spawn "fuzzel"' in content) is not reuse
    if reuse:
        assert 'Environment=NIRI_BACKEND=headless' in (home / targets[1]).read_text().splitlines()
        session = (home / '.config/niri/conf.d/40-session.kdl').read_text()
        assert sum(line.startswith('spawn-at-startup ') and line.endswith(' dms run"')
                   for line in session.splitlines()) == 1
    if has_niri:
        subprocess.run(['niri', 'validate', '--config', str(kdl)], check=True)

desktop = home / '.config/niri/config.kdl'
assert desktop.read_text().strip() == 'include "profile.kdl"'
assert not (home / seat_dropin).exists()
machine('headless', True, True, 'dms', separate_input=True)
run('apply', '--exclude=scripts,encrypted')
assert (home / seat_dropin).read_text().splitlines() == ['[Service]', 'Environment=XDG_SEAT=seat-stream']
assert not (home / seat_rule).exists()
machine('headless', True, True, 'dms', separate_input=False)
assert seat_dropin not in run(*list_files).splitlines()
run('apply', '--exclude=scripts,encrypted')
assert (home / seat_dropin).is_file()
installed_headless = {path: (home / path).read_bytes() for path in targets}
machine('desktop', True, True, 'dms')
assert init_data()['biri'] == 'desktop'
assert not (set(targets) & set(run(*list_files).splitlines()))
run('apply', '--exclude=scripts,encrypted')
assert {path: (home / path).read_bytes() for path in targets} == installed_headless
content = desktop.read_text()
assert 'output "SUNSHINE-1" {' in content and 'create-virtual' in content
assert content.index('output "SUNSHINE-1"') < content.index('include "profile.kdl"')
assert content.count('"/usr/bin/sunshine"') == 1
assert '"--scope"' in content and '"--property=BindsTo=niri.service"' in content
assert '"output_name=SUNSHINE-1"' in content
profile = desktop.with_name('profile.kdl').read_text()
assert 'create-virtual' not in profile and 'sunshine' not in profile
settings = json.loads((home / '.config/dms/settings.json').read_text())
assert settings['lockAtStartup'] is True
assert settings['lockScreenPowerOffMonitorsOnLock'] is False
assert settings['acPostLockMonitorTimeout'] == settings['batteryPostLockMonitorTimeout'] == 0

machine('none', True, True, 'dms')
run('apply', '--exclude=scripts,encrypted')
assert desktop.read_text().strip() == 'include "profile.kdl"'
assert not (set(targets) & set(run(*list_files).splitlines()))

assert all((home / path).read_text() == 'application-owned fixture\n' for path in unmanaged)
home = task / 'fresh-desktop'
home.mkdir()
machine('desktop', True, True, 'dms')
run('apply', '--exclude=scripts,encrypted')
assert not (home / '.config/biri').exists()
assert not (home / targets[1]).exists()
if not has_niri:
    print('Biri headless KDL validation skipped: niri unavailable')
print('Biri mode checks passed')
PY

# DMS plugins and native lyrics

Install the DMS startup launcher and maintained plugins explicitly from a
reviewed checkout. Chezmoi configures the desktop integration, but does not
fetch plugin code, install the launcher, enable plugins, or prepare the shell
overlay. **The launcher must exist before the first DMS Niri session**, even
when you intend to use stock DMS without lyrics.

The maintained `lyrics` and `dankTodo` plugins live in
[oai404iao/dms-plugins](https://github.com/oai404iao/dms-plugins), along with
their offline tests, native media overlay, preparation helper, and launcher.
That repository documents upstream attribution, licenses, plugin behavior,
and implementation changes.

| Component | Responsibility |
|---|---|
| Chezmoi | Niri startup command, DankBar layout, and reminder-only apply hook |
| Reviewed `dms-plugins` checkout | Plugin code, installer, launcher, overlay preparer, and tests |
| Machine-local state | Installed symlinks, enablement/preferences, lockfiles, todo data, generated shell trees |

The lyrics daemon shares one fetcher across displays. The version-matched
overlay integrates original/translated lyrics into the music pill and native
media page, retaining the native controls and a no-lyrics fallback. There is
no separate lyrics bar widget. Plugin preferences, enablement, lockfiles,
and todo storage remain machine-local.

Before starting, prepare the [DMS packages](desktop-shells.md#selection-and-packages)
and a trusted pristine shell tree matching DMS **1.6.2 or 1.6.3** if you want
integrated lyrics. On an existing machine, save work and stop DMS while
unlocked before replacing active plugin sources. Keep preferences and todo
data outside both source repositories, including custom todo storage paths.

## Install on a fresh machine or migrate an existing installation

### 1. Verify the chezmoi ownership handoff

Before running the plugin installer, review and update the **chezmoi source**
to a revision that removes plugin and launcher ownership and ignores their
installed paths. Inspect the source worktree first; do not blindly pull over
local changes. An older source can replace the new symlinks during a later
full apply. Verify the ownership handoff with this narrow inventory check
(no destination diff or secret rendering):

```sh
chezmoi managed --include=files,symlinks --exclude=encrypted \
  --skip-secrets --refresh-externals=never --path-style=relative |
  grep -E '^(\.config/DankMaterialShell/plugins(/|$)|\.local/bin/dms-with-lyrics$)'
```

Expect no matching paths (`grep` exits 1 for no matches); if paths appear,
stop and review the source revision before installing. Updating the source
and verifying this inventory is sufficient; **no full chezmoi apply is
required** for the handoff.

### 2. Review and test the plugin checkout

Before starting the DMS Niri session, explicitly clone and review the plugin
repository. The usual checkout is `~/Dev/local/dms-plugins`. For a new checkout:

```sh
mkdir -p ~/Dev/local
git clone https://github.com/oai404iao/dms-plugins.git ~/Dev/local/dms-plugins
cd ~/Dev/local/dms-plugins
git checkout --detach <reviewed-commit>
sh tests/check-source.sh
python3 scripts/install.py --dry-run
```

Replace `<reviewed-commit>` with the reviewed revision; do not blindly update
an existing checkout or replace local edits. These test and install commands
run from the plugin repository, **not** the chezmoi source directory.

### 3. Install the reviewed symlinks

Review the dry run and its planned replacements, then run from the same checkout:

```sh
python3 scripts/install.py
```

The installer symlinks **both** `plugins/lyrics` and `plugins/dankTodo` into
`${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins/`, plus
`bin/dms-with-lyrics` into `~/.local/bin/`. Existing targets are renamed into
a fresh private retained `~/.local/state/agents/tmp/dms-plugins-install.*`
backup directory before replacement. The installer
does not fetch updates, prepare the overlay, enable plugins, or restart DMS.
Keep the checkout at its installed location so the symlinks remain valid.

Do not use `dms plugins install`, `update`, or `restore` to overwrite these
maintained targets. Update the reviewed checkout and run its tests instead.

### 4. Start DMS, scan, and enable deliberately

After launching DMS, scan and explicitly enable the plugins you want:

```sh
dms ipc call plugin-scan scan
dms ipc call plugins enable lyrics
dms ipc call plugins enable dankTodo
```

The managed DankBar layout already places `dankTodo` on the right, after the
clipboard. Enabling the plugin is still required; chezmoi does not change
`plugin_settings.json`. Do not add `lyrics` as a separate widget.
Chezmoi owns the complete bar layout, so local layout
changes are replaced by a later apply unless intentionally added to the
settings source. After plugin-only updates, use
`dms ipc call plugins reload lyrics` or `dms ipc call plugins reload dankTodo`.
If imported JavaScript stays cached, restart DMS while unlocked.

## Native media-page overlay

### Prepare from a matching pristine tree

The plugin repository's `scripts/prepare-dms-media-lyrics.py` and
`scripts/dms-media-lyrics/` support DMS **1.6.2 and 1.6.3** only. The helper
copies a trusted, pristine complete shell tree and checks its version and
original component hashes before replacing the reviewed components in the
copy. Never modify the installed package or its read-only extraction.
These compatibility hashes do not authenticate the complete input tree.

Always prepare from the installed version's tree. Do not relabel
`.dms-version` or reuse a 1.6.2 generated tree as 1.6.3. Generated trees under
`${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/` stay machine-local.
The launcher is required for Niri startup even when no overlay is prepared;
in that case it runs stock DMS.

For an embedded-shell build, locate its pristine extraction using
`qs list --all` while stock DMS runs. Then, from the reviewed plugin checkout:

```sh
python3 scripts/prepare-dms-media-lyrics.py /path/to/pristine/extracted/dms-shell
```

The overlay is still required for the integrated 1.6.2/1.6.3 experience.
Before replacing it with a future upstream lyrics API, verify bilingual
display and provider behavior; do not bypass guards or install a beta simply
to avoid preparation. See the
[plugin repository](https://github.com/oai404iao/dms-plugins) for implementation,
supported revisions, and detailed validation.

### Switch the running shell immediately

The helper and updated Niri startup entry take effect on the next login.
To switch immediately, first save work and ensure the session is unlocked;
stop the old supervisor with `dms kill`, then launch its replacement through
Niri (the shell briefly disappears):

```sh
dms kill
niri msg action spawn -- "$HOME/.local/bin/dms-with-lyrics" run
```

Niri launches asynchronously with the desktop session's environment rather
than the English interactive-shell locale, preserving the desktop UI language
and date/time defaults. It does not preserve the caller's working directory.
This also replaces a supervisor previously launched with the shell's English
environment; `dms restart` alone cannot clear that contamination. A fresh
login is required if Niri itself still has the old locale environment.

The supervisor receives `DMS_SHELL_DIR`, so subsequent `dms restart` retains
the prepared tree and `dms ipc` still reaches the current instance. Do not
launch a second shell. Preparation retains previous generations and scratch
workspaces; cleanup is manual.

## Update after a DMS package upgrade

After a DMS package upgrade, stop the old shell and launch through
`dms-with-lyrics` again: a version mismatch falls back to stock DMS.
Do **not** rely on `dms restart` alone for this check, because an existing
supervisor retains its old environment. Re-review/rebase the overlay and
hashes before preparing for a new DMS version. Stock DMS remains usable after
fallback, but displaying these integrated lyrics requires the custom overlay.

## Return to stock DMS

Save work and ensure the session is unlocked. To return to stock immediately:

```sh
dms kill
niri msg action spawn -- /usr/bin/env -u DMS_SHELL_DIR /usr/bin/dms run
```

To make that permanent, restore the Niri startup source to
`spawn-at-startup "dms" "run"` and apply that explicit target. Neither rollback
requires deleting the prepared trees or moving startup to `dms.service`.

## Diagnose preparation reminders

The chezmoi `run_after_check-dms-lyrics.sh.tmpl` hook is active only for
graphical Niri/DMS profiles. It checks `dms`, `qs`, `dms-with-lyrics`, and the
`current/shell.qml` / `.dms-version` contract under
`${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/`. Healthy setups stay
silent. Missing dependencies, incomplete preparation, mismatched versions, or
a failed `dms version` produce stderr reminders without failing apply; Python
is checked only when preparation is needed. Unresolved reminders repeat.

| Symptom | Action |
|---|---|
| Launcher missing | Install the reviewed checkout; applying Niri again cannot repair a missing/broken symlink |
| Missing or incomplete prepared tree | Prepare from the installed version's trusted pristine shell tree |
| Version/hash mismatch | Re-review/rebase the supported overlay; never relabel `.dms-version` or bypass guards |
| Stock shell starts after an upgrade | Expected safe fallback; stop and relaunch through the launcher after preparing again |
| Plugin appears installed but not enabled | Scan and explicitly enable it; preferences are not managed by chezmoi |
| DMS remains in the terminal's language | Replace its supervisor through Niri; use a fresh login if Niri itself has the old environment |

The hook does not install, download, prepare, restart, or inspect/change plugin
enablement. Applying with `--exclude=scripts` skips even the reminders.

## Verify changes

Run `sh tests/check-source.sh` in the reviewed plugin checkout before installing
or updating it. Those offline tests cover plugin logic/QML, todo persistence,
overlay preparation, and launcher behavior. They do not prove native Wayland
popup focus, real provider availability, or live desktop behavior.

From the chezmoi source root, run:

```sh
./tests/check-desktop-profiles.sh
./tests/check-dms-apply-hints.sh
git diff --check
```

These test integration and reminder behavior without starting the real shell.
Next: [shell switching](desktop-shells.md#switch-an-existing-machine),
[desktop locale](desktop-session.md#locale-split), or the plugin repository's
own behavior and licensing documentation.

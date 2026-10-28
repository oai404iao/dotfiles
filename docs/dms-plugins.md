# Retire the DMS plugins and lyrics overlay

The desktop profile starts the packaged shell with `env -u DMS_SHELL_DIR dms run`. The old
`dms-with-lyrics` launcher, generated media overlay, and plugins are no longer
required. Do not reinstall them when upgrading to `dux-shell` 2.0.0.
The managed bar no longer contains `dankTodo`, and apply no longer emits
overlay-preparation reminders.

## Native lyrics and optional plugins

Dux 2.0 uses its native music widget and media page, not the old overlay.
Provider availability, translated lyrics, and bilingual parity still require
an authorized interactive check. Chezmoi does not install, scan, update, or
enable plugins or providers.

The separate [plugin repository](https://github.com/oai404iao/dms-plugins),
normally `~/Dev/local/dms-plugins`, owns the legacy lyrics/todo plugins,
installer, launcher, overlay and tests. Any future optional plugin use needs
a separate compatibility review. Its old installer targets
`DankMaterialShell/plugins/`; those instructions are not a Dux 2.0 installation
procedure. Native lyrics do not require that plugin. Do not modify installed
packages or read-only shell extractions to restore it.

The legacy overlay supports DMS **1.6.2 and 1.6.3 only**. Do not prepare it
against 2.0, bypass its version/hash checks, or relabel an old generated tree.

## Preserve preferences

Chezmoi targets `~/.config/dms` directly. Existing `DankMaterialShell`
compatibility symlinks remain unmanaged; do not replace them with a second
configuration directory.
If both names are separate directories, follow the
[configuration-path review](desktop-shells.md#review-existing-dux-configuration)
before deployment; do not blindly merge them or replace them with symlinks.

Before retiring local files, save work, unlock the session, and privately back
up settings, plugin preferences, and any todo data. Stop DMS before moving
installed plugin directories, the old launcher, or generated trees. Review
custom todo storage locations separately. Keep the backups outside Git.

Installed plugins, `plugin_settings.json`, plugin lockfiles, `~/.config/dank-todo/`,
`~/.local/bin/dms-with-lyrics`, and
`${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/` remain machine-local.
Removing source integration does not delete these files or disable plugins.
Retire all installed plugins explicitly while preserving the rest of the shell
preferences; do not reset the whole settings directory.

## Start the stock shell

Back up, review, and apply only the Niri session target. To preserve a customized
live bar layout, remove only retired plugin widgets from local settings while
the shell is stopped; do not apply the settings modifier as part of retirement.
That modifier restores the declared desktop preferences, including complete
bar/dock layouts, while preserving unrelated settings. See
[configuration ownership](desktop-shells.md#configuration-ownership).

Niri startup changes take effect at the next login, not on config reload.
For an immediate switch while unlocked, stop the old supervisor and launch
through Niri with its overlay override removed:

```sh
dms kill
niri msg action spawn -- /usr/bin/env -u DMS_SHELL_DIR /usr/bin/dms run
```

Do not also enable `dms.service` or start another shell. A restart of the old
supervisor alone can retain its overlay environment. Launching through Niri
also preserves the desktop locale rather than the terminal's English locale.

## Verify

Run `./tests/check-desktop-profiles.sh` and `git diff --check` in this repository.
These checks cover startup and selective settings merges, not live desktop,
provider access, lyrics display, lock/unlock, or suspend behavior. Optional
plugin implementation tests belong to the reviewed plugin checkout, not this
repository.

# DMS plugins and native lyrics

Dux Shell 2.0 uses native lyrics by default in this profile. Niri starts
`env -u DMS_SHELL_DIR dms run`, without an external launcher or prepared shell
tree. This is a source-only adoption, not a live desktop switch or proof of
bilingual parity with the old overlay. Provider availability and live lyrics
behavior still require a later, authorized interactive check.

The optional maintained `lyrics` and `dankTodo` plugins live in
[oai404iao/dms-plugins](https://github.com/oai404iao/dms-plugins), normally
`~/Dev/local/dms-plugins`. That repository owns their implementations, tests,
installer, legacy overlay, and launcher. Do not extend that code in chezmoi or
modify installed packages/read-only shell extractions.

| Component | Responsibility |
|---|---|
| Chezmoi | Native Niri startup, declared Dux settings, and complete bar layout |
| Reviewed `dms-plugins` checkout | Optional plugin code, installer, legacy launcher/overlay, and tests |
| Machine-local state | Installed plugins/symlinks, enablement/preferences, providers, lockfiles, todo data, generated shell trees |

Chezmoi does not install, update, scan, or enable plugins or providers. It does
not prepare an overlay or restart Dux. The bar retains the optional `dankTodo`
slot after the clipboard; using it requires a separately reviewed compatible
plugin installation and deliberate enablement. An unused slot does not make
that plugin a startup dependency.

## Install on a fresh machine or migrate an existing installation

Prepare the [Dux packages](desktop-shells.md#selection-and-packages), not the
legacy overlay. Before a later deployment on an existing machine, complete
the [configuration-path review](desktop-shells.md#review-existing-dux-configuration).
`~/.config/dms/settings.json` is the canonical target; the entire legacy
`~/.config/DankMaterialShell/` directory remains unmanaged. Back up and privately
review duplicate settings and plugin data rather than blindly merging them or
replacing directories with symlinks.

For an optional plugin, review the separate repository's supported shell
versions and installation destinations first. Its legacy installer targets
`DankMaterialShell/plugins/`; those instructions are not a Dux 2.0 installation
procedure. Compatibility and path changes belong in that repository, not in
chezmoi. Do not run an old installer or enable the old lyrics plugin merely
because it remains installed. Native lyrics do not require it.

Installed plugins under `~/.config/dms/plugins/` and the legacy directory,
`~/.local/bin/dms-with-lyrics`, plugin preferences/lockfiles, and
`~/.config/dank-todo/` data remain unmanaged. Custom todo storage paths must
also stay outside both source repositories. Source adoption does not delete
or relocate any of these files, and no full apply is needed to relinquish
ownership.

## Native media-page overlay

This heading describes the **legacy** implementation, not native Dux lyrics.
The separate repository's `scripts/prepare-dms-media-lyrics.py` and
`scripts/dms-media-lyrics/` support DMS **1.6.2 and 1.6.3 only**. Do not run
them against Dux 2.0, bypass their version/hash checks, or relabel an old tree.
Original/translated lyrics in that overlay do not establish equivalent native
2.0 behavior.

Generated trees under
`${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/` remain machine-local.
They are not used by this profile's startup and are not removed automatically.
Any future compatibility work belongs in the plugin repository and is separate
from choosing the native Dux implementation.

## Update after a DMS package upgrade

Review the upstream release and native integration before deployment. Do not
prepare or reactivate a legacy overlay as a 2.0 upgrade step. Preserve optional
plugin preferences and data, and review compatibility separately before updating
or enabling plugins. A source-only update neither restarts the running shell
nor validates provider access, popup focus, or lyrics display.

## Return to stock DMS

Native startup is already the managed default. A later reviewed deployment and
fresh Niri login select it while clearing `DMS_SHELL_DIR`; `dms restart` alone
can retain an old supervisor's environment. Follow the
[desktop switching procedure](desktop-shells.md#switch-an-existing-machine)
rather than applying a launcher symlink or starting a second shell. Do not also
enable `dms.service`. Existing generated trees can remain on disk.

## Verify changes

From the chezmoi source root:

```sh
./tests/check-desktop-profiles.sh
git diff --check
```

These are offline integration checks, not live lyrics validation. Optional
plugin implementation tests belong to the reviewed plugin checkout; run its
`sh tests/check-source.sh` before an independently authorized plugin update.
No overlay-preparation reminder hook is part of the native profile.

Next: [shell switching](desktop-shells.md#switch-an-existing-machine),
[desktop locale](desktop-session.md#locale-split), or the plugin repository's
own behavior and licensing documentation.

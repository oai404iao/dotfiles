# Desktop shell profiles

Niri supports two complete desktop stacks:

| Responsibility | `custom` | `dms` |
| --- | --- | --- |
| Bar / launcher / notifications | Waybar / Fuzzel / Mako | DMS |
| Wallpaper / palette orchestration | awww / Waypaper / user Matugen templates | DMS wallpaper and built-in Matugen templates |
| Clipboard history | CopyQ | DMS native clipboard (no cliphist watcher) |
| Idle / lock / sleep integration | swayidle / swaylock-effects | DMS |
| Color temperature | waybar-gammarelay.service | DMS night mode |
| Screenshot shortcuts | Niri / Satty helper | DMS screenshot |
| Power / resource UI | Waybar actions / wlogout | DMS power menu / dgop |

DMS still depends on Quickshell, Matugen for generated palettes, and system
services such as PipeWire, NetworkManager, and BlueZ. It replaces the desktop
frontends and their coordination, not those underlying services. Niri, Kitty,
Fcitx5, fonts, locale, portals, and GNOME Keyring remain shared.

## Selection and packages

On a new machine, `chezmoi init` asks for **Desktop shell: DMS or custom
components** when both `graphical` and `niri` are enabled. The default is
`custom`; older machine configurations without `desktopShell` also retain
custom. Invalid values fail rendering. Outside Niri, the DMS profile is inactive.

On an initialized machine, use `chezmoi edit-config` to set the following
under the existing `[data]` section. Do not rerun init to silence its warning:

```toml
graphical = true
niri = true
desktopShell = "dms" # or "custom"
```

The DMS integration targets Arch's DMS 1.6.2/1.6.3 and Niri 26.04.
Install separately; inspect any system upgrade transaction before accepting:

```sh
sudo pacman -Syu --needed dms-shell dgop matugen wtype qt6ct \
  adw-gtk-theme adwaita-icon-theme
```

Arch's unified [`extra/dms-shell` package](https://archlinux.org/packages/extra/x86_64/dms-shell/)
replaces `dms-shell-niri` and `dms-shell-hyprland` (also `dms-shell-bin`).
During a reviewed full upgrade, answer **Y** to either legacy-package
replacement prompt, or both if both appear. Do not reinstall the old split
packages or remove them manually first. Chezmoi still supplies Niri integration;
this package replacement does not require switching desktop profiles.
The native lyrics overlay supports DMS 1.6.2 and 1.6.3. After upgrading,
prepare it again from the matching pristine shell tree; an old 1.6.2 tree
still falls back to stock on 1.6.3. Do not bypass its version/hash checks.

Quickshell and accountsservice are pulled in as dependencies. Existing shared
desktop dependencies still apply. Cava and qt6-multimedia enable visualization
and sound feedback. See [custom dependencies](desktop.md#runtime-dependencies)
for the other profile. Keeping both package sets installed is supported.

Do not run DankInstall or `dms setup --force` over this configuration. Chezmoi
already supplies the compositor integration. DMS starts **only** through
`spawn-at-startup "dms-with-lyrics" "run"`; do not also enable `dms.service`.
The launcher uses the prepared, version-matched media-page overlay when
available and otherwise runs the stock DMS shell. Install the launcher from
the [plugin repository](https://github.com/oai404iao/dms-plugins) before the
first DMS session; chezmoi neither deploys nor automatically fetches it.

The `run_after_check-dms-lyrics.sh.tmpl` apply hook runs only when `graphical`,
`niri`, and `desktopShell="dms"` are selected. It checks for `dms`, `qs`, and
`dms-with-lyrics`, then checks the launcher's `current/shell.qml` and
`.dms-version` contract under
`${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/`. Missing
dependencies, missing/incomplete preparation, version mismatches, or a failed
`dms version` produce actionable stderr reminders without failing apply.
Python is checked only when preparation is needed. Healthy setups stay silent;
unresolved reminders repeat on later applies. The hook directs preparation to
the separate plugin repository; it does not install, download, prepare,
restart, or inspect/change local plugin enablement.
Applies using `--exclude=scripts` skip these reminders as well.

## Configuration ownership

- Chezmoi owns Niri's main include graph, common input/window rules, profile
  startup, Kitty includes, GTK imports, and the Fcitx5 theme selector.
- Chezmoi merges `~/.config/DankMaterialShell/settings.json`: it owns the
  complete `barConfigs` (DankBar with DankDash), `barElevationEnabled=false`,
  `cornerRadius=16`,
  `widgetColorMode=default`, `runningAppsCurrentWorkspace=true`, and
  `matugenTemplateNeovim=true`. On a
  missing file it also seeds wallpaper-based colors, native clipboard paste,
  Adwaita Sans, and the idle policy below. Existing files keep every other
  preference, including machine-specific outputs, wallpaper, network, and
  battery settings. Applying again restores only the six owned fields;
  pre-seeding this file bypasses DMS's first-launch wizard.
- With the optional `tether=true` capability, the modifier also prepends an
  owned `no_history` rule for the exact `tether-gtk` desktop entry, preserving
  unrelated notification rules. Live notifications remain visible; previous
  history is not purged. See [Bluetooth iPhone notifications](tether.md) for
  manual setup, isolation, ownership, and disabling before a profile switch.
- DankBar uses `centerWidgets` for music, date/time, and weather in that order.
  In the customized shell, music contains visualization, playback controls,
  and the current lyric (or song title and artist) within one pill.
  Click or hover opens the tabbed DankDash panel; hover popouts use a 450 ms
  delay. The left/right sections retain the launcher, workspaces, focused
  window, and system status without duplicate music or weather widgets.
  The right section includes `dankTodo` after the clipboard; its installed
  plugin must be scanned and enabled separately as described below.
  The bar background is transparent and its shadow is disabled; individual
  widget backgrounds remain opaque.
- The separate [plugin repository](https://github.com/oai404iao/dms-plugins)
  owns `plugins/{lyrics,dankTodo}`, `scripts/prepare-dms-media-lyrics.py`,
  `scripts/dms-media-lyrics/`, `bin/dms-with-lyrics`, and their offline tests.
  All installed plugin directories, including `lyrics`, and the launcher are
  ignored by chezmoi. Plugin enablement/preferences in `plugin_settings.json`,
  plugin lockfiles, and `~/.config/dank-todo/` storage stay machine-local.
  Custom todo storage paths must also remain outside either source repository.
- The native media widget/page customization is prepared from that reviewed
  plugin checkout. Its complete generated DMS tree under
  `$XDG_DATA_HOME/dms-media-lyrics/` is machine-local, not a managed package.
- `~/.config/niri/dms/{binds,outputs,layout,cursor,colors,alttab,windowrules}.kdl`
  are create-only. DMS owns subsequent edits. Output selection and familiar
  window bindings are seeded from the same templates as custom mode. DMS
  Settings can reassign/remove bindings without leaving a second copy active.
  Their `create_empty_` attributes preserve empty fragments as well as edits:
  DMS writes an empty cursor fragment for defaults, and Niri still requires
  every included file to exist. Plain `create_` can delete these empty files.
  Input configuration remains in the common `conf.d/10-input.kdl`.
- Kitty's `dank-theme.conf` / `dank-tabs.conf` and GTK's `dank-colors.css`
  receive create-only fallbacks; DMS generates subsequent palettes. Both
  graphical profiles manage `gtk-4.0/nautilus.css` for Nautilus and its portal
  file chooser's 90%-opacity background, imported once after the profile's
  palette. GTK 4 uses `dank-colors.css` then `nautilus.css` in DMS, and
  `colors.css` then `nautilus.css` in custom; unrelated CSS survives switching.
  DMS mode does not force GTK's dark preference or enable legacy user templates.
  For an existing machine, follow the
  [reviewed two-target style update](desktop.md#nautilus-background-style).
  Reopen GTK applications after changing palettes if they do not refresh.
  Apply does not automatically quit applications.
- The initial dynamic palette uses Matugen's `scheme-neutral`: wallpaper hue
  remains, with less saturated accents and backgrounds. Terminals stay dark
  even when the shell switches to light mode. Kitty includes the declarative
  `dms-ansi.conf` after DMS's generated files for soft, stable ANSI colors;
  foreground, background, selection, tabs, and links still follow DMS. This
  does not enable the legacy user Matugen templates. Existing DMS installations
  can select **Neutral** and **Terminals - Always use Dark Theme** in Settings;
  the seed does not reset existing preferences outside the six owned fields.
- Chezmoi merges Qt6ct's `Appearance` palette path
  (`colors/matugen.conf` under this machine's home), custom palette, Adwaita
  icon theme, Fusion style, and `Fonts` settings. Other sections and keys
  remain local; DMS still generates the palette file itself. Without
  an icon theme, Qt can fall back to `hicolor`, where Fcitx5's
  `input-keyboard-symbolic` is missing (a purple/black placeholder in the tray).
  DMS's Niri environment selects
  `QT_QPA_PLATFORMTHEME=qt6ct`. After changing the icon theme, run `dms restart`
  while unlocked: an existing Quickshell process can retain its old icon
  lookup state even when a newly launched Qt application finds the icons.
- Fcitx5 selects DMS's generated `dms` theme, without taking over input schemes
  or dictionaries. Its first palette is generated by DMS at runtime.
- DMS uses its **built-in** Matugen templates. `runUserMatugenTemplates=false`
  prevents old user templates from updating/reloading Waybar, Mako, swaylock,
  etc. Keep it disabled while the legacy `~/.config/matugen/config.toml`
  remains. The existing repository's `[config.wallpaper]` has `set=false`;
  it does not launch awww when DMS reads that config. Review additional
  machine-local `~/.config/matugen/dms/configs/` templates separately: DMS can
  execute these even when user templates are disabled.
- btop is not a built-in DMS template. Chezmoi deploys only
  `matugen/dms/configs/chezmoi-btop.toml` and the shared `btop.theme` input in
  DMS mode. DMS generates `~/.config/btop/themes/matugen.theme` on theme changes;
  the hook sends `SIGUSR2` to this user's running btop instances to reload it.
  The generated theme remains create-only, and other DMS custom templates
  remain machine-local. Existing machines can apply these two explicit inputs
  without enabling `runUserMatugenTemplates` or restarting DMS; the next
  wallpaper/theme change regenerates the btop palette.
- fastfetch uses `matugen/dms/configs/chezmoi-fastfetch.toml` and the shared
  `fastfetch-config.jsonc` input. DMS owns the generated full
  `~/.config/fastfetch/config.jsonc`; local layout edits belong in the template,
  not in that output.
- Neovim's built-in DMS template is enabled by the settings modifier.
  The profile-aware LazyVim specification loads the pinned `AvengeMedia/base46`
  plugin and selects `dms`, with `tokyonight` as a fresh-machine fallback
  until DMS first generates the palette. DMS owns `nvim/colors/dms.lua` and
  `nvim/lua/lualine/themes/dms.lua`, including their upstream hot-reload logic;
  these files remain ignored. Install only the new pinned plugin when migrating,
  without updating other locked plugins. The specification renders empty
  for custom/headless profiles, so switching away from DMS retires it even
  when generated palettes remain on disk.
- Custom-only files become ignored in DMS mode, not deleted. CopyQ history
  remains untouched and is not imported into DMS. DMS clipboard data,
  notifications, night-mode/wallpaper session state, downloaded plugins, and
  caches stay machine-local; never recursively add these directories to chezmoi.

If DMS was already configured before adopting this profile, back up and review
its current settings before applying the modifier. In particular, check
`runUserMatugenTemplates`, idle/lock settings, and any custom power commands:
those are only seeded on a new file, not changed in an existing file.

#### Legacy Matugen template coverage

Switching profiles does not migrate every entry in the custom
`matugen/config.toml`. Ignored old outputs can remain on disk without updating.

| Custom template | DMS equivalent / remaining integration |
|---|---|
| Kitty, Fcitx5, GTK3/4, Qt6ct, Niri | Built-in generation plus this profile's application configuration |
| Qt5ct, KDE color scheme | Built-in generation; application/backend selection is separate |
| Neovim (commented out in custom) | Built-in `dms` colorscheme enabled and selected by this profile's LazyVim/base46 integration |
| btop | This profile's narrow DMS template and live-reload hook |
| fastfetch | This profile's narrow DMS template; regenerated full configuration |
| Cava | No built-in replacement or DMS adapter here; old generated output does not follow DMS |
| Starship, Yazi, niriswitcher, Ghostty, Hyprland, Pywalfox | Removed from the custom Matugen configuration and inputs |
| Waybar, Fuzzel, Mako, wlogout, swayosd, swaylock-effects | Custom desktop components replaced by DMS UI; their old palettes are not regenerated |

Only migrate additional applications that are actually used. Generation alone
does not select a theme, and copying the complete old configuration would also
reactivate obsolete desktop hooks.

For a machine-local cleanup, back up and move only reviewed retired targets.
Disable the DMS Ghostty, Qt5ct, KDE color-scheme, Hyprland, and Pywalfox template switches
before removing their generated outputs, or DMS can recreate them. These
switches remain local preferences; the repository still supports the custom
desktop and does not uninstall packages during apply.

### Bilingual lyrics

The maintained `lyrics` and `dankTodo` plugins now live in
[oai404iao/dms-plugins](https://github.com/oai404iao/dms-plugins), along with
their offline tests, native media overlay, preparation helper, and launcher.
That repository documents upstream attribution, licenses, plugin behavior,
and implementation changes. Chezmoi no longer deploys any plugin or the
launcher; its apply hook only emits reminders.

The lyrics daemon shares one fetcher across displays. The version-matched
overlay integrates original/translated lyrics into the music pill and native
media page, retaining the native controls and a no-lyrics fallback. There is
no separate lyrics bar widget. Plugin preferences, enablement, lockfiles,
and todo storage remain machine-local.

#### Install on a fresh machine or migrate an existing installation

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

Before starting the DMS Niri session, explicitly clone and review the plugin
repository. The usual checkout is `~/Dev/local/dms-plugins` (on this machine,
`/home/hisir/Dev/local/dms-plugins`). For a new checkout:

```sh
mkdir -p ~/Dev/local
git clone https://github.com/oai404iao/dms-plugins.git ~/Dev/local/dms-plugins
cd ~/Dev/local/dms-plugins
git checkout --detach <reviewed-commit>
sh tests/check-source.sh
python3 scripts/install.py --dry-run
python3 scripts/install.py
```

Replace `<reviewed-commit>` with the reviewed revision; do not blindly update
an existing checkout or replace local edits. These test and install commands
run from the plugin repository, **not** the chezmoi source directory.

The installer symlinks **both** `plugins/lyrics` and `plugins/dankTodo` into
`${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins/`, plus
`bin/dms-with-lyrics` into `~/.local/bin/`. Existing targets are renamed into
a fresh private retained `~/.local/state/agents/tmp/dms-plugins-install.*`
backup directory before replacement. Review the dry run first. The installer
does not fetch updates, prepare the overlay, enable plugins, or restart DMS.
Keep the checkout at its installed location so the symlinks remain valid.

For migration, save work and stop DMS while unlocked before replacing active
plugin sources. Keep existing plugin preferences and todo data; do not copy
them into either Git repository. Do not use `dms plugins install`, `update`,
or `restore` to overwrite these maintained targets. Update the reviewed
checkout and run its tests instead.

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

#### Native media-page overlay

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

After a DMS package upgrade, stop the old shell and launch through
`dms-with-lyrics` again: a version mismatch falls back to stock DMS.
Do **not** rely on `dms restart` alone for this check, because an existing
supervisor retains its old environment. Re-review/rebase the overlay and
hashes before preparing for a new DMS version. Stock DMS remains usable after
fallback, but displaying these integrated lyrics requires the custom overlay.

To return to stock immediately:

```sh
dms kill
niri msg action spawn -- /usr/bin/env -u DMS_SHELL_DIR /usr/bin/dms run
```

To make that permanent, restore the Niri startup source to
`spawn-at-startup "dms" "run"` and apply that explicit target. Neither rollback
requires deleting the prepared trees or moving startup to `dms.service`.

### Idle and lock defaults

On AC and battery: lock after 300 seconds idle, then use DMS's 30-second
post-lock display-off timer. Independent unlocked display-off and automatic
suspend timers are disabled. Lock-before-suspend and loginctl integration are
enabled; the pre-lock fade/grace period is disabled.

The lock-and-display-off shortcut calls DMS's `lockAndOutputsOff`, which waits
for its session lock before powering displays off, rather than chaining
asynchronous shell commands. Authentication and suspend/resume still require
an interactive check on the real machine; offline config validation cannot
prove successful PAM authentication. Do not run two lockers or idle daemons.

Night mode is owned entirely by DMS. `Mod+Alt+N` toggles it; its default warm
temperature is 4500 K. Schedule and temperature choices live in DMS's mutable
session state, not in the declarative settings seed. Do not run gammarelay,
gammastep, or another gamma controller alongside it.

### Initial DMS shortcuts

| Shortcut | Action |
| --- | --- |
| `Mod+D`, `Alt+Space` | Launcher |
| `Mod+F2` | Settings |
| `Mod+Alt+V` | Clipboard |
| `Mod+N` | Notification center |
| `Mod+Y` | Wallpaper selection |
| `Mod+Alt+N` | Night mode |
| `Mod+Alt+M` | Task manager |
| `Super+Alt+L` | Lock and turn off displays |
| `Mod+Shift+E`, `Ctrl+Alt+Delete` | Power menu |
| `Print`, `Ctrl+Print`, `Alt+Print` | Region, focused output, focused window screenshot |
| Volume, microphone, brightness, media keys | DMS controls / OSD |

Niri movement, workspace, column, and floating shortcuts retain their original
keys. In particular, `Mod+V`, `Mod+M`, and `Mod+Comma` are not repurposed.

## Switch an existing machine

1. Save work and **log out of Niri**, then use a TTY for the transition.
   Niri reloads configuration immediately, but `spawn-at-startup` is not rerun
   on reload. Applying mid-session would mix new bindings with old processes.
2. Review `systemctl --user list-unit-files` and
   `~/.config/autostart/` for independent DMS, Waybar, Mako, CopyQ, awww,
   Waypaper, or swayidle startup. Disable only reviewed conflicting entries.
   In particular, remove previously enabled `dms.service` or
   `niri.service.wants/swayidle.service` startup; this repository owns startup
   through Niri. Stop any surviving `waybar-gammarelay.service` before DMS
   takes gamma control. Ignoring its unit file does not stop a running service.
3. Back up `~/.config/chezmoi/chezmoi.toml` and each pre-existing target below
   into a private, retained machine-local directory before changing ownership.
   Include custom component configs when switching back; do not copy clipboard
   histories or other personal state into the repository.
4. Set `desktopShell` deliberately via `chezmoi edit-config`.
   Before entering DMS, follow the [plugin setup](#bilingual-lyrics) to install
   both plugins and the launcher from a reviewed checkout. Prepare a matching
   overlay when using integrated lyrics. Chezmoi apply cannot install the
   missing launcher or repair its symlink.
5. Preview and apply **only** the selected desktop targets. For DMS:

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=encrypted \
     ~/.config/niri ~/.config/kitty ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
     ~/.config/fcitx5/conf/classicui.conf \
     ~/.config/DankMaterialShell/settings.json ~/.config/qt6ct/qt6ct.conf

   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/niri ~/.config/kitty ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
     ~/.config/fcitx5/conf/classicui.conf \
     ~/.config/DankMaterialShell/settings.json ~/.config/qt6ct/qt6ct.conf
   ```

   Existing DMS settings can contain personal paths; inspect that target locally,
   not in shared logs. The Bar layout and Qt6ct fields above will be replaced;
   back up both targets first. Create missing target parent directories if
   chezmoi reports an absent parent for an explicit file target. Restart DMS
   after applying to refresh its generated Niri corners and Qt icon state.
6. Run `niri validate --config ~/.config/niri/config.kdl`, then start a fresh
   `niri-session`. Do not start DMS manually as well.
7. Open Settings and select a wallpaper. Test notifications, clipboard paste,
   audio/brightness, night mode, and application palettes. Test lock/unlock
   before leaving the machine unattended, then test suspend/resume separately.

### Return to custom

Follow the same logout/backup/review procedure and set `desktopShell="custom"`.
Apply the common targets above **without** the DMS and Qt6ct targets, plus:

```sh
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/fuzzel ~/.config/mako ~/.config/waybar ~/.config/waypaper \
  ~/.config/matugen ~/.config/swaylock \
  ~/.config/systemd/user/waybar-gammarelay.service \
  ~/.local/share/fcitx5/themes/Matugen
```

Review their targeted diff before applying. Run `systemctl --user daemon-reload`
after restoring the gamma unit. Disable independent DMS autostart if previously
enabled, and ensure DMS is stopped before logging into custom.
Reapply a wallpaper through Waypaper to regenerate custom colors; `create_`
fallbacks deliberately do not overwrite old generated palettes. DMS-generated
files can stay on disk: custom no longer includes them. No packages or histories
need to be deleted, and DMS GUI preferences survive the round trip.

## Validation

`tests/check-desktop-profiles.sh` renders both shells across every output
profile, validates Niri, checks init choices, legacy/default and headless
behavior, verifies selective DMS/Qt6ct merges, GTK import switching, and
generated-file preservation, and
excludes runtime state. It does not start DMS, lock the screen, change services,
or access the real credential backend.

`tests/check-dms-apply-hints.sh` renders the reminder hook across profiles
and checks healthy silence, missing dependencies/launcher/prepared trees, version
mismatches, and command failures. It never starts a real shell.

Plugin logic, QML, todo persistence, overlay preparation, and launcher tests
belong to [dms-plugins](https://github.com/oai404iao/dms-plugins). Run
`sh tests/check-source.sh` from its reviewed checkout before installing or
updating it. Those tests use offline fixtures; they do not prove native
Wayland popup focus, real provider availability, or live desktop behavior.

Run `./tests/check-source.sh` and `git diff --check` before applying.

References:
[installation](https://danklinux.com/docs/dankmaterialshell/installation),
[Niri integration](https://danklinux.com/docs/dankmaterialshell/compositors),
[application themes](https://danklinux.com/docs/dankmaterialshell/application-themes),
and [DMS v1.6.2 → v1.6.3 changes](https://github.com/AvengeMedia/DankMaterialShell/compare/v1.6.2...v1.6.3).

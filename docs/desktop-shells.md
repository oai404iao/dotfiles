# Desktop shell profiles

Choose who owns the desktop UI before applying Niri configuration. The
`custom` stack coordinates separate tools; `dms` delegates those responsibilities
to Dux Shell (formerly DankMaterialShell). The profile name remains `dms`.
Both use the same compositor and shared desktop services.

For a new machine, [prepare the selected packages](#selection-and-packages)
and choose a profile during initialization. For an existing machine, follow
[Switch an existing machine](#switch-an-existing-machine), including logout,
backups, and retained-service checks. Changing the data value alone is not a
safe live switch.

## Compare the profiles

| Responsibility | `custom` | `dms` |
| --- | --- | --- |
| Bar / launcher / notifications | Waybar / Fuzzel / Mako | DMS |
| Wallpaper / palette orchestration | awww / Waypaper / user Matugen templates | DMS wallpaper and built-in Matugen templates |
| Clipboard history | CopyQ | DMS native clipboard (no cliphist watcher) |
| Idle / lock / sleep integration | swayidle / swaylock-effects | DMS |
| Color temperature | waybar-gammarelay.service | DMS night mode |
| Screenshot shortcuts | Niri / Satty helper | DMS screenshot |
| Power / resource UI | Waybar actions / wlogout | DMS power menu / dux-gop |

DMS still depends on Quickshell, Matugen for generated palettes, and system
services such as PipeWire, NetworkManager, and BlueZ. It replaces the desktop
frontends and their coordination, not those underlying services. Niri, Kitty,
Fcitx5, fonts, locale, portals, and GNOME Keyring remain shared.

## Selection and packages

### Choose machine data

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

### Prepare DMS packages

The configuration targets Dux Shell 2.0 and native lyrics. This source update
does not establish live desktop or bilingual-lyrics parity with the old overlay.
Arch packages the shell as `dux-shell` and its process monitor as `dux-gop`.
Install separately; inspect any system upgrade transaction before accepting:

```sh
sudo pacman -Syu --needed dux-shell dux-gop matugen wtype qt6ct \
  adw-gtk-theme adwaita-icon-theme
```

[`extra/dux-shell`](https://archlinux.org/packages/extra/x86_64/dux-shell/)
replaces `dms-shell`; `extra/dux-gop` replaces `dgop`. The shell command and
user unit remain `dms` and `dms.service`. The upstream
[2.0 release notes](https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.0.0)
describe the rebranding and configuration-path changes. Chezmoi now targets
`~/.config/dms/settings.json`. Keep `desktopShell = "dms"`; review
[existing configuration paths](#review-existing-dux-configuration) before deployment.

The optional legacy lyrics overlay supports only DMS 1.6.2 and 1.6.3, not 2.0.
It is no longer required or started by this profile. Do not prepare it against
2.0 or bypass its version/hash checks.

Quickshell and accountsservice are pulled in as dependencies. Existing shared
desktop dependencies still apply. Cava and qt6-multimedia enable visualization
and sound feedback. See [custom dependencies](desktop.md#runtime-dependencies)
for the other profile. Keeping both package sets installed is supported.

Do not run DankInstall or `dms setup --force` over this configuration. Chezmoi
already supplies the compositor integration. DMS starts **only** through
`spawn-at-startup "env" "-u" "DMS_SHELL_DIR" "dms" "run"`; do not also enable
`dms.service`. Clearing the inherited overlay selector ensures native startup
even if an older session exported it. No external launcher is required.
Chezmoi does not install or enable plugins or lyrics providers.

### Review existing Dux configuration

This adoption is **source-only**: no apply, restart, installation, or live
directory cleanup is part of it. The deployment commands below are for a later,
explicitly authorized transition.

Both `~/.config/DankMaterialShell/settings.json` and
`~/.config/dms/settings.json` have been observed locally; Dux reports a
migration conflict when both configuration directories exist. Before deployment,
privately back up both directories and review their settings and personal state.
The reviewed new `dms` configuration is canonical. The old directory is ignored
by chezmoi, not automatically merged, renamed, or deleted. Decide separately
which old-only preferences or plugin data to retain and when to retire the
duplicate path. Do not blindly merge directories or replace them with a symlink;
apply only the reviewed new settings target. No compatibility migration or
overlay-preparation hook runs during apply.

## Configuration ownership

Chezmoi owns Niri's include graph, common input/window rules, profile startup,
Kitty includes, GTK imports, and the Fcitx5 theme selector. Not every file in
those directories is overwrite-managed:

| Target | Apply behavior | Owner afterward |
|---|---|---|
| `dms/settings.json` | Merge declared fields below; seed defaults only for a missing file | Chezmoi for declared fields; DMS for other preferences |
| `DankMaterialShell/` | Ignored, no migration or cleanup | Retained local configuration |
| `niri/dms/*.kdl` | Create-only, including empty fragments | DMS Settings |
| Kitty / GTK generated palette files | Create-only fallback | DMS |
| Qt6ct configuration | Merge declared appearance/font fields | Chezmoi for declared keys; local for the rest |
| Installed plugins, launcher, preferences, data | Ignored, never auto-fetched | Reviewed plugin checkout / local runtime |
| Custom-only configuration | Ignored in DMS, not deleted | Retained on disk for rollback |

Configuration paths in the table are under `~/.config/`. Optional plugin and
legacy launcher ownership is described in [plugin setup](dms-plugins.md).

### Settings restored on every apply

The settings modifier owns:

| Field | Managed value |
|---|---|
| `barConfigs` | Complete DankBar layout with DankDash |
| `barElevationEnabled` | `false` |
| `radiusMode` / `radiusStrength` | `scale` / `50`, preserving the old 16px base-radius intent |
| `widgetColorMode` | `default` |
| `matugenTemplateNeovim` | `true` |

A missing file receives schema version 42, wallpaper-based colors, native
clipboard paste, Adwaita Sans, and [the idle defaults](#idle-and-lock-defaults). This pre-seeding
bypasses DMS's first-launch wizard. Existing files retain other preferences,
including machine-specific outputs, wallpaper, network, and battery settings.
Existing schema versions are preserved for Dux's own migrations. The modifier
stops emitting legacy `cornerRadius` and global `runningAppsCurrentWorkspace`,
but does not delete existing keys or implement a migration shim. The bar keeps
supported widget string IDs. Widget-specific options such as
`runningAppsCurrentWorkspace` now belong to widget objects; no running-apps
widget is present here, so that option is no longer managed. Unrelated user
preferences remain intact.

**Before adopting an existing DMS installation**, back up and review settings,
especially `runUserMatugenTemplates`, idle/lock settings, and custom power
commands. These are seeded only on a new file; apply does not repair existing
unsafe or incompatible choices automatically.

With optional `tether=true`, the modifier also prepends an owned `no_history`
rule for the exact `tether-gtk` desktop entry while preserving unrelated rules.
Live notifications remain visible; previous history is not purged. Follow
[Tether setup and retirement](tether.md) before changing its service or profile.

### Bar, plugins, and runtime state

DankBar uses `centerWidgets` for music, date/time, and weather in that order.
Music uses Dux's native widget and media page, without a prepared shell overlay.
Lyrics availability depends on the local settings and providers; bilingual
display and live provider behavior have not been verified for this adoption.
Click or hover opens the tabbed DankDash panel; hover popouts use a 450 ms
delay. The left/right sections retain the launcher, workspaces, focused
window, and system status without duplicate music or weather widgets.
The right section retains the optional `dankTodo` slot after the clipboard;
using it needs a separately reviewed compatible plugin and local enablement.
The bar background is transparent and its shadow is disabled; individual
widget backgrounds remain opaque.

The separate [plugin repository](https://github.com/oai404iao/dms-plugins)
owns `plugins/{lyrics,dankTodo}`, `scripts/prepare-dms-media-lyrics.py`,
`scripts/dms-media-lyrics/`, `bin/dms-with-lyrics`, and their offline tests.
All installed plugin directories, including `lyrics`, and the launcher are
ignored by chezmoi. Plugin enablement/preferences in `plugin_settings.json`,
plugin lockfiles, and `~/.config/dank-todo/` storage stay machine-local.
Custom todo storage paths must also remain outside either source repository.

Old generated trees under `$XDG_DATA_HOME/dms-media-lyrics/` remain unmanaged
and unused by native startup. Neither they nor installed plugins are deleted.

Custom-only files are ignored, not deleted. CopyQ history remains untouched
and is not imported into DMS. DMS clipboard data, notifications, night-mode and
wallpaper state, downloaded plugins, and caches stay machine-local. Never
recursively add these directories to chezmoi.

### Niri fragments

`~/.config/niri/dms/{binds,outputs,layout,cursor,colors,alttab,windowrules}.kdl`
are create-only. DMS owns subsequent edits. Output selection and familiar
window bindings are seeded from the same templates as custom mode. DMS
Settings can reassign/remove bindings without leaving a second copy active.
Their `create_empty_` attributes preserve empty fragments as well as edits:
DMS writes an empty cursor fragment for defaults, and Niri still requires
every included file to exist. Plain `create_` can delete these empty files.
Input configuration remains in the common `conf.d/10-input.kdl`.
The window-rules fragment starts empty. Dux generates its own floating-window
rule for `dev.duxlabs.shell`; the main config does not duplicate it. Existing
fragments remain intact until Dux updates its generated rules at runtime.

### Application palettes

Kitty's `dank-theme.conf` / `dank-tabs.conf` and GTK's `dank-colors.css`
receive create-only fallbacks; DMS generates subsequent palettes. Both
graphical profiles manage `gtk-4.0/nautilus.css` for Nautilus and its portal
file chooser's 90%-opacity background, imported once after the profile's
palette. GTK 4 uses `dank-colors.css` then `nautilus.css` in DMS, and
`colors.css` then `nautilus.css` in custom; unrelated CSS survives switching.
DMS mode does not force GTK's dark preference or enable legacy user templates.
For an existing machine, follow the
[reviewed two-target style update](desktop-applications.md#nautilus-background-style).
Reopen GTK applications after changing palettes if they do not refresh.
Apply does not automatically quit applications.

The initial dynamic palette uses Matugen's `scheme-neutral`: wallpaper hue
remains, with less saturated accents and backgrounds. Terminals stay dark
even when the shell switches to light mode. Kitty includes the declarative
`dms-ansi.conf` after DMS's generated files for soft, stable ANSI colors;
foreground, background, selection, tabs, and links still follow DMS. This
does not enable the legacy user Matugen templates. Existing DMS installations
can select **Neutral** and **Terminals - Always use Dark Theme** in Settings;
the seed does not reset existing preferences outside the declared fields.

Chezmoi merges Qt6ct's `Appearance` palette path
(`colors/matugen.conf` under this machine's home), custom palette, Adwaita
icon theme, Fusion style, and `Fonts` settings. Other sections and keys
remain local; DMS still generates the palette file itself. Without
an icon theme, Qt can fall back to `hicolor`, where Fcitx5's
`input-keyboard-symbolic` is missing (a purple/black placeholder in the tray).
DMS's Niri environment selects
`QT_QPA_PLATFORMTHEME=qt6ct`. After changing the icon theme, run `dms restart`
while unlocked: an existing Quickshell process can retain its old icon
lookup state even when a newly launched Qt application finds the icons.

Fcitx5 selects DMS's generated `dms` theme, without taking over input schemes
or dictionaries. Its first palette is generated by DMS at runtime.

### Template adapters and reload behavior

DMS uses its **built-in** Matugen templates. `runUserMatugenTemplates=false`
prevents old user templates from updating/reloading Waybar, Mako, swaylock,
etc. Keep it disabled while the legacy `~/.config/matugen/config.toml`
remains. The existing repository's `[config.wallpaper]` has `set=false`;
it does not launch awww when DMS reads that config. Review additional
machine-local `~/.config/matugen/dms/configs/` templates separately: DMS can
execute these even when user templates are disabled.

btop is not a built-in DMS template. Chezmoi deploys only
`matugen/dms/configs/chezmoi-btop.toml` and the shared `btop.theme` input in
DMS mode. DMS generates `~/.config/btop/themes/matugen.theme` on theme changes;
the hook sends `SIGUSR2` to this user's running btop instances to reload it.
The generated theme remains create-only, and other DMS custom templates
remain machine-local. Existing machines can apply these two explicit inputs
without enabling `runUserMatugenTemplates` or restarting DMS; the next
wallpaper/theme change regenerates the btop palette.

fastfetch uses `matugen/dms/configs/chezmoi-fastfetch.toml` and the shared
`fastfetch-config.jsonc` input. DMS owns the generated full
`~/.config/fastfetch/config.jsonc`; local layout edits belong in the template,
not in that output.

Neovim's built-in DMS template is enabled by the settings modifier.
The profile-aware LazyVim specification loads the pinned `AvengeMedia/base46`
plugin and selects `dms`, with `tokyonight` as a fresh-machine fallback
until DMS first generates the palette. DMS owns `nvim/colors/dms.lua` and
`nvim/lua/lualine/themes/dms.lua`, including their upstream hot-reload logic;
these files remain ignored. Install only the new pinned plugin when migrating,
without updating other locked plugins. The specification renders empty
for custom/headless profiles, so switching away from DMS retires it even
when generated palettes remain on disk.

### Legacy Matugen template coverage

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

## Native lyrics and optional plugins

Native Dux lyrics are the selected default; the old bilingual overlay is not a
2.0 dependency. See [DMS plugins and native lyrics](dms-plugins.md) for optional
plugin ownership and legacy limitations. Chezmoi does not install, update, or
enable plugins or providers, and no bilingual-parity claim is made.

### Install on a fresh machine or migrate an existing installation

Follow the [configuration review](#review-existing-dux-configuration) before a
later deployment. Optional plugins are not prerequisites for the first session.

### Native media-page overlay

The [legacy overlay](dms-plugins.md#native-media-page-overlay) is limited to
1.6.2/1.6.3. Keep its implementation in the separate plugin repository.

## Idle and lock defaults

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

## Initial DMS shortcuts

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

This is a future manual deployment procedure, not part of a source-only update.

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
   If Tether is enabled and the destination profile will not use it, first
   [disable its user service](tether.md#disable-or-change-desktop-profiles).
3. Back up `~/.config/chezmoi/chezmoi.toml` and each pre-existing target below
   into a private, retained machine-local directory before changing ownership.
   Include custom component configs when switching back; do not copy clipboard
   histories or other personal state into the repository.
4. Set `desktopShell` deliberately via `chezmoi edit-config`.
   Before entering DMS, complete the [duplicate-path review](#review-existing-dux-configuration).
   Native startup needs `dms`, not the old plugin launcher or prepared tree.
5. Preview and apply **only** the selected desktop targets. For DMS:

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=encrypted \
     ~/.config/niri ~/.config/kitty ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
     ~/.config/fcitx5/conf/classicui.conf \
     ~/.config/dms/settings.json ~/.config/qt6ct/qt6ct.conf

   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/niri ~/.config/kitty ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
     ~/.config/fcitx5/conf/classicui.conf \
     ~/.config/dms/settings.json ~/.config/qt6ct/qt6ct.conf
   ```

   Existing DMS settings can contain personal paths; inspect that target locally,
   not in shared logs. The Bar layout and Qt6ct fields above will be replaced;
   back up both targets first. Create missing target parent directories if
   chezmoi reports an absent parent for an explicit file target. Use the fresh
   Niri login below to start Dux with the reviewed environment and regenerate
   its Niri rules and palettes; applying alone does not replace a supervisor.
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

Plugin logic, QML, todo persistence, overlay preparation, and launcher tests
belong to [dms-plugins](https://github.com/oai404iao/dms-plugins). Run
`sh tests/check-source.sh` from its reviewed checkout before installing or
updating it. Those tests use offline fixtures; they do not prove native
Wayland popup focus, real provider availability, or live desktop behavior.

Run `./tests/check-source.sh` and `git diff --check` before applying.

## Troubleshooting

| Symptom | Safe next step |
|---|---|
| DMS does not start | Check the installed `dms` command and native Niri startup; no plugin launcher is required |
| Two bars, lockers, or gamma controllers | Inspect independent units/autostart; follow the logout-based switch procedure |
| Lyrics are unavailable | Review native lyrics settings and providers locally; the legacy overlay is not compatible with 2.0 |
| Migration reports both configuration paths | Back up and privately review both; `dms/settings.json` is canonical, but source updates do not clean up the old path |
| Old custom palettes still exist | Expected: ignored is not deleted; only reviewed retired targets should be moved |
| A DMS setting changes back on apply | Check the declared fields and complete bar-layout ownership |
| Existing DMS retains old idle behavior | Defaults are seeded only for a missing settings file; review the live preferences yourself |
| Fcitx5 icon is a purple/black placeholder | Check Qt6ct's Adwaita icon theme, then restart DMS while unlocked |

Next: [application setup](desktop-applications.md),
[session setup](desktop-session.md), or [Tether](tether.md).

References:
[installation](https://danklinux.com/docs/dankmaterialshell/installation),
[Niri integration](https://danklinux.com/docs/dankmaterialshell/compositors),
[application themes](https://danklinux.com/docs/dankmaterialshell/application-themes),
and [Dux Shell 2.0](https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.0.0).

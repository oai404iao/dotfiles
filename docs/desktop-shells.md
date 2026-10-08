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
available and otherwise runs the stock DMS shell.

The `run_after_check-dms-lyrics.sh.tmpl` apply hook runs only when `graphical`,
`niri`, and `desktopShell="dms"` are selected. It checks for `dms` and `qs`,
then checks the launcher's `current/shell.qml` and `.dms-version` contract
under `${XDG_DATA_HOME:-$HOME/.local/share}/dms-media-lyrics/`. Missing
dependencies, missing/incomplete preparation, version mismatches, or a failed
`dms version` produce actionable stderr reminders without failing apply.
Python is checked only when preparation is needed. Healthy setups stay silent;
unresolved reminders repeat on later applies. The hook does not install,
download, prepare, restart, or inspect/change local plugin enablement.
Applies using `--exclude=scripts` skip these reminders as well.

## Configuration ownership

- Chezmoi owns Niri's main include graph, common input/window rules, profile
  startup, Kitty includes, GTK imports, and the Fcitx5 theme selector.
- Chezmoi merges `~/.config/DankMaterialShell/settings.json`: it owns the
  complete `barConfigs` (DankBar with DankDash), `barElevationEnabled=false`,
  `cornerRadius=16`,
  `widgetColorMode=default`, and `runningAppsCurrentWorkspace=true`. On a
  missing file it also seeds wallpaper-based colors, native clipboard paste,
  Adwaita Sans, and the idle policy below. Existing files keep every other
  preference, including machine-specific outputs, wallpaper, network, and
  battery settings. Applying again restores only the five owned fields;
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
  The bar background is transparent and its shadow is disabled; individual
  widget backgrounds remain opaque.
- Chezmoi owns the maintained `plugins/lyrics/` source, including its MIT
  license. Plugin enablement and preferences in `plugin_settings.json`,
  downloaded plugins, and plugin lockfiles remain machine-local.
- The native media widget/page customization is prepared from the reviewed
  `scripts/dms-media-lyrics/` source. Its complete generated DMS tree under
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
  receive create-only fallbacks; DMS generates subsequent palettes. DMS mode
  does not import the custom Nautilus CSS or force GTK's dark preference.
  Reopen GTK applications after changing palettes if they do not refresh.
- The initial dynamic palette uses Matugen's `scheme-neutral`: wallpaper hue
  remains, with less saturated accents and backgrounds. Terminals stay dark
  even when the shell switches to light mode. Kitty includes the declarative
  `dms-ansi.conf` after DMS's generated files for soft, stable ANSI colors;
  foreground, background, selection, tabs, and links still follow DMS. This
  does not enable the legacy user Matugen templates. Existing DMS installations
  can select **Neutral** and **Terminals - Always use Dark Theme** in Settings;
  the seed does not reset existing preferences outside the five owned fields.
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
- Custom-only files become ignored in DMS mode, not deleted. CopyQ history
  remains untouched and is not imported into DMS. DMS clipboard data,
  notifications, night-mode/wallpaper session state, downloaded plugins, and
  caches stay machine-local; never recursively add these directories to chezmoi.

If DMS was already configured before adopting this profile, back up and review
its current settings before applying the modifier. In particular, check
`runUserMatugenTemplates`, idle/lock settings, and any custom power commands:
those are only seeded on a new file, not changed in an existing file.

### Bilingual lyrics

The maintained lyrics service is based on
[Gm-aaa/dms-lyrics](https://github.com/Gm-aaa/dms-lyrics), commit
`2cea21b36a18ca83a930550e067088856f5d8863` (upstream 0.3.0).
Its original MIT license is deployed alongside the locally modified sources.
Do not use a registry update or the upstream installer to overwrite this
directory; update the reviewed source and tests here instead.

- Spotify and other MPRIS players supply playback metadata and position.
- NetEase is queried first for synchronized original lyrics and its supplied
  `tlyric` translation. LRCLIB is the original-only fallback.
- A single DMS daemon plugin supplies all displays; there is no separate
  lyrics bar widget or popout. The customized music widget prefers each
  line's supplied translation, then original lyrics, then song title/artist
  during instrumental gaps or when no lyrics are available.
- The native media page shows original and translated lines together using
  the service's `LyricsView` and model, without starting another fetcher.
- Its right-side lyrics button opens an external settings panel through the
  same overlay as the native volume/device controls, leaving lyrics visible.
  `showLyrics`
  controls the bar and page together and stops fetching while disabled.
  `showTranslation` switches both views to originals only when disabled.
  Preferences are saved in DMS's machine-local `plugin_settings.json`.
- Settings labels follow DMS's UI locale through `I18n.trFor` and the
  plugin-local `translations/zh_CN.json` catalog. English source strings are
  the fallback; UI language selection does not change lyric translations.
- The translation selector lists only what the current provider supplied.
  NetEase exposes one `tlyric` without a language tag, labelled **Provider
  translation**, not an invented language list. With no translated lines,
  the settings show an unavailable message instead of a selector.
- Translations match original timestamps within 200 ms, nearest pairs first,
  without reusing a translation or carrying it forward to unrelated lines.
  Missing, unsynchronized, and duplicate translations are omitted.
- No AI service, Spotify API key, or extra daemon is used. Public lyric
  providers receive the song metadata used for matching. Results are cached
  only in memory; availability and translated coverage depend on the provider.
  NetEase retains the upstream first-search-result selection, so alternative
  recordings or ambiguous titles can still return mismatched lyrics.
- Text width and source priority remain configurable in the lyrics settings.
  Choosing LRCLIB first can bypass NetEase translations.

On a fresh DMS machine, prepare the native overlay below, apply the reviewed
plugin and bar targets, then enable the service locally:

```sh
mkdir -p ~/.config/DankMaterialShell/plugins
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/DankMaterialShell/plugins/lyrics \
  ~/.config/DankMaterialShell/settings.json
dms ipc call plugin-scan scan
dms ipc call plugins enable lyrics
dms ipc call plugins status lyrics
```

Back up any pre-existing `plugins/lyrics/` directory and settings before
applying. When migrating from the standalone widget, remove only its old
`LyricsWidget.qml` after backing it up and confirming it is the managed
version. The `lyrics` entry is no longer part of `centerWidgets`. After
source updates, use `dms ipc call plugins reload lyrics`; if an imported
JavaScript file remains cached, restart DMS while unlocked.

#### Native media-page overlay

The QML files in `scripts/dms-media-lyrics/` are maintained derivatives
of DMS **v1.6.2**, commit `2db7646fe3ab47fddfdb8723f2da07d61a0d47ac`,
also reviewed against **v1.6.3**, commit
`4a87e8227daf0840b3376fd5e7f891f5900165a6`. Both releases have identical
`shell.qml` and five original media/dropdown components, so they share the
same overlay and exact source hashes. Other versions remain rejected.
The upstream MIT license is included beside it. It keeps DankDash's tabs,
progress bar, transport, player selection, volume, and output controls. When
the shared lyrics service has lyrics enabled and available, it places compact artwork
and song metadata on the left and a scrolling bilingual view on the right.
With no lyrics or without the enabled service, it uses the original layout.
The settings button stays available while lyric display is disabled, so the
user can turn it back on. Settings float outside the main panel on the same
side as native audio menus, with their shared dismissal and screen-edge bounds.
They do not replace the lyrics area.

DMS 1.6.2/1.6.3 has no plugin slot for this native page. The preparation script
copies a trusted, pristine shell tree, verifies its version and the hashes of
`shell.qml` and all five original media/dropdown components, then replaces
**only** those five components in the copy. It never edits `/usr/bin/dms`, package files, or the
read-only extracted shell. Source input must be trusted; these hashes are
compatibility guards, not a full-tree authenticity check.

Always use the complete tree from the installed, supported DMS version.
The helper records that input version in `.dms-version`; do not relabel an
old generated tree to pass the launcher check. Preparing from 1.6.3 preserves
its upstream fixes outside the five replaced components.

**Why not a plugin-only implementation?** The fetcher already is a daemon
plugin. DMS 1.6.3 supports separate plugin widgets/popouts, but its
[native media page](https://github.com/AvengeMedia/DankMaterialShell/blob/v1.6.3/quickshell/Modules/DankDash/MediaPlayerTab.qml)
selects built-in chrome directly, without a plugin insertion point.
A standalone lyrics widget would avoid the overlay but change the current
integrated experience. Retain the daemon plus small overlay for these releases.

The upstream 1.7 beta introduces native lyrics and
[lyrics-provider plugins](https://danklinux.com/docs/1.7/dankmaterialshell/plugin-development).
That is a candidate for retiring the overlay after a stable upgrade, not a
1.6.3 API. Verify bilingual original/translation display and provider behavior
before migrating; feature parity is not established. Do not install the beta
or replace the existing daemon just to bypass the version guard.

For the installed embedded-shell build, obtain its extraction path from
`qs list --all` while stock DMS is running, then:

```sh
python3 scripts/prepare-dms-media-lyrics.py /path/to/pristine/extracted/dms-shell
chezmoi apply --exclude=scripts,encrypted \
  ~/.local/bin/dms-with-lyrics \
  ~/.config/niri/conf.d/40-session.kdl \
  ~/.config/DankMaterialShell/plugins/lyrics
```

The helper and updated Niri startup entry take effect on the next login.
To switch immediately, first save work and ensure the session is unlocked;
`dms kill` briefly removes the shell, then launch its replacement:

```sh
dms kill
~/.local/bin/dms-with-lyrics run -d
```

Run the replacement with the desktop session's locale, not the English
interactive-shell locale, to preserve the UI language and date/time format.

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

To return to stock immediately, run `dms kill`, then
`env -u DMS_SHELL_DIR /usr/bin/dms run -d`. To make that permanent, restore the
Niri startup source to `spawn-at-startup "dms" "run"` and apply that explicit
target. Neither rollback requires deleting the prepared trees.

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

`tests/check-dms-lyrics.sh` uses Node.js when available to test lyric parsing,
translation alignment, provider fallback, caching, and stale requests with
fake HTTP responses. It never queries real music services. Without Node.js it
reports a skip; the desktop profile inventory checks still run.
`tests/check-dms-media-lyrics.sh` checks offline overlay preparation, source
version/hash rejection, generation preservation, and exact-version launcher
selection for both supported releases using fake DMS commands. It also checks
cross-version fallback rather than treating 1.6.2 and 1.6.3 trees as interchangeable.
When chezmoi is available, it renders the apply hook
across profiles and checks silent healthy setups, missing dependencies/trees,
version mismatches, and command failures. It never starts a real shell.
`tests/check-dms-lyrics-qml.sh` uses Qt 6's test runner when available to
instantiate the real lyrics service/view offscreen. Stubbed MPRIS and lyric
responses test startup, player removal, display preferences while paused,
language availability, disabled fetching, and shared view updates without
connecting to the real desktop or network. It also exercises the real media
overlay's external positioning, screen bounds, blur, hover tracking, and
settings availability without a player.

Run `./tests/check-source.sh` and `git diff --check` before applying.

References:
[installation](https://danklinux.com/docs/dankmaterialshell/installation),
[Niri integration](https://danklinux.com/docs/dankmaterialshell/compositors),
[application themes](https://danklinux.com/docs/dankmaterialshell/application-themes),
and [DMS v1.6.2 → v1.6.3 changes](https://github.com/AvengeMedia/DankMaterialShell/compare/v1.6.2...v1.6.3).

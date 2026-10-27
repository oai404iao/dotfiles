# Desktop configuration

Use this repository to configure a Niri desktop with either independent
components (`custom`) or Dux Shell (`dms`, formerly DankMaterialShell).
Packages and system services must already be prepared: chezmoi deploys
configuration, not a desktop installer.

Choose the guide for your task:

| Task | Guide |
|---|---|
| Select DMS, switch stacks, or return to custom | [Desktop shell profiles](desktop-shells.md) |
| Set up fonts, GTK, Nautilus, input methods, or application themes | [Desktop applications](desktop-applications.md) |
| Configure locale, English folders, sudo dialogs, or the keyring | [Desktop session setup](desktop-session.md) |
| Understand native lyrics or optional plugins | [DMS plugins and native lyrics](dms-plugins.md) |
| Forward iPhone notifications or opt into clipboard sharing | [Tether](tether.md) |

The palette, Waybar, and temperature procedures below are for **custom**.
DMS uses its own wallpaper, palette, locking, and night-mode controls. Fonts,
locale, portals, Kitty, Fcitx5, and the keyring remain shared.

## Prepare a desktop

1. Review the [runtime dependencies](#runtime-dependencies) for your chosen
   shell and install them separately.
2. On a new machine, select `graphical=true`, `niri=true`, and the desktop shell
   during initialization. Missing `desktopShell` keeps `custom`. On an existing
   machine, follow [the switching procedure](desktop-shells.md#switch-an-existing-machine)
   instead of rerunning init or applying mid-session.
3. Prepare [session prerequisites](desktop-session.md) and
   [application dependencies](desktop-applications.md). Dux starts natively;
   no external lyrics launcher or plugin is required.
4. Back up existing targets privately, run the offline source checks, and
   review only explicit desktop paths before applying them. Do not use a
   whole-home apply as a validation step.
5. Start a fresh Niri session. Test the lock screen and suspend/resume yourself;
   rendering a valid configuration does not prove authentication works.

## Custom wallpaper and palettes

Change a wallpaper through Waypaper to regenerate custom colors. Do not force
chezmoi to overwrite existing generated palettes when refreshing a theme.

| Owner | Files or state |
|---|---|
| Chezmoi | Hand-written Kitty, Fuzzel, Mako, Waybar, Matugen, and Niri configuration |
| Fontconfig / GTK settings | Generic font stacks / application UI font |
| Matugen | Generated color files after their first creation |
| Waypaper | Selected-wallpaper state after its first creation |
| Applications | Caches, histories, databases, and downloaded plugins; never source state |

Generated color files use chezmoi's `create_` attribute. This gives a fresh
machine a valid fallback without reverting colors after Matugen changes them:

- `~/.config/kitty/current-theme.conf`
- `~/.config/kitty/themes/matugen.conf`
- `~/.config/fuzzel/colors.ini`
- `~/.config/mako/colors.conf`
- `~/.config/niri/colors.kdl`
- `~/.config/waybar/colors.css`
- `~/.config/btop/themes/matugen.theme`
- `~/.local/share/fcitx5/themes/Matugen/theme.conf`
- `~/.config/swaylock/config`
- `~/.config/gtk-3.0/colors.css`
- `~/.config/gtk-4.0/colors.css`

Kitty's themes kitten copies the generated `themes/matugen.conf` to
`current-theme.conf`, maintains its marked include block, and hot-reloads
running Kitty instances. Waybar watches its imported `colors.css` through
`reload_style_on_change`; Matugen does not send `SIGUSR2`, which would reset
and rebuild the bars.

Waypaper runs `~/.config/waypaper/apply-theme` without interpolating the
wallpaper filename into a shell command. The hook reads the active image from
`awww query --json` and invokes Matugen with an argument vector.

## Manual color temperature

Use the Waybar module next to brightness to adjust every connected display.
Hardware brightness is unchanged. If outputs differ, the displayed Kelvin
value is their average.

1. Install `wl-gammarelay-rs` separately (`yay -S wl-gammarelay-rs` on Arch).
2. Back up and review `~/.config/systemd/user/waybar-gammarelay.service`
   before applying that target.
3. Run `systemctl --user daemon-reload` and reload Waybar. Do not enable the
   unit or add another Niri startup command: the helper starts it on demand.

| Action | Result |
|---|---|
| Scroll up | +100 K, cooler |
| Scroll down | −100 K, warmer |
| Left-click at 6500 K | Switch to 4500 K |
| Left-click at any other temperature | Return to 6500 K |

The module is hidden when its dependencies are missing. Temperature is
session-local: restarting the service resets it to 6500 K. Do not run
wlsunset, gammastep, or another gamma controller alongside it. Output/driver
support is required; a changing number does not prove the display accepted it.

### Service behavior

Waybar polls the temperature over D-Bus every two seconds. Its helper starts
the user unit `waybar-gammarelay.service` before reading the value, with a
three-second timeout for each command. Finite queries avoid the continuous
custom-module teardown race observed with Waybar 0.15.0 during monitor
disconnects. The unit waits for D-Bus ownership and owns gamma control
independently of the bars. No Niri startup entry or `systemctl enable` is
needed; the service stops with the graphical session. Event commands do not
trigger extra queries; a failed query is retried at the next interval.

Upstream references:
[wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) and
[Waybar custom modules](https://github.com/Alexays/Waybar/blob/master/man/waybar-custom.5.scd).

## Runtime dependencies

This is the custom stack's dependency reference, not a package installer.
For DMS's replacement components and dependencies, use
[Selection and packages](desktop-shells.md#selection-and-packages).

| Use | Packages / commands |
|---|---|
| Compositor and custom UI | niri, kitty, fuzzel, waybar, mako |
| Custom lock, idle, clipboard | swaylock (styled for swaylock-effects), swayidle, copyq |
| Custom wallpaper and colors | awww, waypaper, matugen |
| Media and brightness | wireplumber (`wpctl`), playerctl, brightnessctl |
| Shared fonts | fontconfig, adwaita-fonts, noto-fonts, noto-fonts-extra, noto-fonts-cjk, noto-fonts-emoji, ttf-jetbrains-mono-nerd |
| GTK 3 theme | adw-gtk-theme |
| Shared portals | xdg-desktop-portal, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk |
| Shared keyring | gnome-keyring, libsecret, seahorse |
| Optional capture / clipboard actions | grim, slurp, satty, wl-clipboard, wf-recorder |
| Optional Waybar actions | ddcutil, hyprpicker, pavucontrol, wlogout, blueberry |
| Manual color temperature | wl-gammarelay-rs, systemd (`busctl`) |
| Long-screenshot helper | uv |
| Additional application adapters | btop, Fcitx5 with fcitx5-rime, Nautilus |

Satty and swaylock-effects styling is also managed. All packages are installed
separately; source checks do not install or start them.

Kitty scrollback integration also expects
`mikesmithgh/kitty-scrollback.nvim`, installed by the Neovim configuration.

## Output profiles

`niriOutputProfile` defaults to `auto` for unknown hardware. The
`desktop-single-4k` profile matches the P275MV by its monitor identity rather
than its connector name and selects 3840x2160 at 120 Hz with 1.5 scaling.

In DMS mode this profile seeds `~/.config/niri/dms/outputs.kdl` only once;
subsequent output edits belong to DMS Settings. The procedure below applies
to custom mode.

To change an initialized **custom** machine:

1. Back up the local chezmoi config and existing output target privately.
2. Run `chezmoi edit-config` and set
   `niriOutputProfile = "desktop-single-4k"` under the existing `[data]` section.
3. Review and apply only the output target, then ask Niri to reload:

```sh
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/niri/conf.d/20-outputs.kdl
chezmoi apply ~/.config/niri/conf.d/20-outputs.kdl
niri msg action load-config-file
```

## Validation

Run source checks from the repository root. The remaining commands are manual
configuration checks on a prepared desktop; replace the wallpaper placeholder.

```sh
./tests/check-source.sh
git diff --check
fuzzel --check-config
matugen --dry-run image /path/to/wallpaper
niri validate --config ~/.config/niri/config.kdl
chezmoi diff --skip-secrets --exclude=encrypted ~/.config/niri
```

Source checks do not install packages or start a desktop. Optional rendering,
GTK, and compositor checks can skip when their dependencies are absent.

## Troubleshooting

| Symptom | Check |
|---|---|
| Theme colors revert or stop following wallpaper | Edit the generator/template, not a generated `create_` target; select the wallpaper again |
| Wrong bar, notifications, or gamma controller after switching | Follow [startup and rollback checks](desktop-shells.md#switch-an-existing-machine); ignored services are not stopped |
| Chinese desktop but English GUI launched from a terminal | Use [the `gui` helper](desktop-session.md#locale-split) |
| Missing or misaligned glyphs | Check [fonts and Waybar icon alignment](desktop-applications.md#fonts) |
| Number changes but display temperature does not | Verify output/driver gamma support and that no second controller is running |

## Related setup

Older links into this page remain available below. The detailed procedures now
live in the application and session guides.

## Graphical sudo prompts

See [graphical sudo prompts](desktop-session.md#graphical-sudo-prompts).

## Fonts

See [fonts](desktop-applications.md#fonts).

## Waybar icon alignment

See [waybar icon alignment](desktop-applications.md#waybar-icon-alignment).

## Desktop applications

See [desktop applications](desktop-applications.md#application-behavior).

## Nautilus background style

See [Nautilus background style](desktop-applications.md#nautilus-background-style).

## Nautilus copy-path scripts

See [Nautilus copy-path scripts](desktop-applications.md#nautilus-copy-path-scripts).

## GTK theme prerequisites

See [GTK theme prerequisites](desktop-applications.md#gtk-theme-prerequisites).

## File chooser portal

See [file chooser portal](desktop-applications.md#file-chooser-portal).

## Bruno on Niri

See [Bruno on Niri](desktop-applications.md#bruno-on-niri).

## Desktop keyring

See [desktop keyring](desktop-session.md#desktop-keyring).

## Locale split

See [locale split](desktop-session.md#locale-split).

## XDG user directories

See [XDG user directories](desktop-session.md#xdg-user-directories).

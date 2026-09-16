# Desktop configuration

The desktop profile is intentionally split by ownership:

- chezmoi owns hand-written Kitty, Fuzzel, Mako, Waybar, Matugen, and Niri
  configuration.
- Fontconfig owns the generic application font stacks, while GTK settings
  select the UI font.
- Matugen owns generated color files after their first creation.
- Waypaper owns its selected-wallpaper state after its first creation.
- Application caches, histories, databases, and downloaded plugins stay out of
  source state.

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

## Fonts

Graphical profiles install `~/.config/fontconfig/fonts.conf` with these generic
stacks:

- `sans-serif`: Adwaita Sans, Simplified Chinese Noto Sans, color emoji, then
  Noto symbols;
- `serif`: Noto Serif, Simplified Chinese Noto Serif, color emoji, then Noto
  symbols;
- `monospace`: JetBrainsMono Nerd Font Mono, Simplified Chinese Noto Sans Mono,
  color emoji, then Noto symbols.

Strong Fontconfig aliases keep the primary Latin family stable under the
Chinese session locale while retaining per-character fallback.
Kitty and the generic monospace alias use JetBrainsMono Nerd Font Mono for
predictable one-cell widths. Waybar uses JetBrainsMono Nerd Font Propo so icon
layout advances match their drawn widths, without shrinking icons to one cell.
GTK and browser UI explicitly use
Adwaita Sans instead, avoiding the observed private-use codepoint collision in
Waybar's primary font. The GTK 2 modifier replaces only `gtk-font-name` and
preserves the target's other legacy settings. Browsers use the GTK UI setting
and Fontconfig generic families; a website or browser profile that names a
specific font still takes precedence.

On Arch Linux, install the required font providers:

```sh
sudo pacman -S --needed \
  fontconfig adwaita-fonts noto-fonts noto-fonts-extra noto-fonts-cjk \
  noto-fonts-emoji ttf-jetbrains-mono-nerd
```

A package that declares `provides = noto-fonts` can supply the base Noto
families instead.

### Waybar icon alignment

The font choice follows
[shorin-niri's Waybar style](https://github.com/SHORiN-KiWATA/shorin-niri/blob/main/dotfiles/.config/waybar/style.css).
The plain `JetBrainsMono Nerd Font` variant can draw icons beyond their layout
cells, shifting them relative to hover backgrounds and crowding adjacent text.
Use the installed `Propo` family rather than compensating with spaces or
asymmetric launcher padding. Workspace hover transitions change only colors;
GTK theme gradients and text shadows are disabled on those buttons. Reserve
workspace icon width on the label itself: Niri's non-expanding label would
otherwise sit at the left of a wider button.

The launcher uses upstream's `` (U+F303) Arch icon. Newer Waybar custom modules
use `AIconLabel`, which places the module ID on a box rather than the label.
Its child label must inherit the module's minimum width and font size;
otherwise the global font rule resets the glyph size and the wider box leaves
unused space on the right. Desktop checks exercise both widget structures when
GTK 3 Python bindings and a display are available.

Waybar uses logical dimensions; Niri applies each output's scale. At 150%,
a logical offset is magnified and rounding can add a small visual difference.
Keep relative spacing rather than adding resolution-specific pixel offsets.
Check the selected family with `fc-match 'JetBrainsMono Nerd Font Propo'`.
Tray and privacy icons are images, not Nerd Font glyphs; their internal margins
depend on the supplied artwork.

## Desktop applications

- Satty starts with the arrow tool and uses Adwaita Sans with Chinese fallback.
  Enter saves the edited file and exits; Escape exits without saving. The
  screenshot helpers supply output paths and copy saved edits after Satty exits.
  Standalone use needs `--output-filename` for Enter-to-save; the copy button
  remains available.
- btop selects the generated `matugen` theme through a modifier. Its other
  preferences, including layout and update interval, remain application-owned.
- Fcitx5 Classic UI selects Matugen, uses Adwaita Sans 11, and keeps native
  fractional scaling without forcing DPI. Its modifier preserves candidate
  orientation, tray preferences, and unknown keys. Input groups, Rime schemes,
  dictionaries, and learned words remain unmanaged. Outlined monochrome menu
  assets stay visible on both normal and selected backgrounds.
  Matugen reloads a running Fcitx instance rather
  than replacing the process.
- swaylock-effects keeps the existing blurred screenshot background, with a
  smaller indicator, thin ring, matching text colors, and a compact clock.
  The Matugen template owns the full configuration; no grace period is enabled.
  Blurred screenshots are not an opaque privacy screen. Lock-before-sleep and
  lock-before-monitor-off ordering stays in Niri.
- Nautilus remains the graphical file manager. GTK 3/4 import the generated
  palette for applications and file choosers; modifiers preserve other CSS.
  GTK 3 selects `adw-gtk3-dark` with dark preference enabled; this requires the
  separately installed `adw-gtk-theme` package. A missing theme can silently
  fall back to light Adwaita even when the desktop prefers dark mode.
  On Niri, the FileChooser portal prefers GNOME/Nautilus with GTK as fallback;
  other portal preferences remain untouched. No folder history, bookmarks,
  default applications, icon theme, or dconf database is taken
  over. Matugen no longer forces a particular GTK theme via GSettings.
  GTK 4 imports a separate `nautilus.css`: Nautilus main windows and its portal
  file choosers share a Matugen view background at 90% opacity. Only their
  background layers change; text, icons, context menus, and dropdown popovers
  retain their original opacity. Other GTK applications are not targeted.
  This is background transparency, not compositor opacity or blur.

SwayOSD is not enabled by this configuration; volume bindings retain their
existing WirePlumber behavior.

After reviewing and backing up explicit targets, apply their declarative
files. Existing `create_` targets are deliberately left untouched: regenerate
their palettes through Matugen/Waypaper rather than forcing chezmoi ownership.
Reopen GTK applications to check their styles; test a file chooser separately
from Nautilus. Test the lock screen interactively, not as an automated check.
Neither source checks nor theme rendering invokes the lock screen.

### GTK theme prerequisites

On Arch Linux:

```sh
sudo pacman -S --needed adw-gtk-theme
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```

The GTK 3 theme consumes the generated named colors. Nautilus uses GTK 4 and
libadwaita instead, so it does not use the GTK 3 theme package. Do not force
`GTK_THEME` globally to make the two match.

Reopen applications after installing the theme. Source checks
verify effective GTK 3 window and list colors when the theme, GTK Python
bindings, Matugen, and a display are available, rather than only checking that
palette files exist.

### File chooser portal

On Niri, `~/.config/xdg-desktop-portal/niri-portals.conf` manages only
`org.freedesktop.impl.portal.FileChooser=gnome;gtk;` in `[preferred]`.
With a recent GNOME portal backend and Nautilus installed, this uses the
Nautilus file chooser instead of GTK 3's chooser, avoiding its clipped
file-type dropdown near screen edges. GTK remains a fallback backend;
this does not fix GTK 3 menus embedded directly in applications.

After backing up and applying that explicit target, log out and back in,
or restart `xdg-desktop-portal.service` once file dialogs and portal-based
screen sharing have ended. Reopen a portal-using application's file chooser
to check it. The preference list selects an available backend; it does not
guarantee retrying GTK if a running GNOME backend fails.

## Locale split

The login and user-service environments use `LANG=zh_CN.UTF-8`,
`LANGUAGE=zh_CN:zh`, and `LC_ALL=zh_CN.UTF-8`. `niri-session` imports that
login environment before starting graphical services; the login profile first
clears inherited `LC_*` overrides so an English parent shell cannot take
precedence. Bash and Zsh then source
`~/.config/shell/interactive.sh` only for interactive shells, where `LANG`,
`LANGUAGE`, and the effective locale categories switch to `en_US.UTF-8`.

Both locales must already exist in `locale -a`; this repository does not edit
the system-owned `/etc/locale.gen`. Log out completely and sign in again after
applying these targets so the user service manager and graphical applications
receive the new environment.

## Runtime dependencies

Core session:

- niri, kitty, fuzzel, waybar, mako
- swaylock, swayidle, copyq
- awww, waypaper, matugen
- wireplumber (`wpctl`), playerctl, brightnessctl
- fontconfig, adwaita-fonts, noto-fonts, noto-fonts-extra, noto-fonts-cjk
- noto-fonts-emoji
- ttf-jetbrains-mono-nerd
- adw-gtk-theme
- xdg-desktop-portal, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk

Optional Waybar actions:

- grim, slurp, satty, wl-clipboard, wf-recorder
- ddcutil, hyprpicker, pavucontrol, wlogout, blueberry
- uv for the long-screenshot helper

Desktop application styling also supports Satty, btop, Fcitx5 with
fcitx5-rime, Nautilus, and swaylock-effects. These packages are installed
separately; the source checks do not install or start them.

Kitty scrollback integration also expects
`mikesmithgh/kitty-scrollback.nvim`, installed by the Neovim configuration.

## Output profiles

`niriOutputProfile` defaults to `auto` for unknown hardware. The
`desktop-single-4k` profile matches the P275MV by its monitor identity rather
than its connector name and selects 3840x2160 at 120 Hz with 1.5 scaling.

For an already initialized machine, run `chezmoi edit-config`, set
`niriOutputProfile = "desktop-single-4k"` under `[data]`, then apply only the
reviewed output target:

```sh
chezmoi apply ~/.config/niri/conf.d/20-outputs.kdl
niri msg action load-config-file
```

## Validation

```sh
tests/check-source.sh
fc-match sans-serif
fc-match monospace
fc-match 'monospace:charset=4e2d'
fuzzel --check-config
matugen --dry-run image /path/to/wallpaper
niri validate --config ~/.config/niri/config.kdl
chezmoi diff --skip-secrets
```

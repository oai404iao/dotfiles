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
Chinese session locale while retaining per-character fallback. GTK 3/4,
Kitty and the generic monospace alias use JetBrainsMono Nerd Font Mono for
predictable one-cell widths. Waybar uses the non-Mono variant so icons retain
their natural size in its existing layout. GTK and browser UI explicitly use
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

Optional Waybar actions:

- grim, slurp, satty, wl-clipboard, wf-recorder
- ddcutil, hyprpicker, pavucontrol, wlogout, blueberry
- uv for the long-screenshot helper

Kitty scrollback integration also expects
`mikesmithgh/kitty-scrollback.nvim`, installed by the Neovim configuration.

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

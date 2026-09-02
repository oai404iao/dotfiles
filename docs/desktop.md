# Desktop configuration

The desktop profile is intentionally split by ownership:

- chezmoi owns hand-written Kitty, Fuzzel, Mako, Waybar, Matugen, and Niri
  configuration.
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

## Runtime dependencies

Core session:

- niri, kitty, fuzzel, waybar, mako
- swaylock, swayidle, copyq
- awww, waypaper, matugen
- wireplumber (`wpctl`), playerctl, brightnessctl

Optional Waybar actions:

- grim, slurp, satty, wl-clipboard, wf-recorder
- ddcutil, hyprpicker, pavucontrol, wlogout, blueberry
- uv for the long-screenshot helper

Kitty scrollback integration also expects
`mikesmithgh/kitty-scrollback.nvim`, installed by the Neovim configuration.

## Validation

```sh
tests/check-source.sh
fuzzel --check-config
matugen --dry-run image /path/to/wallpaper
niri validate --config ~/.config/niri/config.kdl
chezmoi diff --skip-secrets
```

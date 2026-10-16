# Desktop applications

Configure fonts, GTK file dialogs, Nautilus actions, and the small application
adapters shared by the desktop profiles. This page does not take ownership of
browser profiles, input dictionaries, histories, or application databases.

Before changing an existing machine, install the relevant packages separately,
back up the explicit targets privately, and review their source and destination
diff. Existing `create_` palettes are not overwritten: regenerate custom colors
through Waypaper/Matugen or DMS colors through DMS.

Start with [fonts](#fonts) and, for custom mode,
[GTK theme prerequisites](#gtk-theme-prerequisites). Use the
[file chooser setup](#file-chooser-portal) for Niri and the
[two-file style update](#nautilus-background-style) for existing Nautilus installs.
See [DMS application palette ownership](desktop-shells.md#application-palettes)
for its additional theme adapters.

## Fonts

Graphical profiles deploy `~/.config/fontconfig/fonts.conf`. Each family falls
back per character in this order:

| Generic family | Primary | Chinese | Emoji / symbols |
|---|---|---|---|
| `sans-serif` | Adwaita Sans | Noto Sans CJK SC | Noto Color Emoji / Noto Sans Symbols |
| `serif` | Noto Serif | Noto Serif CJK SC | Noto Color Emoji / Noto Sans Symbols |
| `monospace` | JetBrainsMono Nerd Font Mono | Noto Sans Mono CJK SC | Noto Color Emoji / Noto Sans Symbols |

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

Verify the selected families after installation:

```sh
fc-match sans-serif
fc-match monospace
fc-match 'monospace:charset=4e2d'
fc-match 'JetBrainsMono Nerd Font Propo'
```

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

## Application behavior

| Application | Managed behavior | Remains local |
|---|---|---|
| Satty | Arrow tool; Adwaita Sans with Chinese fallback; Enter saves and exits, Escape exits without saving | Standalone output path |
| btop | Selects generated `matugen` theme through a modifier | Layout, update interval, and other preferences |
| Fcitx5 Classic UI | Adwaita Sans 11; native fractional scaling without forced DPI; profile-selected theme | Candidate orientation, tray preferences, unknown keys, input groups, Rime schemes, dictionaries, learned words |
| swaylock-effects (custom) | Full Matugen-generated configuration, blurred screenshot, smaller indicator, thin ring, compact clock, matching text; no grace period | Interactive authentication and suspend verification |
| Nautilus / GTK | Profile palette imports and the narrow background style below | Folder history, bookmarks, default applications, icon theme, dconf database |

The screenshot helpers supply Satty's output paths and copy saved edits after
it exits. For standalone Enter-to-save, supply `--output-filename`; the copy
button remains available without it.

Custom Fcitx5 selects `Matugen`; DMS selects its generated `dms` theme, whose
first palette appears at runtime. Custom theme menu assets use monochrome
outlines visible on both normal and selected backgrounds. Matugen reloads the
running Fcitx instance instead of replacing its process.

**A blurred screenshot is not an opaque privacy screen.** Custom mode retains
Niri's lock-before-sleep and lock-before-monitor-off ordering. Test locking
interactively, never through an automated theme check.

Nautilus remains the graphical file manager. GTK 3/4 modifiers preserve other
CSS while importing the generated palette. Custom GTK 3 selects
`adw-gtk3-dark` with dark preference enabled; without `adw-gtk-theme`, it can
silently fall back to light Adwaita. Matugen does not force a GTK theme through
GSettings. Niri prefers GNOME/Nautilus for portal file dialogs, with GTK as
fallback; other portal preferences remain untouched.

SwayOSD is not enabled by this configuration; volume bindings retain their
existing WirePlumber behavior.

Reopen GTK applications after changing their declarative files or palettes.
Check a portal file chooser separately from Nautilus. Neither source checks
nor theme rendering invokes the lock screen.

## Nautilus background style

Both graphical profiles import `gtk-4.0/nautilus.css` after the palette
(`colors.css` for custom, `dank-colors.css` for DMS). Nautilus main windows and
portal file choosers use a view background at 90% opacity. Text, icons, context
menus, and dropdown popovers keep their original opacity; other GTK apps are
not targeted. This is background transparency, not compositor opacity or blur.

To update an existing machine:

1. Save work and back up both targets privately.
2. Review and apply only the two style files:

```sh
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.config/gtk-4.0/gtk.css ~/.config/gtk-4.0/nautilus.css
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/gtk-4.0/gtk.css ~/.config/gtk-4.0/nautilus.css
```

The modifier preserves unrelated CSS and imports the profile palette followed
by `nautilus.css` exactly once. DMS still owns its generated `dank-colors.css`;
this update does not enable legacy user Matugen templates.

3. Reopen Nautilus and affected GTK applications yourself, then test a portal
   file chooser separately. Apply does not automatically quit applications.

## Nautilus copy-path scripts

Graphical profiles manage two executable scripts under
`~/.local/share/nautilus/scripts/`: `复制相对路径` and `复制绝对路径`.
Select files or folders, then choose **Scripts → 复制相对路径** or
**Scripts → 复制绝对路径** from the context menu. This uses
[Nautilus's built-in script support](https://help.gnome.org/gnome-help/nautilus-behavior.html),
not a Python extension. Python and `wl-clipboard` must be installed; clipboard
copying requires a Wayland session.

Relative paths use the current browsing directory, with `./` for descendants
and `../` for parent traversal; absolute paths retain symlink names rather than
resolving them. Multiple selections produce one unquoted path per line, with
no trailing newline. Spaces and Unicode are preserved. These are plain text
paths, not shell-escaped arguments or Nautilus file-copy clipboard data.
Remote locations and filenames containing line breaks are rejected before
copying; an empty selection leaves the clipboard unchanged. Relative copying
requires a local current directory, so virtual search/recent views are not
supported for that action.

Apply only the two script targets after reviewing them; other user scripts
remain unmanaged. If the Scripts submenu is not visible, reopen Nautilus.
`tests/check-nautilus-scripts.py` validates rendering and clipboard calls offline
without replacing the real clipboard.

## GTK theme prerequisites

For the custom profile on Arch Linux, install the GTK 3 theme separately.
Review existing desktop preferences before setting them:

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

## File chooser portal

On Niri, `~/.config/xdg-desktop-portal/niri-portals.conf` manages only
`org.freedesktop.impl.portal.FileChooser=gnome;gtk;` in `[preferred]`.
With a recent GNOME portal backend and Nautilus installed, this uses the
Nautilus file chooser instead of GTK 3's chooser, avoiding its clipped
file-type dropdown near screen edges. GTK remains a fallback backend;
this does not fix GTK 3 menus embedded directly in applications.

1. Install `xdg-desktop-portal`, `xdg-desktop-portal-gnome`,
   `xdg-desktop-portal-gtk`, and Nautilus separately.
2. Back up, review, and apply only `~/.config/xdg-desktop-portal/niri-portals.conf`.
3. Log out and back in. Alternatively, end file dialogs and portal-based
   screen sharing before restarting `xdg-desktop-portal.service`.
4. Open a portal-using application's file chooser to check the selected backend.

The preference list selects an available backend; it does not guarantee
retrying GTK if a running GNOME backend fails.

## Bruno on Niri

The user-level `~/.local/share/applications/bruno.desktop` overrides the
`bruno-bin` launcher at `/opt/Bruno/bruno` with `--ozone-platform=wayland`.
It is deployed only for graphical Niri profiles and retains the `bruno://`
URL handler. This leaves the GNOME/Nautilus file chooser preference unchanged
for every application.

Bruno 4.2.1 (Electron 37.6.1) under XWayland triggered a Nautilus 51 file chooser
crash in a local test. With the same isolated Bruno profile, native Wayland
opened the Nautilus chooser successfully. This is an application-scoped
compatibility workaround, not a patch to Nautilus or a global portal change.
After applying the launcher, fully quit Bruno and reopen it from the
application launcher; an existing single-instance process keeps its original
display backend. For terminal launches, use `bruno --ozone-platform=wayland`.

## Troubleshooting and verification

| Symptom | Next step |
|---|---|
| GTK 3 stays light | Check `adw-gtk-theme` and the GTK 3 preference; do not set `GTK_THEME` globally |
| Nautilus changed but file dialogs did not | Test the [portal backend](#file-chooser-portal) independently |
| Copy-path action is absent | Reopen Nautilus; check Python, `wl-clipboard`, and the Wayland session |
| Relative copy fails in search/recent | Navigate to a local directory; virtual views have no supported current base |
| Fcitx5 tray shows a placeholder in DMS | Check [Qt6ct icon theme and restart requirements](desktop-shells.md#application-palettes) |
| Bruno still uses XWayland | Fully quit its single-instance process and reopen through the managed launcher |

From the source root, run `./tests/check-desktop-apps.sh` for the modifiers,
launchers, palette inputs, and offline Nautilus script calls.
`tests/check-desktop.sh` covers fonts and Waybar behavior.
`tests/check-nautilus-scripts.py` never replaces the real clipboard. Effective
GTK/visual checks require their optional theme, Python bindings, renderer, and
display; missing prerequisites can skip them. Run `./tests/check-source.sh`
and `git diff --check` before a reviewed apply.

Next: [session setup](desktop-session.md), [shell profiles](desktop-shells.md),
or [custom wallpaper and palettes](desktop.md#custom-wallpaper-and-palettes).

# Desktop session setup

Prepare the login environment and services used by both custom and DMS Niri
desktops. This guide covers four independent tasks:

| Task | Start here |
|---|---|
| Authenticate a single sudo command through a dialog | [Graphical sudo prompts](#graphical-sudo-prompts) |
| Activate and unlock application secrets consistently | [Desktop keyring](#desktop-keyring) |
| Keep the desktop Chinese and interactive terminals English | [Locale split](#locale-split) |
| Generate English user-folder names without changing the desktop language | [XDG user directories](#xdg-user-directories) |

System packages, locale generation, PAM changes, and service enablement are
manual prerequisites. Chezmoi does not perform them. Back up existing targets
privately, review only the relevant paths, and avoid restarting the session bus
or changing another authentication provider as a shortcut.

## Graphical sudo prompts

Use `sudo -A` when a command needs graphical authentication. The graphical
profile's `~/.local/bin/sudo-askpass` runs `/usr/bin/zenity --password` as the
calling user and passes the password directly to sudo. Ordinary `sudo` is
unchanged.

### Set up the helper

1. Install `sudo` and `zenity` separately:

```sh
sudo pacman -S --needed sudo zenity
```

2. On an existing machine, back up both targets if present, review the
   sanitized diff, and apply only these files:

```sh
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.local/bin/sudo-askpass ~/.config/shell/profile.sh
chezmoi apply --skip-secrets --exclude=scripts,encrypted \
  ~/.local/bin/sudo-askpass ~/.config/shell/profile.sh
```

3. Start a new login session. The shared Bash/Zsh login environment exports
   `SUDO_ASKPASS` only when the helper is executable and preserves any non-empty
   custom value. For an already open terminal, export it before starting Pi,
   or pass it on the individual command:

```sh
export SUDO_ASKPASS="$HOME/.local/bin/sudo-askpass"
```

   Start a new Pi process after exporting; existing processes retain their
   environment.

4. Invoke sudo explicitly when needed:

```sh
sudo -A /usr/bin/id
```

To ignore an existing authentication timestamp for one command, use
`sudo -A -k /usr/bin/id`; sudoers may still exempt a command from password
authentication. The dialog is authentication, not per-command approval, and
does not display the full command. Do not grant a root shell or run the whole
agent as root to avoid repeated prompts.

### Constraints and retirement

The calling process must have access to the graphical session. This setup
does not forward prompts from remote SSH sessions or containers. Never run
the helper alone through an agent tool, capture its stdout, or log passwords.
Canceling the dialog fails authentication; there is no password-storage or
terminal fallback in the helper.

Headless profiles ignore the helper, not delete it. When retiring graphical
configuration, move a retained helper out of its target path and unset the
managed `SUDO_ASKPASS` value before starting new processes. Login export is
based on the helper's executable presence, not a runtime display check.

## Desktop keyring

Use GNOME Keyring's packaged service/socket for application secrets while
retaining `rbw-agent` for SSH. With `graphical=true` and `niri=true`, chezmoi
manages only these activation overrides:

```text
~/.local/share/dbus-1/services/org.freedesktop.secrets.service
~/.local/share/dbus-1/services/org.gnome.keyring.service
```

Both keep the packaged daemon command as a fallback and set
`SystemdService=gnome-keyring-daemon.service`. D-Bus activation therefore uses
the same unit as socket activation instead of launching a separate transient
daemon after a restart. The packaged service and socket remain unchanged;
do not add a daemon startup command to Niri or shell profiles. This coordinates
activation, not a fix for every possible daemon crash.

GNOME Keyring's Secret Portal is an interface on `org.freedesktop.secrets`.
It does not need a third override named `org.freedesktop.impl.portal.Secret`.
The Niri portal preference file still manages only the file chooser.

### 1. Prepare packages, socket activation, and PAM

Install `gnome-keyring`, `libsecret`, and `seahorse` separately. If needed,
enable the packaged socket:

```sh
systemctl --user enable --now gnome-keyring-daemon.socket
```

PAM, not Niri, supplies the login password for unlocking. On an Arch TTY login,
back up and review `/etc/pam.d/login` for these entries after the corresponding
included authentication and session stacks:

```pam
auth       optional    pam_gnome_keyring.so
session    optional    pam_gnome_keyring.so auto_start
```

If using a display manager, review its PAM stack instead. For password
changes, review `/etc/pam.d/passwd` for
`password optional pam_gnome_keyring.so use_authtok` after the password stack.
Back up PAM files before editing; do not replace the existing stack or add
duplicate entries. System package installation, PAM edits, and service
enablement are manual prerequisites, not chezmoi apply hooks.

### 2. Review the default keyring without discarding data

Use Seahorse to make **Login** the default password keyring, with its password
matching the login password. Passwordless login cannot supply that password
to PAM. Changing the default does not migrate existing entries: any migration
must separately preserve conflicting application keys and verify the affected
applications. Do not delete or recreate keyrings to fix a missing UI category.
SSH continues to use `rbw-agent`; do not change `SSH_AUTH_SOCK` for this setup.

`~/.local/share/keyrings/` (including the default selector) and
`~/.local/state/keyring-backups/` are machine-local, ignored state. Never add
their contents to chezmoi or Git, even as encrypted recovery copies.

### 3. Apply only the activation overrides

Before taking over existing activation files, back up and review only these
two non-secret targets. Then apply them explicitly:

```sh
mkdir -p ~/.local/share/dbus-1/services
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.local/share/dbus-1/services/org.freedesktop.secrets.service \
  ~/.local/share/dbus-1/services/org.gnome.keyring.service
chezmoi apply \
  ~/.local/share/dbus-1/services/org.freedesktop.secrets.service \
  ~/.local/share/dbus-1/services/org.gnome.keyring.service
```

### 4. Start a fresh session and verify unlocking

Log out completely and log in again to load the overrides and exercise PAM
unlocking. On an existing dbus-broker session, `systemctl --user reload
dbus.service` reloads activation metadata without restarting the bus, but
does not remove an already running extra daemon. Do not restart the session
bus. A deliberate keyring-service restart drops its unlocked state, so
applications may ask for the keyring password again. GNOME Keyring also reads
the Portal's default collection at startup; after changing the default,
use a fresh session or a deliberate keyring-service restart.

Offline coverage is in `tests/check-keyring.sh`; it neither contacts the
live keyring nor starts services. After a real login, check the service status
and verify that Seahorse shows Login and applications retain their credentials.
If moving to a different desktop or Secret Service provider, explicitly retire
these two overrides after review: ignoring them in another profile does not
remove previously deployed files.

References: [GNOME Keyring PAM](https://wiki.gnome.org/Projects/GnomeKeyring/Pam)
and [D-Bus service activation](https://dbus.freedesktop.org/doc/dbus-daemon.1.html).

## Locale split

Generate both `zh_CN.UTF-8` and `en_US.UTF-8` at the system level first and
confirm them with `locale -a`. This repository does not edit `/etc/locale.gen`.

| Environment | Defaults | How it gets them |
|---|---|---|
| Login, desktop, user services | `LANG=zh_CN.UTF-8`, `LANGUAGE=zh_CN:zh` | Shared login profile and user environment; no persistent `LC_ALL` |
| Interactive Bash/Zsh | `LANG=en_US.UTF-8`, `LANGUAGE=en_US:en` | `~/.config/shell/interactive.sh`, sourced only interactively |
| `gui` launches on Niri | Desktop's environment | Compositor spawn, not the caller's terminal environment |

Both shell layers clear inherited `LC_*` overrides before selecting their
locale. `niri-session` imports the login environment before graphical services
start, so an English parent shell cannot override the desktop categories.

### Launch an application with the desktop locale

Direct launches from an interactive shell inherit its English environment;
being a GUI application does not automatically select Chinese. On Niri, use
the shared interactive `gui` helper to launch through the compositor instead:

```sh
gui nautilus "$HOME/Documents"
```

It delegates to `niri msg action spawn -- "$@"`, launching asynchronously
with Niri's desktop environment. It does not wait for the application or
preserve the caller's working directory; pass absolute file paths. This
requires a running Niri session, and application-specific language settings
can still override the locale defaults.

### Migrate a persistent `LC_ALL` setting

Back up and review these explicit targets before applying them:

| Target | Responsibility |
|---|---|
| `~/.config/shell/profile.sh` | Chinese login defaults; clears inherited category overrides |
| `~/.config/shell/interactive.sh` | English interactive defaults and `gui` helper |
| `~/.config/environment.d/10-locale.conf` | Chinese user-service defaults |

Reload the user manager's configuration and remove its stale override once:

```sh
systemctl --user daemon-reload
systemctl --user unset-environment LC_ALL
```

Importing the new login environment does not remove variables absent from it.
Do not globally import the English terminal's environment into the user
manager. These commands do not restart services: existing processes and legacy
D-Bus activation environments still retain their old values. Terminate the
full user session and sign in again; reboot if lingering keeps the user
manager alive.

For DMS, stop its old supervisor and relaunch through Niri as
described in [the immediate overlay switch](dms-plugins.md#native-media-page-overlay);
`dms restart` alone retains the supervisor's environment.

## XDG user directories

On graphical machines, the managed
`~/.config/systemd/user/xdg-user-dirs.service.d/10-english.conf` gives only the
login folder updater an English locale. Its service-local `LC_ALL` overrides
inherited Chinese `LC_*` values without changing the desktop environment.
Missing mappings are generated with English names even when the desktop is
Chinese; surviving custom mappings are retained.

`~/.config/user-dirs.dirs` and `user-dirs.locale` remain generated,
machine-local files. After reviewing and applying the explicit drop-in target,
run `systemctl --user daemon-reload`. The override must be restored before
the updater runs if the user configuration tree is lost.

### Generate missing mappings manually

The service override does not affect manual commands or other desktop folder
renamers. To generate missing mappings manually, use:

```sh
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US:en xdg-user-dirs-update
```

### Migrate an existing mapping

An existing Chinese mapping is not renamed automatically:

1. Back up `user-dirs.dirs` and `user-dirs.locale` privately.
2. Create each intended English directory and set its mapping explicitly:

```sh
mkdir -p -- "$HOME/Downloads"
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US:en \
    xdg-user-dirs-update --set DOWNLOAD "$HOME/Downloads"
```

3. Move any desired contents separately: setting mappings does not move files.
4. Restart applications that cache these paths and review explicit download
   settings. Do not use `--force` as a migration shortcut.

## Troubleshooting and checks

| Symptom | Check before changing anything |
|---|---|
| No sudo dialog | Helper executable, `sudo -A`, exported `SUDO_ASKPASS`, and access to the graphical session |
| Keyring asks for a password after restart | Restart drops unlocked state; confirm PAM/login-password matching in a fresh login |
| Missing Seahorse category | Inspect the default collection; never delete or recreate keyrings to fix the UI |
| Duplicate keyring daemon | Both activation overrides and packaged unit/socket; do not restart the session bus |
| Desktop or DMS unexpectedly English | Stale `LC_*`, supervisor environment, or an incomplete user-session logout |
| New folders have Chinese names | Apply the updater's service drop-in before it runs; manual commands need their own English locale |

Offline checks from the source root:

```sh
./tests/check-shell.sh
./tests/check-desktop.sh
./tests/check-keyring.sh
git diff --check
```

These checks use fixtures; they do not authenticate sudo against the real
system, unlock the live keyring, or prove real login behavior. Run the full
`./tests/check-source.sh` before applying configuration changes.

Next: [desktop applications](desktop-applications.md),
[switching shells](desktop-shells.md#switch-an-existing-machine), or
[SSH ownership](ssh.md).

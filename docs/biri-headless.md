# Biri and Sunshine streaming

Select one `biri` mode in chezmoi machine data:

| Mode | Managed configuration |
|---|---|
| `none` (default) | Upstream Niri configuration without Biri or Sunshine integration |
| `headless` | Independent Biri/Sunshine user service, using `HEADLESS-1` |
| `desktop` | Sunshine on the regular Biri/DMS desktop's `SUNSHINE-1`; no managed headless service |

Both stream modes use 1920×1080 at 60 Hz. Chezmoi does not switch packages.

The regular desktop owns DMS. The independent headless service uses its own
KDL, Waybar configuration and stylesheet, Fuzzel configuration, and swaylock
configuration under `~/.config/biri/`. Waybar shows workspaces, the focused
window title, and a clock on `HEADLESS-1`. The session starts Waybar, swayidle,
and Sunshine. swayidle locks after five minutes and keeps the virtual output
available for capture.

Same-user sessions share the user manager and use `seat0` by default. To run
both sessions with separate input, follow the
[dual-seat setup](#separate-headless-input-from-the-local-desktop).

## Prepare the host

- Install [Biri](https://github.com/barrulus/biri/tree/main/packaging) and
  [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html).
  Biri's upstream Arch snapshot is unsigned; review its provenance and verify
  the published SHA-256 before installing. It replaces the `niri` package and
  retains the `niri` and `niri-session` commands. Keep a known-good Niri package
  for rollback. For `headless`, install `kitty`, `fuzzel`, `waybar`, `swayidle`,
  and stock `swaylock`. Arch's `swaylock` and AUR `swaylock-effects` provide the
  same command and are alternative packages. The custom desktop's lock styling
  requires `swaylock-effects`. For `desktop`, prepare the
  [DMS profile](desktop-shells.md).
- The service user needs unattended access to the GPU render node and, for
  remote input, access to `/dev/uinput` and the associated input event devices.
  Active graphical login ACLs alone are not enough. Allow streams only from a
  trusted LAN or VPN; the service does not configure the host firewall.
- Check that no independent Sunshine service or desktop autostart is running.
  Biri launches Sunshine with the correct Wayland socket; a second instance can
  compete for the same ports and state.

## Stream the regular desktop

1. Prepare the [DMS profile](desktop-shells.md). Back up the machine config,
   DMS settings and existing KDL privately. Use `chezmoi edit-config` and set
   these values under `[data]`:

   ```toml
   graphical = true
   niri = true
   desktopShell = "dms"
   biri = "desktop"
   ```

2. Review and apply `~/.config/niri/profile.kdl`, `~/.config/niri/config.kdl`,
   and `~/.config/dms/settings.json` before starting the new session. Validate
   the regular entry point with
   `niri validate --config ~/.config/niri/config.kdl` using **Biri**, not upstream
   Niri. The regular session creates and initially focuses `SUNSHINE-1` and
   launches Sunshine in a scope tied to `niri.service`. It is an extended
   display, not a mirror.
3. For boot-time startup, configure a display manager to run `niri-session`
   as the desktop user on a local VT. On Arch, one option is
   [greetd](https://man.archlinux.org/man/greetd.5.en) with an `initial_session`
   running `/usr/bin/niri-session`. Choose a VT not shared with another login
   manager; use the packaged PAM stack. greetd runs `initial_session` only
   once per boot; logging out returns to the greeter. The root-owned login
   configuration and service enablement are manual, not chezmoi targets.
4. Before starting the regular session, use the [switching helper](#switch-modes)
   to retire any previously deployed headless service. The DMS profile requests
   the native lock at startup and keeps the outputs on when locked so Moonlight
   can connect. Check that no custom DMS lock command or settings override
   replaces this behavior, and that DMS's lock screen shows on all displays or
   includes `SUNSHINE-1`. Startup lock is not a substitute for login
   authentication or physical access control during startup. Test Moonlight
   login with the Linux account password, desktop capture, keyboard, mouse,
   audio, and a cold boot. Do not change PAM to bypass a failed unlock.

## Enable the independent headless service

Use the [dual-seat setup](#separate-headless-input-from-the-local-desktop)
instead if the local desktop will stay active.

1. Back up the machine config and any existing targets privately. Use
   `chezmoi edit-config` to set these values under `[data]`:

   ```toml
   biri = "headless"
   ```

   Stop any running regular streaming session before applying; see [Switch
   modes](#switch-modes).
2. Review and apply the dedicated headless configuration and user unit.
   Create missing parent directories before targeting files explicitly.

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=scripts,encrypted \
     ~/.config/biri ~/.config/systemd/user/biri-headless.service
   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/biri ~/.config/systemd/user/biri-headless.service
   # From the chezmoi source root:
   scripts/biri --apply
   journalctl --user -u biri-headless.service -b
   ```

   Check that Sunshine sees `HEADLESS-1` and probes a working encoder. Its
   startup arguments select Wayland screencopy and disable UPnP; Sunshine
   still owns its config file, credentials, apps, and pairings. The web UI is
   localhost-only. From the client, open an SSH tunnel and visit
   `https://localhost:47990` to set up the UI or enter Moonlight's pairing PIN:

   ```sh
   ssh -N -L 47990:127.0.0.1:47990 <host>
   ```

   Add the host's LAN or VPN address to Moonlight. Test the Desktop stream,
   keyboard, mouse, and audio. `Super+T` or `Super+Enter` opens Kitty,
   `Super+D` or `Alt+Space` opens Fuzzel, and `Super+Alt+L` locks with swaylock.
   `Super+Shift+/` lists shortcuts. `Super+Alt+M` opens `btop` in Kitty when
   `btop` is installed. Test unlock with the Linux account password, then
   reconnect after five minutes idle and confirm that the lock screen remains
   visible in Moonlight.
3. For startup before login, run `sudo loginctl enable-linger "$USER"` if
   needed. The helper enables the unit in the user manager. Verify after
   a cold boot without logging into the graphical desktop. Applying the files
   alone neither enables nor starts the service.

## Separate headless input from the local desktop

With both compositors on `seat0`, Moonlight input can reach the local desktop
and physical input can reach the stream. The opt-in assigns Sunshine's virtual
keyboard, mice, touchscreen, and pen to `seat-stream` and starts headless Biri
on that seat. It does not route gamepads or isolate processes running as the
same user.

If the rule and drop-in are already installed and match the sources, opt in
with the machine data in step 2 and review the target diff. There is no need
to reinstall the rule or restart a working service just to adopt the drop-in.

1. Review [`scripts/udev/72-sunshine-seat-stream.rules`](../scripts/udev/72-sunshine-seat-stream.rules)
   against the installed Sunshine devices. The rule matches only the listed
   `libvirtualhid` event devices from vendor `1209`. Back up any existing rule
   or service override before replacing it. Stop the headless service; this
   disconnects Moonlight but leaves the local desktop running. From the source
   root, install the rule manually and reload udev:

   ```sh
   systemctl --user stop biri-headless.service
   udevadm verify scripts/udev/72-sunshine-seat-stream.rules
   sudo install -m 0644 scripts/udev/72-sunshine-seat-stream.rules \
     /etc/udev/rules.d/72-sunshine-seat-stream.rules
   sudo udevadm control --reload-rules
   ```

   Chezmoi does not write `/etc`. Reloading rules does not retag devices that
   are already open; Sunshine recreates its virtual devices on startup. Do not
   retrigger all input devices on the live desktop.
2. On an initialized machine, use `chezmoi edit-config` and set these keys
   under the existing `[data]` section:

   ```toml
   biri = "headless"
   biriSeparateInput = true
   ```

   A missing or false `biriSeparateInput` leaves the drop-in unmanaged.
3. Review and apply the dedicated headless configuration, user unit, and
   seat drop-in. Create missing parent directories before targeting files
   explicitly.

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=scripts,encrypted \
     ~/.config/biri ~/.config/systemd/user/biri-headless.service \
     ~/.config/systemd/user/biri-headless.service.d/90-seat-stream.conf
   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/biri ~/.config/systemd/user/biri-headless.service \
     ~/.config/systemd/user/biri-headless.service.d/90-seat-stream.conf
   systemctl --user daemon-reload
   systemctl --user start biri-headless.service
   ```

   Manage activation manually: `scripts/biri --apply` is for exclusive
   sessions without drop-ins. Enable the unit separately if it should start at
   boot. Verify the headless unit's `Environment` contains `XDG_SEAT=seat-stream`,
   and check the Sunshine event nodes with `udevadm info --query=property
   --name=/dev/input/eventN` for `ID_SEAT=seat-stream`. Reconnect Moonlight and
   verify that input in each session leaves the other unaffected.

To retire the dual-seat setup, stop the headless service and set
`biriSeparateInput = false`. Archive the installed `90-seat-stream.conf` and
the `/etc` rule, then reload the user service manager and udev rules. Chezmoi
does not delete the now-ignored drop-in. If switching Biri modes, complete this
cleanup before using `scripts/biri --apply`.

## Switch modes

On an initialized machine with the old `niriCompositor`, `biriHeadless`, or
`biriDesktopStream` keys, replace all three with one `biri` value before applying
the new source. Choose the mode that should run, not which files used to be
managed. Missing `biri` means `none`; the old keys are no longer read. Do not
rerun initialization.

1. Save work and disconnect live streams. When switching to `headless`, end the
   regular session and handle competing desktop autostart separately. When leaving
   `desktop`, review DMS's retained lock preferences in DMS Settings.
2. Set `biri` explicitly. Review and apply the new mode's targets with chezmoi as
   above. When leaving `desktop`, also reapply the regular Niri entry point and
   DMS settings to remove the virtual output, Sunshine startup, and post-lock
   timer override.
3. From the source root, run `scripts/biri` to preview the user-service changes,
   then `scripts/biri --apply` to carry them out:

   - `headless`: stop the previous desktop Sunshine scope and enable/start the
     applied headless service. The helper refuses to start it alongside another
     regular Niri session.
   - `desktop`: disable and stop the headless service, if present, and archive
     its unit and KDL under `$XDG_STATE_HOME/deployment-backups/biri` (default
     `~/.local/state/deployment-backups/biri`). Chezmoi leaves the remaining
     headless UI files unmanaged. Start the regular session through
     its login manager. With greetd, log in at the greeter or boot again;
     restarting greetd does not repeat automatic login in the same boot.
   - `none`: retire the headless service as above and stop the regular Sunshine
     scope, without terminating the regular desktop.

Run the helper as the desktop user with the standard `~/.config` layout. It
never runs `chezmoi apply`, changes system services or linger, or touches
Sunshine settings and pairings. If you customized the headless unit or added
drop-ins, handle its service changes manually.
To return to upstream Niri, replace Biri separately after stopping its session.
To migrate a running `headless` service to the lightweight UI, review and
apply `~/.config/biri` as above, then restart `biri-headless.service` when the
stream can be disconnected. This closes the headless desktop and launches
the new startup commands. Restart the service also if Sunshine exits.

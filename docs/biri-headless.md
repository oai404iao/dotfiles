# Biri and Sunshine streaming

Use Sunshine and Moonlight to stream either a virtual output of the regular
desktop or a separate headless desktop. Both use a 1920×1080 at 60 Hz virtual
output and may be managed on the same machine. Run only one at a time.

With the DMS profile, both entry points include `niri/profile.kdl` for shared
bindings, layout, rules, and DMS startup. The independent headless session
otherwise uses its standalone Kitty and Fuzzel bindings. Same-user sessions
share the user manager, DMS state and IPC, and by default seat0 input.

## Prepare the host

- Install [Biri](https://github.com/barrulus/biri/tree/main/packaging) and
  [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html).
  Biri's upstream Arch snapshot is unsigned; review its provenance and verify
  the published SHA-256 before installing. It replaces the `niri` package and
  retains the `niri` and `niri-session` commands. Keep a known-good Niri package
  for rollback. Install Kitty and Fuzzel for standalone use, or prepare and
  apply the [DMS profile](desktop-shells.md) before starting the service.
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
   niriCompositor = "biri"
   desktopShell = "dms"
   biriDesktopStream = true
   biriHeadless = true # optional: keep the independent fallback managed
   ```

2. Review and apply `~/.config/niri/profile.kdl`, `~/.config/niri/config.kdl`,
   and `~/.config/dms/settings.json` before starting the new session. If keeping
   a fallback, also update and validate its `~/.config/biri/headless.kdl` after
   applying `profile.kdl`. Validate the regular entry point with
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
4. Stop and disable the fallback before starting the regular session:

   ```sh
   systemctl --user disable --now biri-headless.service
   ```

   The DMS profile requests the native lock as DMS starts and keeps the outputs
   on when locked so Moonlight can connect. Check that no custom DMS lock command
   or settings override replaces this behavior, and that DMS's lock screen is
   set to show on all displays or includes `SUNSHINE-1`. Startup lock is not a
   substitute for login authentication or physical access control during startup.
   Test Moonlight login with the Linux account password, desktop capture,
   keyboard, mouse, audio, and a cold boot. Do not change PAM to bypass a failed unlock.

To use the fallback, end the regular session and stop its display manager
first. Confirm that `biri-desktop-sunshine.scope` and DMS have exited, then
run `systemctl --user start biri-headless.service`. Leave it
disabled if it should not start on the next boot. Stop it before returning to
the regular session. With greetd, log in at the greeter or boot again; restarting
the service does not repeat automatic login in the same boot. If retiring
regular streaming, review and reapply the same desktop targets with
`biriDesktopStream = false`; review DMS's retained startup lock and immediate
display-off preferences in its settings.

## Enable the independent headless service

1. Back up the machine config and any existing targets privately. Use
   `chezmoi edit-config` to set these values under `[data]`:

   ```toml
   niriCompositor = "biri"
   biriHeadless = true
   ```

   On an existing Biri headless installation, add `niriCompositor` before
   rendering or applying with the updated source. Without it, an initialized
   machine defaults to upstream Niri. Chezmoi does not switch packages.
2. If also using the DMS profile, ensure the shared `~/.config/niri/profile.kdl`
   and its includes have been applied. Review and apply only the headless files
   (create missing parent directories):

   ```sh
   chezmoi diff --exclude=scripts,encrypted \
     ~/.config/biri/headless.kdl ~/.config/systemd/user/biri-headless.service
   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/biri/headless.kdl ~/.config/systemd/user/biri-headless.service
   systemctl --user daemon-reload
   systemctl --user start biri-headless.service
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
   keyboard, mouse, and audio. In standalone mode, `Super+Enter` opens Kitty
   and `Super+D` opens Fuzzel. In DMS mode, check the bar, DMS launcher, and
   reconnect after the [idle lock and display-off timers](desktop-shells.md#idle-and-lock-defaults).
3. For startup before login, run `sudo loginctl enable-linger "$USER"` if
   needed, then `systemctl --user enable biri-headless.service`. Verify after
   a cold boot without logging into the graphical desktop. Applying the files
   alone neither enables nor starts the service.

## Restart or retire

Restart `biri-headless.service` after changing the desktop profile or
Sunshine's launch options, or if Sunshine exits on its own. This ends any live
stream and closes the headless desktop. To retire it, run
`systemctl --user disable --now biri-headless.service` before setting
`biriHeadless = false`. Leave Sunshine's state in place. Do not disable linger
if another user service relies on it. To return to upstream Niri, stop this
service before replacing Biri with the known-good Niri package, then set
`niriCompositor = "niri"`.

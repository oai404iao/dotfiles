# Biri and Sunshine headless desktop

Stream a separate 1920×1080 at 60 Hz Wayland desktop to Moonlight without a
monitor, display manager, or automatic login. The local custom/DMS profile
continues to use `niri/config.kdl`. The sessions may run as the same Linux user;
they share credentials, the user manager and, by default, seat0 input. Use them
alternately if both sessions receive the same keyboard or mouse events.

## Prepare the host

- Install [Biri](https://github.com/barrulus/biri/tree/main/packaging) and
  [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html).
  Biri's upstream Arch snapshot is unsigned; review its provenance and verify
  the published SHA-256 before installing. It replaces the `niri` package and
  retains the `niri` and `niri-session` commands. Keep a known-good Niri package
  for rollback. Install Kitty and Fuzzel for the terminal and launcher binds.
- The service user needs unattended access to the GPU render node and, for
  remote input, access to `/dev/uinput` and the associated input event devices.
  Active graphical login ACLs alone are not enough. Allow streams only from a
  trusted LAN or VPN; the service does not configure the host firewall.
- Check that no independent Sunshine service or desktop autostart is running.
  Biri launches Sunshine with the correct Wayland socket; a second instance can
  compete for the same ports and state.

## Enable on an initialized machine

1. Back up the machine config and any existing targets privately. Use
   `chezmoi edit-config` to set `biriHeadless = true` under `[data]`.
2. Review and apply only the headless files (create missing parent directories):

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
   keyboard, mouse, and audio. `Super+Enter` opens Kitty; `Super+D` opens Fuzzel.
3. For startup before login, run `sudo loginctl enable-linger "$USER"` if
   needed, then `systemctl --user enable biri-headless.service`. Verify after
   a cold boot without logging into the graphical desktop. Applying the files
   alone neither enables nor starts the service.

## Restart or retire

After changing Sunshine's launch options or if Sunshine exits on its own,
restart `biri-headless.service`; this ends any live stream and closes the
headless desktop. To retire it, run
`systemctl --user disable --now biri-headless.service` before setting
`biriHeadless = false`. Leave Sunshine's state in place. Do not disable linger
if another user service relies on it. To return to upstream Niri, stop this
service before replacing Biri with the known-good Niri package.

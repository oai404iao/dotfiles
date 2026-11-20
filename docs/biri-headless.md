# Biri and Sunshine streaming

Select one `biri` mode in chezmoi machine data:

| Mode | Managed configuration |
|---|---|
| `none` (default) | Upstream Niri configuration without Biri or Sunshine integration |
| `headless` | Independent Biri/Sunshine user service, using `HEADLESS-1` |
| `desktop` | Sunshine on the regular Biri/DMS desktop's `SUNSHINE-1`; no managed headless service |

Both stream modes use 1920×1080 at 60 Hz. Chezmoi does not switch packages.

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

1. Back up the machine config and any existing targets privately. Use
   `chezmoi edit-config` to set these values under `[data]`:

   ```toml
   biri = "headless"
   ```

   Stop any running regular streaming session before applying; see [Switch
   modes](#switch-modes).
2. If also using the DMS profile, ensure the shared `~/.config/niri/profile.kdl`
   and its includes have been applied. Review and apply only the headless files
   (create missing parent directories):

   ```sh
   chezmoi diff --exclude=scripts,encrypted \
     ~/.config/biri/headless.kdl ~/.config/systemd/user/biri-headless.service
   chezmoi apply --exclude=scripts,encrypted \
     ~/.config/biri/headless.kdl ~/.config/systemd/user/biri-headless.service
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
   keyboard, mouse, and audio. In standalone mode, `Super+Enter` opens Kitty
   and `Super+D` opens Fuzzel. In DMS mode, check the bar, DMS launcher, and
   reconnect after the [idle lock and display-off timers](desktop-shells.md#idle-and-lock-defaults).
3. For startup before login, run `sudo loginctl enable-linger "$USER"` if
   needed. The helper enables the unit in the user manager. Verify after
   a cold boot without logging into the graphical desktop. Applying the files
   alone neither enables nor starts the service.

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
     `~/.local/state/deployment-backups/biri`). Start the regular session through
     its login manager. With greetd, log in at the greeter or boot again;
     restarting greetd does not repeat automatic login in the same boot.
   - `none`: retire the headless service as above and stop the regular Sunshine
     scope, without terminating the regular desktop.

Run the helper as the desktop user with the standard `~/.config` layout. It
never runs `chezmoi apply`, changes system services or linger, or touches
Sunshine settings and pairings. If you customized the headless unit or added
drop-ins, handle its service changes manually.
To return to upstream Niri, replace Biri separately after stopping its session.
If staying in `headless`, restart its service after changing startup options or
if Sunshine exits; this closes the headless desktop.

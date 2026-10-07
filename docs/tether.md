# Bluetooth iPhone notifications with Tether

This optional Niri/DMS profile forwards iPhone Bluetooth notifications to DMS
without Wi-Fi transport or desktop clipboard access. It was tested with
Tether **0.2.36**, Arch BlueZ **5.87**, DMS **1.6.2**, and an iPhone 14 on
iOS **27**: BR/EDR, LE, ANCS, and MAP connected, and a real DMS notification
was confirmed. These are tested versions, not a promise about later releases.
[Upstream Tether](https://github.com/zackb/tether) describes notification
mirroring as beta and does not support it on iOS 18 or earlier.

No iOS companion app, Wi-Fi pairing, browser extension, or Avahi service is
needed for this Bluetooth path. An Avahi-unavailable warning concerns Wi-Fi
discovery; do not enable Avahi solely to silence it.

## Opt in and ownership

`tether` defaults to `false`. New-machine initialization asks about it only
when `graphical=true`, `niri=true`, and `desktopShell="dms"`. On an initialized
machine, back up its chezmoi config and deliberately add the following under
the existing `[data]` section with `chezmoi edit-config`; do not rerun init:

```toml
graphical = true
niri = true
desktopShell = "dms"
tether = true
```

The repository owns only:

- `~/.config/tether/bluetooth.json`, merged with a modifier in a private
  directory (`0700`) and file (`0600`). It enables notification forwarding
  with titles/bodies and sets retention to `none`; call control,
  AirPods management, group-message support, and lock-on-away are disabled.
  Existing `device_address`, `auth_strategy`, `adapter`, `enabled`,
  `config_version`, and unknown keys survive. In particular, apply does not
  enable a connection that was locally disabled. Invalid types for known
  runtime fields are rejected because upstream fallback could skip retention.
- `~/.config/systemd/user/tetherd.service.d/10-notification-network.conf`
  and `20-no-clipboard.conf`, described below.
- One DMS notification rule matching the exact desktop entry `tether-gtk`,
  with `no_history`. The modifier owns and consolidates this exact selector,
  placing it before broad user rules; it preserves unrelated rules and
  preferences, but intentionally overrides conflicting matching rules.

The DMS rule keeps notifications in the live notification center but excludes
them from its historical store. It does **not** purge earlier DMS history.
Tether can still hold MAP messages and contacts in memory; retention `none`
prevents message/contact files, not receipt of that information.
Contact sharing is optional for this notification-only use.

Phone addresses, Bluetooth bonds/authentication, certificates and keys,
store keys, known hosts, message/contact stores, logs, and other runtime state
stay machine-local. Do not recursively add Tether's configuration or state
directories to chezmoi. Notifications contain personal information: inspect
existing Bluetooth/DMS settings locally, not in shared diff logs.

## Isolation and limitations

The network drop-in clears the vendor `ExecStartPre` (which runs `pkill`) and
`ExecStart`, then starts:

```ini
ExecStart=/usr/bin/unshare --user --map-current-user --net /usr/bin/tetherd
PrivateUsers=yes
UMask=0077
```

`unshare` is mandatory and fails closed if a new network namespace cannot be
created. On the tested systemd 262 host, `PrivateNetwork` isolation silently
degraded with an `ExecStartPre` namespace failure (`EPERM`); merely reading a
unit's configured flags was not sufficient proof. The restarted daemon was
verified to have a different network namespace from the host and no host
TCP listener on port 5134. BlueZ/system D-Bus and the user Unix socket remain
available; Bluetooth operation does not need the host IP network.

The clipboard drop-in sets `RuntimeDirectory=tether`,
`RuntimeDirectoryMode=0700`, `RuntimeDirectoryPreserve=yes`, and
`WAYLAND_DISPLAY=wayland-0`. It overlays `%t` with `TemporaryFileSystem=%t:rw`,
exposing only `BindPaths=%t/tether` and `BindReadOnlyPaths=%t/bus`.
This hides all runtime-directory compositor sockets, including ones created
after the service starts, while leaving the user bus and Tether's Unix socket
reachable by DMS and the CLI.

Consequently clipboard synchronization, notification actions that copy codes,
and a Wayland GUI launched by the daemon do not work. A manually launched GUI
outside the unit may still work, but is not covered by the service's isolation.
This is a narrowly scoped service policy, not protection from other programs
running as the same user.

**Before every Tether CLI/GUI operation, verify that the sandboxed service is
active.** The client can auto-start an unsandboxed daemon when no service is
running. Do not use the CLI to recover a failed service before resolving the
failure.

## Install and prepare manually

Chezmoi does not install packages, modify root configuration, or enable
services. Install a reviewed Tether package separately. The tested AUR
`tether-bin` 0.2.36 package omitted its `libsecret` dependency; install it
explicitly along with the Bluetooth tools:

```sh
sudo pacman -S --needed libsecret bluez-utils bluez-obex
```

Before changing BlueZ, review `systemctl cat bluetooth.service` and the
source-only `scripts/tether/bluetooth-experimental.conf`. Back up any existing
root-owned destination to a private, retained local backup before overwriting
it. Then, only after review:

```sh
sudo install -d -m 0755 /etc/systemd/system/bluetooth.service.d
sudo install -m 0644 scripts/tether/bluetooth-experimental.conf \
  /etc/systemd/system/bluetooth.service.d/90-tether-experimental.conf
sudo systemctl daemon-reload
sudo systemctl restart bluetooth.service
sudo systemctl enable --now tether-btclass@hci0
```

The last command enables the package's adapter-class unit; substitute the
actual controller if it is not `hci0`. Bluetooth restart interrupts existing
connections. Wait for the adapter to become ready and check its power state
with `bluetoothctl show`; `bluetoothctl power on` can report `Busy` immediately
after restart. Do not blindly remove bonds as a recovery step.

## Apply and enable the user service

Back up pre-existing Bluetooth settings, DMS settings, and both drop-ins into
a private retained directory outside Git. Review existing settings locally,
and run the offline checks from the source root:

```sh
./tests/check-source.sh
git diff --check
```

The full source check includes Tether; `./tests/check-tether.sh` is available
as a focused alternative during development.

Apply only the reviewed targets, with the daemon stopped while its settings
are merged:

```sh
mkdir -p ~/.config/DankMaterialShell ~/.config/systemd/user/tetherd.service.d
systemctl --user stop tetherd.service
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/tether \
  ~/.config/systemd/user/tetherd.service.d/10-notification-network.conf \
  ~/.config/systemd/user/tetherd.service.d/20-no-clipboard.conf \
  ~/.config/DankMaterialShell/settings.json
systemctl --user daemon-reload
systemctl --user enable --now tetherd.service
systemctl --user is-active --quiet tetherd.service
```

Apply the Tether directory so chezmoi creates its private `0700` parent.
DMS watches `settings.json` and reloads its rules without a restart. Verify
them read-only with `dms ipc call settings get notificationRules`.
A package-provided user unit must exist before enabling it. Do not add a
separate autostart entry or run `tetherd` directly.

## Pair and verify

Use an interactive terminal, with the phone unlocked and its Bluetooth
settings open. Check the service before client commands:

```sh
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-setup
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-status
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-devices
```

Select the phone's machine-local address, then run:

```sh
systemctl --user is-active --quiet tetherd.service &&
  tether --bt-pair <phone-address>
```

Replace `<phone-address>`; never store it in repository data. The CLI supports
interactive numeric-code confirmation without a GUI: compare the displayed
code with the phone and accept only if they match. Do not pipe automatic
confirmation into pairing.

In the iPhone's Bluetooth device details, enable **Show System Notifications**
for ANCS and **Show Message Notifications** for MAP. Contact sharing is
optional. If the permission toggles do not appear, upstream's
`tether --bt-solicit` re-advertises ANCS without deleting the bond; check the
service first. If the connection was locally disabled, enable it deliberately
with `tether --bt-enable on`, again only with the service active.

Verify ANCS/MAP and both Bluetooth bearers with `tether --bt-connection`
(after the service check), then send a real phone notification and confirm
its DMS delivery. Verify isolation after each relevant unit/package change:

```sh
pid=$(systemctl --user show --property=MainPID --value tetherd.service)
test "$pid" -gt 0
readlink /proc/self/ns/net
readlink "/proc/$pid/ns/net"
ss -ltn 'sport = :5134'
```

The namespace identifiers must differ, and the host socket listing must not
contain Tether's listener. If access restrictions prevent inspecting the
daemon namespace, resolve that locally with a reviewed privileged check;
do not treat an unreadable identifier as success. Inspect the service's mount
namespace locally to confirm the compositor socket is hidden. Check that
message/contact files are not being retained; do not print their contents.
Offline tests validate configuration, not actual phone permissions or delivery.

## Disable or change desktop profiles

If stopping forwarding is desired, first run:

```sh
systemctl --user disable --now tetherd.service
```

Then set `tether=false` (or switch away from the active DMS/Niri profile).
The targets become ignored, not deleted, and changing machine data alone does
not stop the service. Existing drop-ins, local pairing state, and DMS settings
remain on disk. Review retained configuration explicitly before any later
manual service enablement; do not assume an ignored target has been reverted.

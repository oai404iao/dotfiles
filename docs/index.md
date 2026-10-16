# Dotfiles documentation

This repository describes a personal Arch Linux environment. Chezmoi renders
reviewed source files into your home; it is not a system installer or a backup
of everything under `$HOME`.

## Get started

- [Quickstart](quickstart.md): prepare a new machine and apply one component at a time.
- [How it works](how-it-works.md): source attributes, ownership, and generated state.
- [Configuration](configuration.md): machine capabilities and deployment conditions.

## Use and maintain

- [Daily workflow](usage.md): update, preview, apply, and add an individual target.
- [Security](security.md): handle secrets, encrypted metadata, backups, and scratch data.
- [Development](development.md): change the source and run offline checks.
- [Publication](publication.md): validate history before making a remote public.

## Configure a component

| Task | Guide |
|---|---|
| Set up shell paths, locale, or user Node.js | [Shell environment](shell.md) |
| Adopt or upgrade pinned shell dependencies | [Zsh dependencies](zsh.md) |
| Prepare a graphical machine | [Desktop](desktop.md) |
| Configure fonts, GTK, Nautilus, or portals | [Desktop applications](desktop-applications.md) |
| Set up locale, sudo dialogs, XDG folders, or keyring | [Desktop session](desktop-session.md) |
| Choose or switch Niri desktop shells | [Desktop shell profiles](desktop-shells.md) |
| Install the separately maintained DMS launcher and plugins | [DMS plugins](dms-plugins.md) |
| Integrate an iPhone with DMS | [Tether](tether.md) |
| Configure Pi models, packages, notifications, or agents | [Pi](pi.md) |
| Adopt Pi credential references or render Telegram credentials | [Pi authentication](pi-authentication.md) |
| Manage Pi pins, builds, notifications, or package layout | [Pi packages](pi-packages.md) |
| Coordinate child agents, codemode, Jev, or global instructions | [Pi agents](pi-agents.md) |
| Install shared agent skills | [Global skills](skills.md) |
| Select a Git commit identity | [Git](git.md) |
| Use Bitwarden-backed SSH keys or manage inbound access | [SSH](ssh.md) |

## Find reference information

Use [machine data](configuration.md#machine-data) for supported values,
[source attributes](how-it-works.md#source-attributes) for chezmoi naming, and
the [check matrix](development.md#checks-by-area) for verification commands.
The annotated [pacman](packages/pacman.txt) and [AUR](packages/aur.txt) lists
are dependency references, not installation scripts.

[AGENTS.md](../AGENTS.md) contains repository-specific coding-agent rules.
It is not the global instruction file deployed to Pi.

For documentation changes, use the
[writing and organization guide](development.md#write-documentation).

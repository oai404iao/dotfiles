# Dotfiles

[English](README.md) | [简体中文](README.zh-CN.md)

Personal Arch Linux configuration managed by
[chezmoi](https://www.chezmoi.io/), for desktop, laptop, and headless machines.

Use Bash or Zsh with a shared login environment, a modular Niri desktop with
custom components or Dux Shell (DMS), LazyVim, Git, SSH, and Pi. Machine
capabilities select what is deployed; credentials, downloaded packages, and
application state remain outside Git.

## Get started

Follow the [Quickstart](docs/quickstart.md) to prepare dependencies, initialize
machine data, validate the source, and adopt reviewed targets. Initialization
does not apply configuration or install system packages.

Already using this repository?

- [Update or add configuration](docs/usage.md) without overwriting local state.
- [Choose machine capabilities](docs/configuration.md), including desktop and SSH profiles.
- [Understand ownership](docs/how-it-works.md) before importing an existing file.
- [Work safely](docs/security.md) before previewing credentials or encrypted targets.

## Configure your environment

| Area | Start here |
|---|---|
| Shells, XDG paths, and user Node.js | [Shell environment](docs/shell.md) |
| Pinned Oh My Zsh and Powerlevel10k | [Zsh dependencies](docs/zsh.md) |
| Fonts, applications, locale, and keyring | [Desktop](docs/desktop.md) |
| Niri custom/DMS selection and migration | [Desktop shells](docs/desktop-shells.md) |
| Optional iPhone notifications and clipboard | [Tether](docs/tether.md) |
| Models, notifications, extensions, and agents | [Pi](docs/pi.md) |
| Optional local agent daemon without web UI | [Paseo](docs/paseo.md) |
| Shared agent skills | [Skills](docs/skills.md) |
| Commit identities and SSH authentication | [Git](docs/git.md) and [SSH](docs/ssh.md) |

See the [documentation index](docs/index.md) for all guides and references.

## Develop and verify

From the chezmoi source directory:

```sh
./tests/check-source.sh
git diff --check
```

Checks are offline; some rendering checks require installed tools. They do not
install dependencies or apply configuration to your home. See
[Development](docs/development.md) for prerequisites, targeted checks, and skips.
Coding agents should read [AGENTS.md](AGENTS.md).

Treat the repository as public. Never commit literal credentials, private keys,
or runtime state. Publication requires the separate
[public-repository safety procedure](docs/publication.md).

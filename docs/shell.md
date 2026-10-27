# Configure the shell environment

Bash and Zsh share a public POSIX login environment but keep completion,
options, bindings, and prompts in their own modules. Both configurations
deploy regardless of the `shell` preference; chezmoi does not change the
account's login shell.

## Startup and ownership

| Source | Role |
|---|---|
| `dot_config/shell/profile.sh` | Login/session XDG paths, Chinese locale, editor/pager, Pi paths, optional askpass and SSH socket |
| `dot_config/shell/toolchains.sh` | Shared language-tool paths; also loaded by non-login shell entrypoints |
| `dot_config/shell/interactive.sh` | English interactive locale, `gui`, and terminal-specific `GPG_TTY` |
| `dot_bash_profile`, `dot_bashrc`, `dot_config/bash/rc.d/` | Bash startup and interactive modules |
| `dot_zshenv`, `dot_config/zsh/` | Zsh XDG entrypoint and ordered modules |
| `dot_config/p10k/p10k.zsh` | Powerlevel10k preferences |

`~/.zshenv` sets `ZDOTDIR` to `$XDG_CONFIG_HOME/zsh`. The managed XDG
`.zshenv` delegates to the home entrypoint when `ZDOTDIR` was inherited.
Keep startup fast, silent where required, and secret-free. Do not fetch
credentials from shell startup.

Niri's login environment uses `LANG=zh_CN.UTF-8` and `LANGUAGE=zh_CN:zh`;
interactive shells use `en_US.UTF-8` and `en_US:en`. Neither persists `LC_ALL`.
See [desktop locale](desktop.md#locale-split) for GUI launches and user services.

## Toolchain paths

`toolchains.sh` preserves explicit non-empty overrides and supplies XDG
defaults. It configures paths, not installations or automatic data migration.

| Tool | Default location / behavior |
|---|---|
| pnpm | `PNPM_HOME=$XDG_DATA_HOME/pnpm`; its root and `bin/` join PATH |
| npm / Node | npm cache under `$XDG_CACHE_HOME/npm`, config under `$XDG_CONFIG_HOME/npm/npmrc`, REPL history under `$XDG_STATE_HOME` |
| Rust | Cargo and rustup under `$XDG_DATA_HOME` |
| Go | GOPATH under `$XDG_DATA_HOME/go`, module cache below it, build cache under `$XDG_CACHE_HOME/go-build` |
| Java / Gradle | System default JVM if available; preferences under `$XDG_CONFIG_HOME/java`, Gradle under `$XDG_DATA_HOME/gradle` |
| Maven 3 | Regenerable repository under `$XDG_CACHE_HOME/maven/repository`; XDG settings selected only if present |
| Docker | `$XDG_CONFIG_HOME/docker` |
| .NET / NuGet | CLI data under `$XDG_DATA_HOME/dotnet`; bundle/package/HTTP/plugin caches under `$XDG_CACHE_HOME` |

The shared login environment also exports `DSH_HOME`, defaulting to
`$XDG_DATA_HOME/dsh`. DSH keeps its configuration, credentials, and runtime
data together there; the whole root stays unmanaged. Existing `~/.dsh` data
is not moved automatically. Set an override in the launch environment, not in
DSH's `.env` file.

The shared login environment exports `PASEO_HOME`, defaulting to
`$XDG_DATA_HOME/paseo`, so the CLI uses the same home as the managed service
on the standard XDG layout. The service explicitly uses
`~/.local/share/paseo`; custom shell overrides do not relocate it. See
[Paseo migration](paseo.md#migrate-an-existing-home) before moving existing data.

## User-level Node.js

Install pnpm 12 separately using the selected system package provider, for
example AUR `pnpm-bin`. After deploying the shared toolchain file, install
the user runtime and npm without `sudo`:

```sh
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/toolchains.sh"
pnpm runtime set node 24 -g
pnpm add -g npm@12.1.0
```

These are explicit network/package operations, not source checks. pnpm itself
remains system-package-managed. Node.js and npm/npx live under `PNPM_HOME`;
downloaded runtimes and global packages are not chezmoi source.

`dot_config/pnpm/modify_private_config.yaml` merges the `@getpaseo/*` release-age
exception into `~/.config/pnpm/config.yaml`. It preserves existing exceptions,
pnpm-managed `globalShims`, and other settings without changing the release-age
limit for other packages. For an existing machine, back up that config, review
its targeted diff, and apply only `~/.config/pnpm/config.yaml`; no package update
or service restart is performed.

Open a new terminal and check:

```sh
command -v node npm npx pnpm
```

Node/npm/npx should resolve under `$PNPM_HOME/bin`; pnpm should resolve to
the selected system package. Pi's separate hoisted npm layout is described in
[Pi packages](pi-packages.md), not a repository-wide package-manager policy.

## Migrate existing shell files

1. Keep the current terminal open.
2. Back up `~/.bash_profile`, `~/.bashrc`, `~/.zshenv`, `~/.config/bash`, and
   `~/.config/zsh`. Move an obsolete `~/.zshrc` into the backup; Zsh now
   reads `~/.config/zsh/.zshrc`.
3. For nvm migration, also back up `shell/toolchains.sh`, `shell/nvm.sh`,
   `bash/rc.d/50-node.bash`, and `zsh/rc.d/50-node.zsh` under `~/.config`.
4. Run `./tests/check-shell.sh`, review explicit sanitized targets, and apply
   only those targets. `.chezmoiremove` retires the old nvm loaders; review
   those removals too.
5. Prepare the user Node runtime if needed, then check a new login and
   interactive shell before closing the original terminal.

New shells discard inherited nvm runtime PATH entries and `NVM_*` variables.
Chezmoi does not uninstall nvm or its global packages. Migrate required tools
first, then separately remove the old system package and move its user runtime
directory to the trash when no longer needed. Do not restore startup loaders
to work around a missing replacement tool.

For Oh My Zsh and nested plugins, use the separate
[Zsh migration guide](zsh.md); do not recursively import downloaded trees.

## Verify changes

```sh
./tests/check-shell.sh
./tests/check-rbw.sh
git diff --check
```

The shell check covers syntax, locale/toolchain environment, startup behavior,
and pinned external fixtures without contacting upstream. The rbw check uses
fixtures for config merging and terminal selection, not the real vault.
Run the [complete source suite](development.md) before finishing a source change.

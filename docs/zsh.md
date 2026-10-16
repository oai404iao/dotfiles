# Manage Zsh dependencies

Use this guide to adopt, upgrade, or roll back the pinned shell framework.
For shared paths, shell entrypoints, and Node.js, see [Shell](shell.md).

## Ownership and versions

Chezmoi owns the Zsh modules, `~/.config/p10k/p10k.zsh`, and four commit-pinned
archive declarations in `.chezmoiexternal.toml`:

| Target under `$HOME` | Upstream |
|---|---|
| `.oh-my-zsh` | `ohmyzsh/ohmyzsh` |
| `.oh-my-zsh/custom/themes/powerlevel10k` | `romkatv/powerlevel10k` |
| `.oh-my-zsh/custom/plugins/zsh-autosuggestions` | `zsh-users/zsh-autosuggestions` |
| `.oh-my-zsh/custom/plugins/zsh-syntax-highlighting` | `zsh-users/zsh-syntax-highlighting` |

URLs contain full commit hashes. There is no periodic upgrade hook; the
declarations, not retained `.git` directories, are the version authority.
OMZ automatic updates are disabled before the framework loads. Do not update
these targets with `omz update`, `upgrade_oh_my_zsh`, or `git pull`.

Both shell configurations and their dependencies deploy regardless of the
`shell` preference. Explicit `ZSH` or `ZSH_CUSTOM` overrides still select
machine-local installations; the declarations do not deploy those paths.

## Understand non-exact archives

All four archives use `exact = false` to preserve local additions. The OMZ
archive excludes `custom/`, `cache/`, and `log/`; nested archives own only
their respective dependencies. Local edits to upstream-owned files still
conflict and need review.

Downloaded source, `.git` metadata, caches/logs, compiled `.zwc` files, P10k
instant prompts, and gitstatus downloads stay machine-local. Gitstatus normally
uses `~/.cache/gitstatus`; optional in-tree `gitstatus/usrbin/` is ignored too.
Do not recursively add these trees to chezmoi.

Installing a missing archive may contact GitHub. Cached archives can be reused;
offline tests substitute local fixtures and do not fetch upstream.

## Migrate an existing installation

Keep the current terminal open until a new Zsh passes startup checks. Do not
use a full-HOME apply.

1. Inspect all four checkouts for tracked changes and ignored/untracked custom
   files. Compare with the pinned revisions privately; custom contents may
   contain sensitive data.
2. Back up the complete framework tree, including nested repositories and
   `custom/`, plus Zsh and P10k configuration:

   ```sh
   (
       set -eu
       umask 077
       scratch_root="$HOME/.local/state/agents/tmp"
       mkdir -p -- "$scratch_root"
       backup=$(mktemp -d "$scratch_root/zsh-migration.XXXXXXXX")
       for path in .oh-my-zsh .config/zsh .config/p10k; do
           if [ -e "$HOME/$path" ]; then
               mkdir -p -- "$backup/$(dirname -- "$path")"
               cp -a -- "$HOME/$path" "$backup/$path"
           fi
       done
       printf 'Retained backup: %s\n' "$backup"
   )
   ```

   This example is only for secret-free trees. If custom files contain
   credentials, use a private backup outside retained agent scratch instead.
   Capture the printed absolute path and leave the backup in place.
3. Run `./tests/check-shell.sh` and `git diff --check`.
4. Preview the explicit framework and loader targets:

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=encrypted,scripts \
       "$HOME/.oh-my-zsh" \
       "$HOME/.config/zsh/rc.d/20-framework.zsh"
   ```

   A preview can download the pinned archives and display local edits to
   upstream-owned files. Inspect privately if necessary; verify there are no
   removals or unrelated changes.
5. Apply those reviewed targets without refreshing externals:

   ```sh
   chezmoi --refresh-externals=never apply --skip-secrets \
       --exclude=encrypted,scripts \
       "$HOME/.oh-my-zsh" \
       "$HOME/.config/zsh/rc.d/20-framework.zsh"
   ```

   Do not force unexpected conflicts. Existing `.git` directories and local
   additions remain; P10k preferences are managed separately and need not be
   reapplied for this takeover.
6. Open a new terminal. Check the prompt, Git segment, suggestions, syntax
   highlighting, and retained custom behavior. In Zsh,
   `zstyle -s ':omz:update' mode mode` should place `disabled` in `$mode`.

For a fresh machine, deploy the reviewed shell configuration first, then use
the explicit framework target above. Basic completion remains available
until OMZ is installed.

## Upgrade or roll back

1. Select reviewed upstream commits and change only their full hashes in
   `.chezmoiexternal.toml`. A new URL selects a new cache key;
   `--refresh-externals` alone cannot advance a pinned commit.
2. Review upstream changes and runtime requirements, especially deleted or
   renamed files. Back up the targets using the procedure above.
3. Run `./tests/check-source.sh` and `git diff --check`. Preview/apply only
   the affected targets and test a new interactive Zsh before closing the old one.
4. When committing the update, commit version declarations only, not downloaded
   framework files, binaries, or caches.

Non-exact archives do not remove obsolete upstream files. On rollback, files
introduced by the newer version can remain too. Compare archive inventories
and move only reviewed obsolete upstream files into the captured backup.
Do not enable `exact` or run broad cleanup on an existing tree to handle this.
Extra executables in OMZ's auto-loaded directories can change runtime behavior
even with unchanged pins.

To roll back managed content, restore the previous URLs and repeat targeted
review/apply, including obsolete-file handling. A complete pre-change backup
is the recovery fallback; preserve newer local edits before restoring it.

## Related references

- [Chezmoi external sources](https://www.chezmoi.io/user-guide/include-files-from-elsewhere/)
- [Oh My Zsh update settings](https://github.com/ohmyzsh/ohmyzsh#keeping-oh-my-zsh-up-to-date)
- [Offline check matrix](development.md#checks-by-area)

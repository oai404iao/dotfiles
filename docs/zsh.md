# Zsh dependency ownership

Chezmoi manages the Zsh modules, `~/.config/p10k/p10k.zsh`, and four
commit-pinned archives declared in `.chezmoiexternal.toml`:

| Target under `$HOME` | Upstream |
| --- | --- |
| `.oh-my-zsh` | `ohmyzsh/ohmyzsh` |
| `.oh-my-zsh/custom/themes/powerlevel10k` | `romkatv/powerlevel10k` |
| `.oh-my-zsh/custom/plugins/zsh-autosuggestions` | `zsh-users/zsh-autosuggestions` |
| `.oh-my-zsh/custom/plugins/zsh-syntax-highlighting` | `zsh-users/zsh-syntax-highlighting` |

The initial pins preserve the previously installed revisions. Each archive
URL contains a full commit hash, not a moving branch or tag. There is no
periodic refresh or upgrade hook. Applying a missing archive requires network
access; subsequent operations can reuse chezmoi's cache. These dependencies,
like both shell configurations, are independent of the `shell` preference.

Downloaded source is not vendored into this repository. Zsh's framework
module disables OMZ updates before loading OMZ; do not use `omz update`,
`upgrade_oh_my_zsh`, or `git pull` to update these targets. Retained `.git`
directories are ignored historical metadata, not the version authority.
Overrides of `ZSH` or `ZSH_CUSTOM` still select machine-local installations;
those paths are not deployed by these declarations.

All four archives use `exact = false` to avoid deleting local additions.
The OMZ archive excludes its `custom/`, `cache/`, and `log/` contents, leaving
custom files alone while the three nested archives own only their respective
dependencies. Local edits to an upstream-owned file still conflict with
takeover or upgrades and must be reviewed before applying.

Caches, logs, `.git` metadata, compiled `.zwc` files, P10k instant-prompt
files, and gitstatus daemon downloads remain machine-local. In particular,
gitstatus normally downloads under `~/.cache/gitstatus`; its optional
in-tree `gitstatus/usrbin/` is ignored too. Do not recursively `chezmoi add`
the framework or any of these dependency directories.

## Migrate an existing installation

Keep the current terminal open until a new Zsh has passed its startup check.
Do not run a full-HOME apply.

1. Check each of the four existing Git checkouts for local changes, including
   ignored/untracked custom files. Review differences against the pinned
   revisions. Do not print private custom-file contents into shared logs.
2. Back up the complete framework tree, including nested repositories and
   `custom/`, plus the existing Zsh and P10k configuration. For example:

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

   Record that printed path. Leave the backup in place. Chezmoi does not
   delete existing `.git` directories or local additions during takeover.
3. Run `./tests/check-shell.sh` and `git diff --check`. The dependency tests
   substitute local fixture archives and do not contact GitHub or a vault.
4. Preview only the relevant targets:

   ```sh
   chezmoi diff --recursive --skip-secrets --exclude=encrypted,scripts \
       "$HOME/.oh-my-zsh" \
       "$HOME/.config/zsh/rc.d/20-framework.zsh"
   ```

   The preview may download the four pinned archives. It can also display
   local edits to upstream-owned files; inspect privately if necessary.
   Verify there are no removals or unrelated configuration changes.
5. Apply the reviewed targets without refreshing the cache:

   ```sh
   chezmoi --refresh-externals=never apply --skip-secrets \
       --exclude=encrypted,scripts \
       "$HOME/.oh-my-zsh" \
       "$HOME/.config/zsh/rc.d/20-framework.zsh"
   ```

   Do not force an unexpected conflict. P10k preferences are already managed
   separately and need not be reapplied for this migration.
6. Open a new terminal. Check the prompt, Git status segment, suggestions,
   syntax highlighting, and that `zstyle -s ':omz:update' mode mode` returns
   `disabled` in `$mode`. Confirm that custom files still work.

On a fresh machine, review and deploy the managed shell configuration first,
then use the same explicit framework target to install dependencies. Until
OMZ is present, the existing basic completion fallback remains available.

## Upgrade or roll back

1. Select reviewed upstream commits and replace only their full hashes in
   `.chezmoiexternal.toml`. Changing the URL selects a new archive cache key;
   `--refresh-externals` alone does not advance a pinned commit.
2. Inspect upstream changes, especially deleted or renamed files and changes
   in runtime requirements. Back up the current targets as above.
3. Run `./tests/check-source.sh` and `git diff --check`, then preview and apply
   the explicit targets using the migration commands. Retain the current
   terminal and check a new interactive Zsh before closing it.
4. Commit the version declarations after verification. Never commit downloaded
   framework files, runtime binaries, or cache directories.

Non-exact deployment intentionally does **not** remove files dropped by an
upstream version. This also applies on rollback: new files from the newer
version can remain. Compare archive inventories and, if needed, move only
reviewed obsolete upstream files into the captured backup directory. Do not
enable `exact` on the existing tree or run broad cleanup to handle this.
Extra executable files under OMZ's auto-loaded directories can affect behavior,
so a pin alone does not guarantee an identical runtime when such files remain.

To roll back managed contents, restore the previous pinned URLs and repeat
the targeted review/apply workflow, handling obsolete files as above. A
complete pre-change backup is the recovery fallback; restore it only after
preserving any newer local edits.

See the [chezmoi external-source guide](https://www.chezmoi.io/user-guide/include-files-from-elsewhere/)
and [OMZ update settings](https://github.com/ohmyzsh/ohmyzsh#keeping-oh-my-zsh-up-to-date).

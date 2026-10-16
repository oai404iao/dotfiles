# Maintain the configuration

Use this workflow on an initialized machine. For first setup, follow the
[Quickstart](quickstart.md); for encrypted or secret-bearing targets, read
[Security](security.md) before previewing anything.

## Update the source

From the source directory:

```sh
cd "$(chezmoi source-path)"
git status --short --branch
```

Preserve uncommitted work before integrating upstream changes. On a clean
appropriate branch, a fast-forward update avoids an implicit merge:

```sh
git pull --ff-only
./tests/check-source.sh
```

Review incoming source changes before deploying them. Updating Git does not
apply targets, refresh all external resources, or restart applications.

## Preview and apply one target

First back up a pre-existing target. The following is for a known sanitized
configuration file, such as the shared toolchain environment:

```sh
chezmoi status --skip-secrets --exclude=encrypted \
    "$HOME/.config/shell/toolchains.sh"
chezmoi diff --skip-secrets --exclude=encrypted \
    "$HOME/.config/shell/toolchains.sh"
chezmoi apply --exclude=scripts,encrypted \
    "$HOME/.config/shell/toolchains.sh"
```

For other targets, choose the component's documented command. Excluding
`scripts` prevents apply hooks for this isolated update; it is not a substitute
for reviewing the target. External sources may still need network access.

Never diff Pi `auth.json`, a possibly credential-bearing `models.json`,
Telegram credentials, or decrypted SSH/Git inventory. `--skip-secrets` is not
redaction. Follow [Pi](pi.md#credentials), [Git](git.md), or [SSH](ssh.md)
instead. Do not use a full-HOME apply merely to validate a source change.

## Add a configuration file

1. Classify the file using [ownership rules](how-it-works.md#decide-who-owns-a-file).
2. Check that the target contains no credentials, history, caches, or local identifiers.
3. Add one explicit declarative file, for example:

   ```sh
   chezmoi add "$HOME/.config/example/config"
   ```

4. Inspect the resulting source attributes, permissions, and machine conditions.
5. Update the area test when its inventory or invariant changes.
6. Run `./tests/check-source.sh` and `git diff --check`, then review the source diff.

The example path is a placeholder, not a target supplied by this repository.
Never recursively add `$HOME`, `.config`, an XDG root, or a downloaded package
tree. Add a precise `.chezmoiignore` entry for mutable state instead.

## Check activation

Application behavior determines when a change takes effect:

- Open a new login session for shared environment and locale changes.
- Open a new interactive shell after changing shell modules.
- Restart Pi completely after upgrading its host; `/reload` does not replace the SDK.
- Follow the desktop/Tether guides for service changes; ignored targets do not stop services.
- Unlock `rbw` before SSH signing or first model-key resolution in a new Pi process.
  A running Pi process retains its resolved key in memory.

## Recover from an unexpected result

Stop before forcing a conflict. Compare the reviewed source with the private
backup and restore only the affected component, preserving newer local work.
For generated files, repair the generator rather than making a seed overwrite
application state. For non-exact Zsh archives, review obsolete files explicitly;
a rollback of pins does not remove files introduced by a newer archive.

See [Zsh recovery](zsh.md#upgrade-or-roll-back),
[desktop switching](desktop-shells.md#switch-an-existing-machine), and
[Pi authentication](pi.md#apply-authentication-references-safely) for procedures
with additional ordering requirements.

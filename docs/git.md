# Configure Git identities

Git behavior is public configuration; names, email addresses, and
account-specific GitHub routing are age-encrypted metadata. Commit identity
and SSH authentication are separate: one determines who signs a commit's
metadata, the other determines which account can access a remote.

## Configuration layout

`dot_gitconfig` includes a default identity and path-specific profiles:

| Repository location | Included target |
|---|---|
| Everywhere | `~/.config/git/.gitconfig-identity` |
| `~/Dev/company/` | `~/.config/git/.gitconfig-work` |
| `~/Dev/local/` | `~/.config/git/.gitconfig-person` |
| `~/Dev/github/` | `~/.config/git/.gitconfig-github` |

Encrypted sources are under `dot_config/git/encrypted_private_dot_gitconfig-*.age`.
The default and personal identities match. Public-facing identities use
ID-based GitHub `noreply` addresses; the organization profile can keep its
required address inside ciphertext. The personal profile leaves `github.com`
unchanged. Only the `~/Dev/github/` profile rewrites `git@github.com:` through
its account-specific SSH alias.

The public config selects `main` for new repositories and the `libsecret`
credential helper. It does not install the helper or migrate keyring data.
Graphical Secret Service activation is documented under
[desktop keyring](desktop.md#desktop-keyring).

## Adopt the configuration

1. Restore the age identity privately using the [Quickstart](quickstart.md).
2. Back up existing `~/.gitconfig` and `~/.config/git` privately. Do not print
   identity-bearing destination diffs into shared logs.
3. Review the public source and trusted encrypted revision, then validate:

   ```sh
   CHECK_PRIVATE_CONFIG=1 ./tests/check-git.sh
   ```

4. Apply only the reviewed targets, without unrelated hooks:

   ```sh
   chezmoi apply --exclude=scripts "$HOME/.gitconfig" "$HOME/.config/git"
   ```

The validator checks decrypted structure and routing without printing the
values or using the vault. A public age recipient does not prove authorship;
trusted source review remains necessary.

## Choose a remote account

Use an explicit SSH alias when cloning:

```sh
git clone git@github-primary:OWNER/repository.git
git clone git@github-secondary:OWNER/repository.git
```

`OWNER/repository` is a placeholder. The destination repository's conditional
Git configuration is not active until after cloning, so do not rely on its
path-specific rewrite for that first connection. See
[GitHub SSH accounts](ssh.md#github-accounts) for identity verification; those
commands are live authentication checks.

## Change an identity

Keep names, addresses, and account-specific rewrites inside the corresponding
encrypted source. Update `tests/check-git.sh` if the profile inventory or schema
changes. Run `CHECK_PRIVATE_CONFIG=1 ./tests/check-git.sh` before applying new
ciphertext, and the complete trusted source suite before publishing it.

Do not copy real identity values into examples, public configuration, or test
fixtures. Before publication, also validate reachable commit history using
the [publication gates](publication.md).

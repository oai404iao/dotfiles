# Use Bitwarden-backed SSH

Chezmoi manages OpenSSH client policy, public selector keys, and optional
inbound `authorized_keys`. Private keys remain in native Bitwarden SSH items;
`rbw-agent` signs without writing them to managed files.

Start with [machine data](#machine-data) for a fresh profile or
[takeover](#taking-over-an-existing-machine) for an existing installation.
Network authentication and vault commands below are manual live operations,
not offline tests.

## Ownership

| Owner | Data |
|---|---|
| Git | Generic SSH policy and age-encrypted public selectors/host inventory |
| Bitwarden | Native SSH items and private key material |
| Machine | Host trust, local fragments, and legacy migration copies |

OpenSSH private keys, host keys, `sshd_config`, and `known_hosts*` are never
managed here. Public keys are not credentials, but their fingerprints and
host/user mapping are encrypted to avoid correlation and topology disclosure.

## Identities

The six managed selectors are distinct Ed25519 public keys:

| Selector | Purpose |
|---|---|
| `private` | Personal private-network hosts |
| `uni` | Personal remote servers |
| `company_dev` | Company development hosts |
| `company_ai` | Company AI hosts |
| `github_primary` | One GitHub account |
| `github_secondary` | The other GitHub account |

Targets under `~/.ssh/identities/` contain public keys only. A public
`IdentityFile` selects the matching agent key, and each managed host uses
`IdentitiesOnly yes` to avoid offering unrelated identities.

This is key selection, not isolation: rbw-agent exposes every native SSH key
in the active vault to same-UID processes. Do not enable global agent
forwarding or treat Host rules as a boundary around the vault.

## Machine data

Set these non-secret values in `[data]` during initialization, or use
`chezmoi edit-config` on an initialized machine:

```toml
[data]
    sshAgent = true
    sshInboundIdentity = "none"
```

| Setting | Ownership |
|---|---|
| `sshAgent = true` | Client config, public selectors, SSH socket environment |
| `sshAgent = false` | No client-side SSH management |
| `sshInboundIdentity = "private"` | Entire `authorized_keys` replaced with the `private` public key |
| `sshInboundIdentity = "uni"` | Entire `authorized_keys` replaced with the `uni` public key |
| `sshInboundIdentity = "none"` | Existing `authorized_keys` left unmanaged |

Disabling a capability does not remove previously rendered files. Switching
inbound ownership to `none` does not revoke access: remove or replace the old
file explicitly if that is intended. Likewise, review old client config,
selectors, and socket environment when retiring `sshAgent`.

## Encrypted source

The six selectors, real Host blocks, and conditional authorized-keys template
use native `encrypted_` sources. Git identity profiles and account routing
use the same mechanism; see [Git](git.md).

Exact Host blocks precede `90-defaults.conf`'s catch-all. The `20-uni.conf`
fragment groups remote hosts using the `uni` selector. Every managed host
must keep one public IdentityFile; do not add a global one.

Never display decrypted inventory as a review diff. `--skip-secrets` does not
exclude native encrypted sources; add `--exclude=encrypted` when inspecting
other targets. For SSH changes, review the trusted source revision and run:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-ssh.sh
```

The trusted check decrypts into a protected temporary directory, validates
six distinct Ed25519 keys, allowlists Host directives, and ensures both
inbound keys match their selectors without printing values. Default fixture
tests also work without the real identity. Before publishing changed encrypted
data, run the complete trusted [publication gates](publication.md).

The public age recipient lets anyone create replacement ciphertext. A valid
payload is not proof of a trusted author.

## Agent lifecycle

The managed environment selects `$XDG_RUNTIME_DIR/rbw/ssh-agent-socket` while
preserving an existing `SSH_AUTH_SOCK`, such as a forwarded agent. There is
no managed systemd service or automatic unlock. `rbw unlock` starts the
background agent when necessary.

Use the default one-hour inactivity timeout. If the machine previously set an
explicit timeout, restore the default once:

```sh
rbw config unset lock_timeout
```

Before signing, explicitly synchronize/unlock and inspect the selected agent:

```sh
rbw sync
rbw unlock
ssh-add -l
```

The default 3600-second timeout slides after successful unlocks, secret
decryptions (such as `rbw get`), and SSH identity listing/signing. Status
queries (`rbw unlocked`), sync, and version checks do not reset it. Expiry or
an explicit lock clears in-memory vault keys but leaves the agent running.
Desktop screen locking is not connected to rbw locking here.

Preserve the user's current lock state during tests and migration.
`rbw lock` and `rbw stop-agent` affect other applications sharing the agent;
only the user decides when to run them.

## GitHub accounts

One account remains the `github.com` default for existing repositories. Use
explicit aliases when cloning or selecting a remote:

```sh
git clone git@github-primary:OWNER/repository.git
git clone git@github-secondary:OWNER/repository.git
git remote set-url origin git@github-secondary:OWNER/repository.git
```

Replace `OWNER/repository` with the intended repository. Conditional Git
profiles rewrite `git@github.com:` for existing repositories, but the
destination's conditional config is not active during the initial clone.
Commit identity and SSH access remain separate; see [Git](git.md).

When a live check is intended, verify each account independently:

```sh
ssh -T git@github-primary
ssh -T git@github-secondary
```

Local fragments under `~/.ssh/config.local.d/` may add new aliases only.
Do not overlap a managed alias or use `Host *`: IdentityFile is additive,
so overlap can add another selector despite `IdentitiesOnly yes`.

## Taking over an existing machine

Keep an authenticated inbound session open until replacement access works.
Backups and key imports below contain secrets and must remain private.

1. Back up existing `~/.ssh/config` and `authorized_keys` privately.
2. Import legacy private keys into versioned native Bitwarden SSH items.
3. Run `rbw sync` and `rbw unlock`; compare public fingerprints privately.
4. Register every replacement key remotely before changing its client
   assignment. Temporarily append the intended inbound public key to the
   existing `authorized_keys`.
5. Open a second inbound session with that key while retaining the old session.
6. Set `sshAgent = true` and the intended inbound identity with
   `chezmoi edit-config`.
7. Run `CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh`.
8. Apply only the reviewed client targets and any related Git profiles:

   ```sh
   chezmoi apply --exclude=scripts "$HOME/.gitconfig" "$HOME/.config/git"
   chezmoi apply --exclude=scripts "$HOME/.ssh/identities"
   chezmoi apply --exclude=scripts \
       "$HOME/.config/environment.d/20-rbw-ssh-agent.conf" \
       "$HOME/.config/shell/ssh-agent.sh" \
       "$HOME/.config/shell/profile.sh"
   chezmoi apply --exclude=scripts "$HOME/.ssh/config" "$HOME/.ssh/config.d"
   ```

9. Activate the new environment and test required private, company, and GitHub
   aliases. Only then apply `~/.ssh/authorized_keys` and verify another fresh
   inbound session.
10. After all required connections work through rbw-agent, move legacy private
    files to ignored `~/.ssh/legacy/` quarantine. Retain them through the
    rollback period; deletion is a separate decision.

A rollback needs both the old config and its key files restored to their
original paths. A config backup alone still references the legacy key paths.

## Rotation

1. Create a new versioned Bitwarden item; keep the old item authorized during
   the transition.
2. Register the new public key remotely, then update the encrypted selector.
   For `private`/`uni`, update the encrypted authorized-keys template too.
3. Run the trusted check; mismatched selectors and inbound keys must fail.
4. Sync/unlock rbw, apply reviewed targets, and test new connections.
5. Remove the old authorization and item only after replacement access works.

Rotating `private` or `uni` affects every host in that shared trust domain.
GitHub keys rotate independently per account.

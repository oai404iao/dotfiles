# SSH Management

Chezmoi manages OpenSSH client configuration, public selector keys, and
optionally `authorized_keys`. Bitwarden native SSH key items hold the matching
private keys, and `rbw-agent` performs signing without writing those private
keys to managed files.

## Ownership

| Owner | Data |
|---|---|
| Git | Generic SSH policy plus age-encrypted selectors and host inventory |
| Bitwarden | Native SSH key items and private key material |
| Machine | `known_hosts*`, local config fragments, and legacy migration copies |

The repository never manages OpenSSH private keys, host keys, `sshd_config`, or
`known_hosts*`. Public keys are not credentials, but their fingerprints and the
host/user mapping are encrypted to prevent correlation and topology disclosure.

## Identities

All managed keys are distinct Ed25519 keys.

| Selector | Purpose |
|---|---|
| `private` | Personal private-network hosts |
| `uni` | Personal remote servers |
| `company_dev` | Company development hosts |
| `company_ai` | Company AI hosts |
| `github_primary` | One GitHub account |
| `github_secondary` | The other GitHub account |

The files under `~/.ssh/identities/` contain only public keys. OpenSSH accepts a
public `IdentityFile` and asks the agent for the matching private key.
`IdentitiesOnly yes` on every managed host prevents unrelated agent identities
from being offered accidentally.

`rbw-agent` exposes every native SSH key item in the active vault. The selector
files prevent accidental use, but do not isolate keys from other processes
running as the same user.

## Encrypted Source

The six selector files, the real Host blocks, and the conditional
`authorized_keys` template use chezmoi's native `encrypted_` source attribute.
They are age ciphertext in Git and are decrypted only while chezmoi computes a
target. Git identity profiles and their account-specific URL rewrites are
encrypted for the same metadata-privacy reason.

`--skip-secrets` does not exclude native encrypted source files. Broad review
and bootstrap commands must use both:

```sh
chezmoi diff --skip-secrets --exclude=encrypted
chezmoi apply --interactive --skip-secrets --exclude=encrypted
```

Before applying changed encrypted SSH data, run the no-output trusted check:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

It decrypts into protected temporary directories, validates Git profiles and
six distinct Ed25519 keys, allowlists Host directives, and checks that both
inbound keys match their selector files. It never prints decrypted values. The
default tests also render independently generated fake identities, keys, and
hosts, so they remain usable without the real age identity.

An age recipient authenticates ciphertext integrity, not its author. Review
encrypted changes only from trusted commits, and require the trusted check
before publishing or applying them.

## Machine Data

New machines configure two values during `chezmoi init`:

```toml
[data]
    sshAgent = true
    sshInboundIdentity = "none"
```

- `sshAgent = true` deploys client config, public selectors, and the
  `SSH_AUTH_SOCK` environment.
- `sshAgent = false` leaves all client-side SSH files unmanaged.
- `sshInboundIdentity = "private"` fully manages `authorized_keys` with the
  `private` public key.
- `sshInboundIdentity = "uni"` fully manages it with the `uni` public key.
- `sshInboundIdentity = "none"` leaves an existing `authorized_keys`
  untouched.

For an already initialized machine, use `chezmoi edit-config` and add the
values deliberately. Do not rerun `chezmoi init` merely to add them.

Changing an inbound identity to `none` relinquishes ownership; it does not
delete a previously rendered file. Remove or replace that file explicitly if
the intent is to disable SSH access.

Changing `sshAgent` from `true` to `false` likewise stops management without
deleting client files rendered earlier. Review and remove the old config,
selectors, and socket environment explicitly after changing the machine data.

## Agent Lifecycle

Set the machine-local timeout once:

```sh
rbw config set lock_timeout 900
```

The managed login and graphical-session environment uses:

```text
$XDG_RUNTIME_DIR/rbw/ssh-agent-socket
```

The shell fragment preserves an existing `SSH_AUTH_SOCK`, including a
forwarded agent. Unlock explicitly when signing is needed:

```sh
rbw sync
rbw unlock
ssh-add -l
```

There is no automatic unlock and no managed systemd service. Running
`rbw unlock` starts the rbw background agent when needed. Tests and migration
commands must preserve the current rbw lock state: `rbw lock` and
`rbw stop-agent` affect other programs sharing the agent, so only the user
decides when to run them.

The 900-second value is a sliding inactivity timeout. Successful unlocks,
secret decryptions such as `rbw get`, and SSH identity listing or signing
restart the timer. `rbw unlocked`, `rbw sync`, and version checks do not.
Expiry or an explicit `rbw lock` clears the in-memory vault keys but leaves the
agent process running. This repository does not connect rbw locking to the
desktop lock screen.

## GitHub Accounts

One account remains the `github.com` default so existing repositories keep
working. Use the account-specific aliases from the rendered SSH config for
unambiguous remotes:

```sh
git clone git@github-primary:OWNER/repository.git
git clone git@github-secondary:OWNER/repository.git

git remote set-url origin \
  git@github-secondary:OWNER/repository.git
```

Verify each identity independently:

```sh
ssh -T git@github-primary
ssh -T git@github-secondary
```

Git commit identity and SSH authentication are separate. The path-specific Git
profiles rewrite `git@github.com:` to the appropriate SSH alias. Use the alias
explicitly when cloning because the destination repository's conditional Git
config is not yet active. Public-facing profiles use each account's ID-based
GitHub `noreply` address; the work profile retains its required identity only
inside age ciphertext.

Local fragments under `~/.ssh/config.local.d/` are for additional aliases only.
They must not match a managed alias or use `Host *`: `IdentityFile` is additive,
so an overlapping fragment could add another selector despite
`IdentitiesOnly yes`.

## Taking Over an Existing Machine

Keep an authenticated SSH session open throughout an inbound-key migration.

1. Back up the existing `~/.ssh/config` and `authorized_keys` privately.
2. Import the legacy private keys into versioned native Bitwarden SSH items.
3. Run `rbw sync`, `rbw unlock`, and compare public fingerprints.
4. Temporarily append the selected inbound public key to the existing
   `authorized_keys`, and register each replacement key remotely before
   changing its client assignment.
5. Open a second inbound session with the selected key while keeping the old
   authenticated session open.
6. Add `sshAgent = true` and the intended inbound identity with
   `chezmoi edit-config`.
7. Validate the source with `CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh`.
8. Apply and test only the reviewed targets:

   ```sh
   chezmoi apply "$HOME/.gitconfig" "$HOME/.config/git"
   chezmoi apply "$HOME/.ssh/identities"
   chezmoi apply \
     "$HOME/.config/environment.d/20-rbw-ssh-agent.conf" \
     "$HOME/.config/shell/ssh-agent.sh" \
     "$HOME/.config/shell/profile.sh"
   chezmoi apply "$HOME/.ssh/config" "$HOME/.ssh/config.d"
   ```

9. Test private, company, and GitHub aliases, then apply
   `~/.ssh/authorized_keys` and open another fresh inbound session.
10. Move legacy private-key files to the ignored `~/.ssh/legacy/` quarantine
    after every required connection succeeds through `rbw-agent`. Delete them
    only after the remaining rollback period.

During the quarantine period, a rollback must restore both the old config and
the required key files to their original `~/.ssh/` paths; the backup config
still references those legacy paths.

## Rotation

Create a new versioned Bitwarden item and keep the old item while both public
keys are authorized. Update the encrypted selector and, for `private` or `uni`,
the encrypted `authorized_keys` template. The trusted check rejects a mismatch.
Sync and unlock rbw, test new connections, then remove the old authorization
and item.

Rotating `private` or `uni` affects every host in that shared trust domain.
GitHub keys rotate independently per account.

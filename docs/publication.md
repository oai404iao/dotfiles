# Publish the repository safely

Publication is a release process, not just a visibility toggle. Encrypted
files still contain private topology and identity metadata when decrypted,
and deleting plaintext at the latest commit does not remove older blobs.

Read [Security](security.md) before inspecting destinations. This guide does
not authorize history rewriting, ref deletion, force-pushing, or changing
remote visibility; those require a deliberate publication task.

## Release gates

With the real age identity available, run from the source root:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
git diff --check
git status --short
```

The final release gate requires an empty worktree status. Do not discard
unrelated changes to achieve it; resolve their ownership separately.

`tests/check-public.sh` scans the worktree, index, non-ignored untracked files,
and every commit reachable from any local ref. Its checks reject:

- Recognized private-key material and plaintext SSH keys/inventory.
- Unencrypted account-specific Git routing and non-allowlisted email addresses.
- Commit identities that do not use an ID-based GitHub `noreply` address.
- Replacement refs or grafts; replacement-object processing is disabled.
- Malformed armored ciphertext, parsed with `age-inspect`.

Private-config validators check decrypted structure without printing values
or contacting the vault. They cannot prove who authored replacement
ciphertext: trusted commit review is still required.

## History rewrites

If private metadata exists in history, prepare recovery before rewriting:

1. Freeze pushes and close or merge open pull requests.
2. Store a pre-rewrite bundle outside the source with directory mode `0700`
   and file mode `0600`. Keep it private; never push it.
3. Rewrite every affected local branch/tag, including author and committer
   addresses that expose private email.
4. Remove reviewed backup/original refs and stale remote-tracking refs, expire
   reflogs, and garbage-collect unreachable objects as part of the authorized
   rewrite. These are destructive operations, not routine cleanup.
5. Rerun the release gates against every remaining ref.

Old clones can reintroduce removed commits through an ordinary merge or push.
Replace them with fresh clones or deliberately clean/rebase them before reuse.
Keep the isolated pre-rewrite bundle for recovery, never below the chezmoi source.

## Remote publication

Prefer a new empty remote containing only the sanitized history. If an old
private remote received sensitive history, do not simply change its
visibility. Delete/recreate it deliberately or follow the hosting provider's
complete sensitive-data removal process.

A force-push alone may leave objects accessible through forks, pull-request
refs, or cached views. Consult GitHub's
[sensitive-data removal procedure](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
for its limitations and support process.

After the intended publication:

1. Clone the public remote into a fresh task-local directory.
2. Run `./tests/check-public.sh` from that clone.
3. Compare its `main^{tree}` object ID with the reviewed local tree.
4. Only then treat the remote as canonical or announce it.

Report which history and remote were verified. A local source check alone
does not verify the contents of a newly published remote.

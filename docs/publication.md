# Public Repository Safety

The repository is designed to be publicly readable, but the age-encrypted
files still describe private topology and identity metadata when decrypted.
Treat publication as a release process rather than a visibility toggle.

## Release Gates

Run the complete trusted validation with the real age identity available:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
git diff --check
git status --short
```

`tests/check-public.sh` scans the working tree, index, non-ignored untracked
files, and every commit reachable from any local ref. It rejects recognized
private-key material, plaintext SSH public keys and inventory, unencrypted Git
account routing, non-allowlisted email addresses, and commit identities that do
not use an ID-based GitHub `noreply` address. `git status --short` must also be
empty at the final gate.

The private-config checks decrypt into protected temporary directories and
validate structure without printing values. They do not prove that replacement
ciphertext came from a trusted author, so encrypted changes still require
trusted commit review.

## History Rewrites

Deleting a file in a new commit does not remove its older blobs. Before
publishing a repository that previously contained private metadata:

1. Freeze pushes and close or merge open pull requests.
2. Store a pre-rewrite bundle outside the repository with directory mode
   `0700` and file mode `0600`.
3. Rewrite every affected local branch and tag, including author and committer
   addresses when they expose private email.
4. Remove local backup/original refs and stale remote-tracking refs, expire
   reflogs, and garbage-collect unreachable objects.
5. Run the release gates against every remaining ref.
6. Keep the private bundle isolated; never push it or place it below the
   chezmoi source directory.

Old clones can reintroduce removed commits through an ordinary merge or push.
Replace them with fresh clones, or clean and rebase them deliberately.

## Remote Publication

Prefer pushing the sanitized history to a new empty repository. If an existing
private remote has received the old history, do not merely change its
visibility. Either delete and recreate it before the first public push, or
follow GitHub's complete sensitive-data removal process.

A force-push alone may leave old objects reachable through forks, pull-request
refs, or cached views. GitHub documents the limitations and support process in
[Removing sensitive data from a repository][github-sensitive-data].

After publishing:

1. Clone the public remote into a new temporary directory.
2. Run `./tests/check-public.sh` in that clone.
3. Compare its `main^{tree}` object ID with the reviewed local tree.
4. Only then treat the public remote as the canonical source.

[github-sensitive-data]: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository

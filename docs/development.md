# Develop and verify the source

This is a configuration repository, not an application or monorepo. There is
no repository-wide dependency bootstrap or build command. Work from the
chezmoi source root, normally `~/.local/share/chezmoi`.

## Make a focused change

1. Check the branch and worktree. Use a focused development branch and preserve
   unrelated work; do not use destructive cleanup to obtain a clean tree.
2. Classify each target as declarative, generated, mutable, or secret before
   adding it. See [ownership](how-it-works.md#decide-who-owns-a-file).
3. Change the owning source, template, or generator, not deployed state.
4. Update the domain test when an inventory, profile set, or invariant changes.
5. Keep `README.md` and `README.zh-CN.md` semantically synchronized.
6. Run the complete source checks and patch-hygiene check below, then inspect
   the source diff for credentials and machine-local state.

Source-only paths (`README*`, `AGENTS.md`, `docs/`, `scripts/`, and `tests/`)
must stay listed in `.chezmoiignore`. Preserve dependency lockfiles unless
the task explicitly updates them, especially `dot_config/nvim/lazy-lock.json`.

## Run the complete checks

```sh
./tests/check-source.sh
git diff --check
```

Install the common tools from the [Quickstart](quickstart.md). Tests use
Python 3 and, where needed, Bash, Zsh, Git, age, and chezmoi. Node.js and the
installed Pi runtime enable the offline Jev checks. The source wrapper checks
shell syntax and runs each domain suite; it does not apply to your real HOME.

Git and SSH checks use fixtures and, by default, also validate real encrypted
payloads when the configured age identity exists. Force or disable that part
explicitly with `CHECK_PRIVATE_CONFIG=1` or `0`; `auto` is the default. The
trusted publication/apply gate is:

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

This decrypts existing ciphertext locally without printing it. It does not
contact the real vault. Do not run it with shell tracing that might expose
sensitive arguments or output.

## Checks by area

All paths below are relative to the source root. These are useful while
iterating; they do not replace the required complete source check.

| Change | Targeted command |
|---|---|
| Shell environment, toolchains, Zsh externals | `./tests/check-shell.sh` |
| rbw config / terminal selection | `./tests/check-rbw.sh` |
| Git profiles | `./tests/check-git.sh` |
| Public files and reachable Git history | `./tests/check-public.sh` |
| SSH selectors, hosts, inbound ownership | `./tests/check-ssh.sh` |
| Pi models, modifiers, package policy, agent roles | `./tests/check-pi.sh` |
| Skill manifest and installer | `./tests/check-skills.sh` |
| Desktop environment, XDG directories, Waybar helpers | `./tests/check-desktop.sh` |
| GTK, fonts, Nautilus, and application settings | `./tests/check-desktop-apps.sh` |
| Shared Niri outputs and bindings | `./tests/check-niri.sh` |
| Custom/DMS profile matrix and generated themes | `./tests/check-desktop-profiles.sh` |
| Reminder-only DMS apply hook | `./tests/check-dms-apply-hints.sh` |
| Tether policy and service drop-ins | `./tests/check-tether.sh` |
| Secret Service activation | `./tests/check-keyring.sh` |

Use `CHECK_PRIVATE_CONFIG=1` with Git/SSH checks when real ciphertext changes.
The public check scans all locally reachable history as well as pending files;
deleting plaintext only at the tip is insufficient.

## Understand optional coverage

- The wrapper checks Neovim Lua/JSON only when `nvim` is installed.
- The wrapper runs Niri rendering/validation only when both chezmoi and Niri
  are installed. No Niri binary means this coverage did not run.
- Pi renders Telegram templates with `tests/fixtures/pi/bin/rbw`, never the
  real vault. Some template/runtime checks skip without chezmoi, Node, or Pi.
- GTK/desktop checks may skip display/binding-dependent coverage. DMS/Matugen
  generation and pnpm policy checks need their corresponding tools/versions.

Report actual skips alongside results. A final "passed" line from a wrapper
does not mean unavailable optional coverage ran. Consult each test's output
for the exact environment used.

## Keep verification offline

Tests must not access the real vault, call paid model APIs, send notifications,
or perform live authentication without an explicit user request. Do not
install or rebuild dependencies merely because a documentation page mentions
them. Pi's pnpm build approvals are declarative policy; a dependency rebuild
executes package code and is a separate operation.

For scratch output, use a fresh retained directory under
`~/.local/state/agents/tmp/` and scope `TMPDIR` per command where supported.
Preserve existing test cleanup contracts; some legacy tests have their own
temporary-root choices. See [Security](security.md#use-task-local-scratch-paths).

## Review and commit

For an authorized commit, stage task-related paths only, review the staged
diff, and run:

```sh
git diff --cached --check
```

Use Conventional Commits, for example `docs(shell): clarify Node migration`.
The global Git ignore can hide a newly created `AGENTS.md`; intentionally
check its tracked status when adding one. A documentation change does not
itself authorize a commit, push, deployment, or refresh of external content.

If deployment is requested, back up the destination and use an explicit
reviewed target. Follow the special Pi/SSH procedures rather than a broad
preview. Stop once the requested change and required checks are complete;
report completed work, tests actually run, skips, and remaining blockers.

## Write documentation

The structure follows the installed Pi documentation's separation of a short
README, a task-oriented index, a Quickstart, focused guides, and lookup
references. It borrows that organization, not Pi's application-specific
installation or contribution policies.

| Location | Reader's question |
|---|---|
| `README.md`, `README.zh-CN.md` | What is this repository, and where do I start? |
| `docs/index.md` | Which guide matches my task? |
| `docs/quickstart.md` | How do I reach a first working setup safely? |
| `docs/how-it-works.md` | What owns the source, targets, and local state? |
| `docs/configuration.md` | Which machine values are supported? |
| Component guides | How do I prepare, change, verify, or recover this component? |
| `AGENTS.md` | Which repository-specific mistakes must a coding agent avoid? |

Keep the documentation flat by topic; do not add a website/navigation build
system just to maintain Markdown. Update the index when adding a guide.
Split a long page only at a useful task or ownership boundary. Keep a short
link at an old section anchor when moving procedures that other pages use.

Start a guide with its purpose and prerequisites. Put safe ordered actions
before detailed reference, mark placeholders and live side effects, and state
what a check proves or cannot prove. Put warnings next to the dangerous step,
not only on a distant security page. Use tables for choices and owned fields;
do not duplicate a complete procedure across README, AGENTS, and a guide.

Verify commands against declarative sources and tests. Treat version-specific
upstream behavior as the adopted integration contract, not an unverified claim
about the latest release. Never read credentials to improve an example.
Check local paths, anchors, old-link compatibility, and bilingual README
meaning. Static instruction walkthroughs are not measured model behavior.

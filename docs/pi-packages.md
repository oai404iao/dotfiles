# Pi packages

Use this page to change extensions, set up notifications, approve reviewed
dependency builds, or migrate an old installation. The declarative package list
belongs to [`settings.json`'s modifier](../dot_config/private_pi/agent/modify_private_settings.json.tmpl);
downloads, manifests, lockfiles, and package checkouts remain machine-local.

## Package reference

| Purpose | Declaration |
| --- | --- |
| Structured questions | `npm:@juicesharp/rpiv-ask-user-question@2.13.9` |
| Codex tools and provider integration | `npm:@oai404iao/pi-codex-minimal-tools@5.1.2` |
| Asynchronous child agents | `npm:@oai404iao/pi-subagent@1.3.1` |
| Graphical notifications | `~/.local/share/pi/extensions/pi-local-notify` |
| Headless notifications | `npm:@oai404iao/pi-telegram-notify@1.0.0` |

Chezmoi selects exactly one notification declaration from `graphical` machine
data. All npm declarations are pinned; this does not pin every transitive
dependency. The tree-continue package is retired: applying settings stops
loading it without deleting its local checkout. Disabled packages and their
configuration are not managed.

The host must be **Pi 1.2.0+ with Node.js 22.19+**. Updating a nested
`pi-coding-agent` dependency does not update Pi's running SDK. Upgrade the
system-managed Arch package with `sudo pacman -Syu pi`, then fully restart Pi.

## Install or change packages

1. Review the package source and edit the declarative list, not downloaded
   implementations. Update `tests/check-pi.sh` invariants when changing pins
   or the managed file inventory.
2. Run the offline checks. Privately back up and review the explicit
   `~/.config/pi/agent/settings.json` target before applying it:

   ```sh
   chezmoi diff --skip-secrets --exclude=encrypted ~/.config/pi/agent/settings.json
   chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/settings.json
   ```

3. Reconcile/install packages deliberately. For example, the subagent upgrade
   uses `pi install npm:@oai404iao/pi-subagent@1.3.1 --no-approve`.
   Installation may access the registry and execute approved dependency code;
   it is not an offline configuration check. `--no-approve` skips trust-gated
   project resources, not package-code execution.
4. Restart Pi, or use `/reload` when no existing child work needs preserving.
   Spawn new children for role/tool changes.

Pi writes package commands back to local settings. A later chezmoi apply
restores the declared package list, model selection, enabled models, and
codemode defaults; review local differences before replacing those keys.
Do not apply the whole Pi directory to upgrade one package.

### Why Pi uses a hoisted pnpm layout

`"npmCommand": ["pnpm", "--config.node-linker=hoisted"]` affects Pi package
operations only. The `npm:` source prefix still identifies registry packages;
it does not require the npm executable.

Pi's jiti loader resolves extension imports from symlink paths without first
resolving their real paths. An isolated pnpm layout can therefore find stale
npm-era sibling packages or miss transitive dependencies. Applying this setting
does not rebuild an existing installation; use the
[layout migration](#pi-package-layout-migration), not manual sibling deletion.

## Codex tools reference

Bundle `5.1.2` composes core `3.0.1` and tools `0.1.1`, sharing runtime `3.0.1`.
The managed config/model schemas use `pi-codex-runtime@3.0.1`. Do not add
separate core/tools or compatibility declarations: the bundle supplies the
engine, patch, search, and image implementations.

The configuration preserves the adopted behavior rather than following newer
Standard/SSE defaults:

| Area | Managed contract |
| --- | --- |
| Model profiles | GPT-5.6 Sol is the Lite parent; GPT-6 Astra/Luna/Sol extend it. GPT-6.1 Terra extends GPT-6 Astra. GPT-6.1 Sol is supplied by the bundle. |
| Responses | Provider shim, developer system-prompt placement, automatic transport, WebSocket enabled/prewarm, automatic reasoning summaries. |
| Tools | Custom `apply_patch`; standalone web search for text/images; parallel tool calls disabled in these profiles. |
| Compaction | Native Responses compaction, using `compaction_trigger`. |
| Global defaults | Enabled/auto-enabled, Unicode glyphs, Fast off, image generation off, patch rendering not deferred. |
| Optional capabilities | `codexRequestExtensions:true`, `applyPatch:true`, `webSearch:true`, `endpoint_config:[]`. |

Astra repeats the parent fields explicitly because its bundled defaults can
override inherited values even with `extends`. The request/capability gates
are independent of Lite format, transport, and compaction. An empty
`endpoint_config` adds no endpoint routing or invented capability policy.
Pi's provider API and base URL own routing; deprecated `responses.endpoint`
overrides are removed.

Pi's native `read` handles local images. Retired `viewImageWorkspaceOnly` and
model `tools.viewImage` settings are absent, as is `directImageApiFallback`
(including its former `false` value). Profiles select standalone image
generation rather than the removed hosted-image path, but the global switch
disables generation. The retained image defaults are `.pi/openai-codex-images`
and `gpt-image-2`; they do not enable it. Unary compaction is not selected.

While `apply_patch` is active, Codex tools hides `edit`/`write` declarations
through Pi's loadout API without disabling the tools or overriding explicit
user exclusions. It preserves codemode. `/fast` changes session state, not
the configured default; children follow the main session's selection. The
profiles specify priority service with a `2` cost multiplier when Fast is used.
Historical opaque checkpoints remain protected; unknown custom-profile hashes
fail closed instead of silently converting history to text.

These are adopted configuration contracts, not proof of live endpoint support.

## Notifications by machine profile

`graphical = true` selects the local plugin; `false` selects Telegram. This
happens at apply time, independent of `niri`, `DISPLAY`, or whether the current
session is SSH. Change the machine role deliberately with `chezmoi edit-config`;
`graphical` also controls other desktop targets.

### Set up the graphical source link

Each machine owns links under `~/.local/share/pi/extensions/` to trusted source
checkouts. Settings name individual packages through those stable paths; Pi
does not automatically scan this directory. Neither links nor plugin source
belong to chezmoi.

Create the link once, replacing the placeholder with the absolute path inside
your `omp` checkout:

```sh
mkdir -p -- "$HOME/.local/share/pi/extensions"
ln -sT -- /absolute/path/to/omp/pi-extensions/pi-local-notify \
  "$HOME/.local/share/pi/extensions/pi-local-notify"
```

Inspect an existing entry before replacing it. If a checkout moves, update
only its machine-local link. This plugin is private/local-only: do not install
it from npm or copy it into this repository. A missing or dangling link does
not fall back to Telegram.

Local notifications use Kitty OSC 99 in an interactive TUI. Other terminals
and non-interactive modes do not notify. Managed tmux enables
`allow-passthrough on`, which passes notifications only from visible panes.
The plugin reports settled runs, not blocking questionnaires or approvals as
Telegram can. Manually run `/local-notify-test` in Kitty to test delivery and
click-to-focus; this sends a real notification, unlike the offline checks.

Telegram 1.0.0 sends automatic notifications only for user runs, not
extension-triggered `custom` runs or aborted runs. Notifications include the
absolute working directory and an answer, error, prompt, or dialog-title
summary; truncation does not redact sensitive content.

### Switch an existing machine

Privately back up, review, and apply only `settings.json` using the commands
above. For headless mode, also follow
[Telegram credential rendering](pi-authentication.md#render-headless-telegram-credentials)
for its explicit target after unlocking `rbw`; never display that file's diff.
Restart Pi or `/reload` once existing child work no longer needs preserving.

Graphical profiles ignore Telegram's configuration directory, so the apply
does not retrieve its secrets. Existing config and packages remain, not
deleted. Removing the declaration stops loading Telegram after reload/restart,
but separately configured project or CLI extensions can still load it.

## pnpm build approvals

Pi installs user npm packages under `~/.config/pi/agent/npm`. The only managed
file there is `pnpm-workspace.yaml`: its modifier preserves unrelated workspace
settings/approvals and replaces selectors for three packages with these exact
reviewed versions:

- `@google/genai@2.21.0`
- `esbuild@0.28.2`
- `protobufjs@7.6.6`

This neither allows all builds nor disables checking. Other versions need a
new review; it does not approve project-local or temporary Pi installations.
See pnpm's [build-policy reference](https://pnpm.io/settings/build#allowbuilds).

Privately back up the existing policy, then review and apply only this
non-secret target:

```sh
chezmoi diff --skip-secrets --exclude=encrypted \
  ~/.config/pi/agent/npm/pnpm-workspace.yaml
chezmoi apply --exclude=scripts,encrypted \
  ~/.config/pi/agent/npm/pnpm-workspace.yaml
```

The modifier accepts one YAML mapping without document markers. It rejects
malformed or ambiguous input instead of discarding it. Apply does not install
packages or run their scripts; later installs read the approvals. If an
earlier install skipped builds, review the installed versions before an
explicit rebuild:

```sh
pnpm --dir ~/.config/pi/agent/npm rebuild @google/genai esbuild protobufjs
```

This executes dependency code. It is not an apply hook or offline check.
Tests cover policy merging, idempotence, invalid input, the managed-file
exception, and pnpm 12 reading a fixture policy—not real builds or Pi startup.

## Pi package layout migration

Use this when adopting the hoisted layout on an existing install. Privately
back up `settings.json` and the entire `~/.config/pi/agent/npm/` outside chezmoi
before starting. Do not discard or regenerate the machine-local lockfile.

1. Review and apply only `settings.json` as shown above.
2. Rebuild from the existing lockfile without changing versions or executing
   lifecycle scripts:

   ```sh
   cd ~/.config/pi/agent/npm
   pnpm --config.node-linker=hoisted install --offline --frozen-lockfile --ignore-scripts
   ```

   If `settings.autoInstallPeers` in `pnpm-lock.yaml` is `false`, append
   `--config.auto-install-peers=false`. A frozen install must match that setting;
   do not regenerate the lockfile to bypass a mismatch.
3. Offline install requires every locked package in the local store. If one
   is missing, keep the backup and deliberately retry without `--offline`
   only when registry access is authorized.
4. Restart Pi. On `openai/gpt-6.1-sol`, run `/codex-minimal-tools:doctor`:
   the model profile should not be `(none)`, and the provider shim and
   `apply_patch` should be active.

pnpm rebuilds the isolated layout and removes stale top-level packages. Deleting
only old Codex siblings is not a fix: jiti still cannot resolve replacements
through an isolated layout. The bundle already supplies GPT-6.1 Sol's profile;
adding it to user `models.json` is not the repair. Installation data, lockfiles,
and backups remain local and ignored. Separate
[build approvals](#pnpm-build-approvals) govern any later lifecycle rebuild.

For child-runtime factory errors rather than package imports, use
[host-version troubleshooting](pi-agents.md#createcodemodeextension-is-not-a-function).

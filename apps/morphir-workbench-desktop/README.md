# Morphir Workbench desktop

A Proton 0.3.4 native host for the shared
[MoonBit/Rabbita workbench](../morphir-workbench/README.md). Its own `moon.work`
keeps CEF acquisition out of the portable repository's default checks. The
frontend build copies the browser app and worker into `frontend/dist`; no UI is
forked for desktop.

## Develop

Install the repository's pinned MoonBit and Node toolchains, then:

```sh
moon install moonbit-community/proton_cli@0.3.4
cd apps/morphir-workbench-desktop
moon update
proton_cli cef setup
proton_cli dev
```

The CLI starts the shared browser build and development server before launching
the native window. `proton_cli build -- --release` compiles the host.

## Package

```sh
proton_cli package --dry-run
proton_cli package --release
```

This creates local unsigned artifacts under `_build/package`; it does not
publish a release. CLI, framework and CEF helper versions must match. Supported
Proton source-built platforms are macOS Apple Silicon, Linux x64 and Windows
x64. This slice's actual desktop verification is on macOS Apple Silicon.

The packaged frontend uses Proton's secure application asset origin. Compilation
and explicitly selected Local Scheme evaluation use the shared browser workers.
Typed invocation uses native-owned child workers on macOS Apple Silicon. Its
page-bound native protocol uses one typed Proton command, restricted to the bundled main window. Every command
checks Proton's native origin/page context; navigation revokes the binding and
window shutdown closes it. The UI labels this mode **Desktop local**.

The bundled host and renderer use `morphir/workbench/native` `0.2.0-draft.2` through
`app:workbench_native`. Each invocation carries complete raw JSON request and
reply text. Production codecs bound the full UTF-8 envelope, reject duplicate
members and validate closed operation payloads. Session open/check returns a
public descriptor with the actual service's stable executions offer directly
nested. Its closed `capabilityChecks` offer identifies the exact bounded Scheme
evaluator and the supported checking policies. Replies correlate to the exact
originating invocation and operation. The frozen `0.2.0-draft.1` mapping remains
strict and does not accept checking-policy fields.

Typed functions default to **Whole model before running**. A qualified native
session also offers **As code executes**, which permits represented unsupported
code to remain dormant and reports `execution.unsupported_reached` if reached.
Both policies retain whole-source integrity, resource and identity checks and the
complete selected input/output type closure. This changes validation timing; it
does not add evaluator features or perform tree shaking.

The renderer captures source, entry, JSON/Ion arguments and policy before any
await. The owner captures its provider, rich snapshot, selected boundary and
policy once; its isolated child reconstructs that selection and echoes the
accepted plan. Both host and client validate typed terminal outcomes against the
captured boundary. UI edits, reconnection and cancellation cannot replace the
accepted selection. A mismatched or replayed accepted plan is an uncertain
submission, never an automatic retry. Native reply size is reserved before owner
acceptance, so a prepublication rejection creates no execution.

The renderer retains one current accepted plan and at most 256 accepted identity
and plan-id pairs per page. It refuses another submission before a host effect
when that observation budget is full; reopen the application page to start a
fresh session. Release frees execution evidence but retains replay protection.

Errors carry explicit `none` or `unknown` effects, with fixed public messages.
Caller/frame rejection proves no effect. The shared execution owner's returned
pre-commit rejection also proves no effect. Once that owner accepts a command,
worker scheduling or publication failure is unknown. Workspace errors after
entry to the stateful service are conservatively unknown. Closing revokes the
session before waiting for children, so failed shutdown also remains unknown.
No status code is invented for native errors. Executable paths, internal
claim/complete operations and environment overrides are not renderer input.

Each native child runs this same packaged executable with `--morphir-native-worker`
and exits without starting CEF. Frames are length-prefixed UTF-8 JSON, limited to
1 MiB. Stderr is capped at 64 KiB. The host observes resident memory every 20 ms
against a 256 MiB budget and enforces a 30-second deadline. Sampling can overshoot
between observations; it is not an allocation cap. At most two workers execute,
with eight retained executions and 16 MiB retained evidence through the shared owner.
Terminal publication follows confirmed child exit. Reload stops old workers before
a new page can claim work, and shutdown waits for owned children. Returned values
survive late cancellation; cleanup failures remain separate evidence.

Linux has separate CEF-free native process acceptance. Linux and Windows retain
browser workers pending independent packaged GUI/lifecycle qualification.
The policy mapping is scoped to the independently checked boundary/client/owner
MCK drafts 20, 21 and 22. Controlled fixtures remain distinct from actual worker,
OS picker and packaged GUI evidence. The policy-aware HTTP mapping has separate
qualification; native negotiation never upgrades a connected host. No additional platform
is enabled by this mapping.

On macOS Apple Silicon, the `workspace` capability enables **Open workspace** in
the explorer. The native OS picker grants one read-only root per page session.
Only opaque project and transfer identities cross the page-bound native command bridge.
The shared engine discovers canonical and legacy configuration and saved model
checkpoints. JSON versions 1–4, Ion text and Ion binary are decoded by the compiled
pipeline. Binary Ion markers also identify `.ion` and `.10n` files. Original-file
downloads preserve bytes; the current-IR export is a separate action. Exports
from the trusted main page use the native save dialog. The host permits only
Blob URLs matching that page and its configured bundled or connected origin;
network URLs and renderer-supplied destination paths are denied. This save flow
is separate from the read-only workspace grant interface.

Folder cancellation preserves the displayed model and project list. Reads reject
traversal, symlinks, hard links, special files and observed replacement races.
Limits are 4,096 entries, 256 directories, depth 16, 128 project/model entries,
256 KiB per configuration file, 2 MiB aggregate configuration, 512 KiB offers and
16 MiB model captures. Captures transfer in 192 KiB chunks and are released before
inspection. Revocation, navigation and shutdown close grants. The observation is
bounded, not an atomic filesystem snapshot; mount latency remains external.
Compilation, scripts, writes, watches and persistent grants are not offered.

`mise run test:workbench-native-workspaces` runs real filesystem and concurrent
replacement acceptance without CEF. macOS packaged qualification additionally
uses the real OS picker, cancellation, JSON/Ion inspection, byte-exact original
export Blobs and the shared browser/native regression flows. Linux has CEF-free
filesystem acceptance; Linux and Windows do not advertise packaged workspace
grants until their GUI/lifecycle qualification is complete.
`?mode=standalone` keeps the browser worker path without negotiating this session.
Development HTTP entries also retain the worker path; they receive no native
command grant. The framework, contract package, CLI and helpers remain pinned
to Proton 0.3.4.

Run `mise run test:workbench-native-session` from the repository root to test
session validation/revocation without CEF. The dependency-free model lives in
`pkgs/morphir-workbench-native-session`; the normal portable CI test matrix
covers it on all four targets without loading the desktop module's prebuild.

To attach the packaged
window to the same-origin authenticated gateway, set
`MORPHIR_WORKBENCH_LAUNCH_URL` to its one-use
`http://127.0.0.1:PORT/launch?token=TOKEN` URL before launching the executable.
The native host accepts only that explicit loopback launch shape and retains
the normal asset origin when the variable is absent. The gateway exchanges the
token for the upstream HttpOnly cookie. Do not put the token in logs or saved
configuration. Enable `MORPHIR_WORKBENCH_EXECUTIONS=1` on the gateway for typed evaluation;
see the [execution setup and acceptance](../morphir-workbench/README.md#authenticated-evaluation-executions).
This HTTP attachment does not introduce native daemon IPC.
An explicit connected launch registers no native commands.

For a headless packaged-app smoke check, enable Proton's CDP port using
`PROTON_REMOTE_DEBUGGING_PORT` and `PROTON_HEADLESS=1`, then run the browser
package's `scripts/desktop-test.ts <cdp-url>`. Keep that debugging port confined
to local development.

The opt-in lifecycle acceptance launches its own unmodified package with an
ephemeral CDP port and verifies Proton's separate temporary CEF profile. From
the repository root, after packaging:

```sh
bun --check apps/morphir-workbench/scripts/desktop-lifecycle-test.ts \
  "apps/morphir-workbench-desktop/_build/package/Morphir Workbench.app" \
  .dev/campaign-completion/lifecycle-agent
```

This currently qualifies macOS Apple Silicon. It evaluates a typed function,
then holds actual owner-spawned native workers with `SIGSTOP` after checking
their executable, direct parent and OS process identity. A bounded list argument
keeps worker observation deterministic. It verifies worker removal at the
replacement session's reply after reload, at the `session.close` reply, and at
normal application exit. Replacement sessions reject the old authority and
execute another typed function successfully.

Before launching the package, the acceptance uses `clang` to build a temporary
owned-child fixture. It verifies that an exited but unreaped macOS process still
counts as present when `ps` changes its command to `<defunct>`. Only PID and birth
time determine continued presence after the initial executable/parent check.
Run just this regression, without launching CEF, with:

```sh
bun --check apps/morphir-workbench/scripts/desktop-lifecycle-test.ts \
  --process-identity-regression .dev/campaign-completion/lifecycle-agent/regression
```

Normal quit uses macOS AppKit's `NSRunningApplication.terminate()` for the owned
PID. That API requests normal application quit; it is not a Unix signal or a
simulated menu click. Successful qualification requires exit code zero with no
signal and OS confirmation that the owned native workers have exited. Emergency
signal cleanup on a failed test does not count as qualification. The JSON
receipt and package log remain in the evidence directory. This acceptance
neither uses a worker executable substitute nor qualifies Linux or Windows
packaged lifecycle behavior.

Run `mise run test:workbench-native-workers` from the repository root for real
native process, exact-value, cancellation, framing, memory and shutdown acceptance
without CEF. The native service is in `pkgs/morphir-workbench-native`.

The `bridge` package owns the same session/service state used by Proton. The
native worker acceptance task also runs `bridge-acceptance` without CEF, covering
all 13 wire operations, actual child evaluation, stable service authority,
read-only capture retirement and late picker rejection after a replacement page.
This is implementation acceptance, not an independent MCK qualification or a
packaged GUI result. The shared renderer tests use the actual compiled reply
validation and receipt cursor, including raw duplicates and transport uncertainty.

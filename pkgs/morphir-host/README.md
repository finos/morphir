# Morphir hosts

`finos/morphir-host` supplies input, configuration, cancellation and publication capabilities around the portable Morphir engine. The engine has no dependency on this module.

## Embedding

Construct a `Mount` with `kind`, `read` and shallow `list` callbacks. Paths are relative to the mount. Entry kinds are 0 missing, 1 regular file, 2 directory, 3 symlink and 4 unsupported special file. Directory listings contain immediate child names.

`Host::new` accepts a mount, optional publisher, explicit environment, system/global configuration documents, cancellation callback, event callback and resource limits. `Mount::memory` copies its input map. `Publisher::memory` commits artifacts to a supplied output map.

Hosts can also supply an optional `toolchain` provider and use
`Host::toolchain_request` to compile or execute through its explicit capabilities.
See [acquired tooling](toolchain/README.md) and [embedded tooling](embedding/README.md)
for process and in-memory providers. Tooling calls emit a host phase event and
check cancellation before and after the provider call; providers enforce their
own operation limits and lifecycle. No tooling is acquired implicitly.

The invocation sequence is:

1. `Host::snapshot()` captures directory inventory, manifests and Scheme configuration.
2. `workspace.discover(snapshot.tree, ...)` resolves configuration and member metadata.
3. `Engine::plan(snapshot.engine_host(), workspace, request, cancelled=host.cancelled)` validates selection and scripts and freezes source paths and destinations.
4. `Host::run(engine, plan)` snapshots selected contents, runs the pipeline, stages artifacts and publishes each task destination.

Hosts can prepare snapshots and consume returned artifacts asynchronously in their own environment. Core execution is synchronous. Long-running Scheme evaluation checks cancellation at each evaluator step; asynchronous applications must arrange a callback whose state can change while their runner executes. Frontend/backend callbacks must provide their own internal cancellation if needed.

Hosts that provide native runtime behavior pass `bind_runtime` when planning. The
engine calls it once per project session before evaluating configuration scripts.
This keeps host capabilities explicit and available to `ir-eval` in those scripts.

The existing `morphir-engine.Host` and `Engine::run` APIs remain available for callers that only need artifacts. No filesystem, process or network access is implicitly available to Scheme.

### Typed content and bytes

`Host::run_content(engine, plan, publisher, read_bytes=Some(reader))` snapshots
text or raw bytes according to the plan and returns `ContentResult`. Its artifacts
carry `data.Content::Text` or `Binary`, plus their selected format. Supply
`ContentPublisher::memory` for typed in-memory outputs or
`ContentPublisher::filesystem` for files. `Mount::filesystem_bytes(root)` supplies
a confined raw-byte reader alongside the existing text mount.

`ContentPublisher.write_bytes` advertises binary support. Missing byte readers
or publishers fail capability checks before source reads or staging. The
`ContentPublisher::text` adapter retains existing publisher callbacks and rejects
binary output. `Host::run` uses that adapter, so existing text callers and readable
Ion checkpoints share the typed execution and publication lifecycle. Byte
snapshots remain bytes throughout execution and staging.

### Scoped metadata sessions

Before planning, an embedding can call
`host.register_project_metadata_provider(engine, acquire)`. The binder freezes
project scope without acquiring resources. The `acquire(scope)` callback runs on
the first restoration or context request during `Host::run_content`, returning a
`MetadataSession` with explicit capabilities and a disposal callback. Context
callbacks receive the resource reference and its document base, unchanged.

The host keeps a distinct session for each bound project and reuses it only
within that execution. It disposes all acquired sessions in reverse order before
library validation or publication, including after generation failure or
cancellation. A failed cleanup prevents publication and retains failed callbacks.
Further execution refuses until an explicit `host.dispose_metadata_sessions()`
retry succeeds. Original generation diagnostics remain available alongside the
cleanup error.

Acquisition callbacks must clean up partial resources if they raise before
returning a session. They own grants, authentication and bounded transport. This
lifecycle adapter does not itself implement signature verification, a process
restore command, runtime qualification or installed CLI integration. Capability calls outside the owning host's active execution are refused; explicit static
engine capabilities remain supported independently.

## Runtime adapters

| Target | Adapter |
| --- | --- |
| Native | OS arguments/environment, filesystem and stderr/exit |
| JavaScript | Node filesystem adapter; memory embedding does not require filesystem access |
| WASM | WASI Preview 1; the development root is preopened directory fd 3 |
| WASM-GC | `morphir_host_v1` imports supplied by the embedding application |

Run WASM artifacts with `node pkgs/morphir-host/runners/wasm.mjs <artifact.wasm> [arguments]`. The runner preopens the current directory for WASI. Other WASI runners can supply equivalent arguments, environment and preopens. There are no Moonrun-specific imports in the WASI CLI.

WASM-GC exchanges JSON responses through opaque UTF-16 string handles. Imports are `begin`, `append`, `length`, `at` and `request`; `request` takes operation and two string arguments and returns `{value: ...}` or `{error: ...}`. The supplied runner implements filesystem operations, arguments, environment, platform identity, stderr and exit. Console output uses `spectest.print_char`. MoonBit core also declares `__moonbit_sys_unstable.exit(code)`, which the CLI does not call; a host must still supply it, and the supplied runner exits the process. These imports are an explicit embedding contract, not WASI.

Diagnostic logging additionally requires `utc_milliseconds`, with both string arguments empty.
Return a whole numeric count of milliseconds since the Unix epoch, for example
`{"value":1793318400000}`. The diagnostic timestamp range is 0 through 253402300799999,
ending at `9999-12-31T23:59:59.999Z`. The supplied Node runner uses `Date.now()`; the
portable logger advances that initial UTC value with the existing `monotonic_seconds`
operation. Missing clocks report `diagnostics.utc_clock_unavailable`; invalid values
report `diagnostics.invalid_utc_clock`. The CLI exits 2 before starting the command,
using its existing JSON failure when selected. Help and `--log-level off` do not
request a clock. Text diagnostics go only to stderr; rolling-file diagnostics require
the native or JS process host and are explicitly refused here. No MEP or worker
message fields are added by these host capabilities.

For `--cancel-file`, the GC entry calls `register_cancel_file` before starting
the host. The first argument is its prepared absolute path and the second is
empty. Return `{"value":true}` after accepting it. Passing an empty first
argument clears the registration and is idempotent. A host that lacks this
capability refuses before the command starts with
`cancellation.cancel_file_registration_unavailable` and exit 2.
The prepared path uses forward slashes on Windows too; compare file identities
with the platform's path rules rather than raw separator spelling.

The supplied runner polls the path in the existing bounded stdin wait, retaining
an observed request in its existing interrupt flag before returning to MoonBit.
Ordinary file reads and startup signal probes do not poll that path. Commands
retain their existing cancel-file checkpoints and JSON outcomes, including
evaluation's per-call cancellation result for a marker present before launch.
Removing a marker observed during a stdin wait cannot undo that request.
Registration cleanup runs after normal completion, cancellation and early
startup failure. A failed clear emits
`cancellation.cancel_file_cleanup_failed` on stderr; it changes an otherwise
successful exit to 1 and keeps an existing failure/cancellation code. It does
not add another stdout document. Existing worker messages and shared buffers
are unchanged.

Optional WASM-GC operations `bytes_supported`, `read_bytes` and `write_bytes`
extend this interface. `bytes_supported` returns true when both byte operations
are implemented; missing operations mean unsupported. `read_bytes(path)` returns
a JSON array of integers 0 through 255. `write_bytes(path, payload)` receives that
array encoded as JSON in the second argument. The supplied runner implements
them. Older embedding hosts continue to support text pipelines without adding
imports. These JSON arrays are a byte transport for the embedding ABI, independent
of the engine's selected data codec.

Desktop hosts resolve system/global configuration using Moon-Lander conventions for the platform config directory and Morphir home rules. Each location accepts JSON/JSON5, YAML/YML and TOML layers in that order. WASI only accesses its preopen. Its CLI accepts optional `.morphir-host/system/morphir.{json,json5,yaml,yml,toml}` and `.morphir-host/user/morphir.{json,json5,yaml,yml,toml}` within that preopen. Library callers can supply separate read-only configuration documents directly. The discovery protocol uses the same format loader without changing its request or response fields. CLI `--discovery-boundary` bounds the ancestor walk; `--isolated` skips machine/global sources and user overrides while retaining active profiles and project primaries.

## Publication and limits

`Publisher.guarantee` declares atomic task publication, recoverable task replacement or host-managed semantics. Events distinguish phases, diagnostics and committed destinations.

Configuration or transformation failures publish nothing. Successful transformations are staged before any destination is replaced. A task owns its `compile.dest` directory, including removal of its stale artifacts on the next successful publication.

Filesystem publishers acquire `.morphir-publish.lock` under the output root with exclusive directory creation. They move an existing task directory to a backup, then move its staged replacement into place. This provides recoverable task replacement, with a brief interval when the destination is absent. It does not provide atomic replacement across tasks. Reports list the destinations that actually committed.

Normal completion/failure removes only the invocation's staging and backup data. If restoring a backup fails, the publisher preserves the lock and backup and reports their location. A lock left by a crashed process requires inspection and explicit recovery; another invocation never removes it automatically.

Default limits are 10,000 entries, depth 64 and 64 MiB per configuration/source/artifact phase. Filesystem adapters limit each text or byte read to 16 MiB. Source contents are snapshots, not a streaming interface. Files changing during snapshot preparation can yield contents from different moments. Checkpoint codecs enforce their own byte/traversal budgets in addition to host limits.

Filesystem mounts reject symlinks and special files and check path components before each operation. They assume the granted filesystem is not being maliciously changed concurrently. These adapters are not OS sandboxes. WASI preopens provide an additional runtime confinement boundary. Memory and remote adapters can materialize confined symlinks before supplying a snapshot.

Generated libraries with `Required(target)` pass through a `LibraryBuildProvider`.
A provider declares the library contracts it can build and acquires a fresh lease
with `build` and `dispose` callbacks. Embedded package compilation does not imply
this capability. The host hashes the exact source/member snapshot with SHA-256,
checks the fresh lease and project/target/dependency evidence, and emits a binary
Ion `morphir-library-build-v1` receipt. All required builds and lease disposal must
succeed before publication begins. Cancellation is checked before and after
provider calls. Providers must bound their own running processes and deadlines.

The explicit process adapter invokes a supplied Node helper, compiler/core home
and supplied dependency directories. It creates a host-owned temporary lease;
the helper materializes a private workspace, verifies pinned compiler/core and
SDK identities, builds with `--frozen`, and verifies source identities again.
Dependency source trees exclude `_build`, `.mooncakes`, `.git` and `node_modules`.
Core identities include bundled compiler inputs and confined file symlinks.
This identity profile records content, not timestamps. Supply an installation
whose matching core is already bundled; a build that changes its inputs fails.
The helper uses no installation, update, registry acquisition or fallback build.
Cleanup covers the entire lease, including workspaces left by failed processes.

`process_execution` additionally probes separate compile/run capabilities before
acquiring a session. It supports JS, a hashed Wasm GC runner, native C on POSIX,
and a separately pinned LLVM compiler/core on the verified macOS arm64 host.
Native receipts identify C compiler, linker, runtime objects and linked libraries;
invocation rechecks platform/architecture, executable and runtime identities.
Wasm imports are restricted to the driver's versioned byte/clock/context ABI.
Toolchain pins and dependency preparation are explicit, with no auto-acquisition.
The helper's JSON control transport is an explicit projection; semantic suites
and outcomes remain binary Ion. See the [CLI configuration](../../apps/morphir/README.md).

### Execution verification and publication

`verify_and_publish(plans, provider, evaluator, publisher, destination)` verifies
all distinct required targets and disposes their leases before opening a publisher
transaction. Sources and `verification.ionb` share the task destination. An invalid
or partial matrix, mismatch, execution failure, or cleanup failure preserves the
previous output. The filesystem publisher applies the recovery rules above when
staging or replacement fails. `VerificationResult.committed` records whether the
replacement happened; `successful()` also requires publication cleanup to succeed.
Plain CLI `execute` and `verify` return reports without replacing generated output.

Process helpers enforce input, output and diagnostic limits and recheck retained
source/dependency identities. Cancellation uses an explicit `--cancel-file` marker
or process signals. POSIX supervision owns a process group, stops its descendants
on deadline/cancellation, reclaims remaining group members at parent exit, and
awaits the absence of live group members before returning. Orphan zombies have
no executing code or open files and may await the OS reaper. If termination cannot
be confirmed, the outer host process times out, or a helper exits abruptly with a
signal-derived status, disposal reports a typed cleanup error and retains the
scratch directory for inspection. Statuses at or above 128 are conservatively
treated as unconfirmed termination, including an explicit exit with such a code.
Windows supervision uses a Job Object worker. The runner joins the job while
suspended, and the worker confirms no active job members remain before writing
its completion receipt. Closing the worker kills job members; a missing receipt
retains private state for recovery. Linux, macOS and Windows CI exercise real
process-tree lifecycle faults. Windows support currently covers Node hosts with
JS and Wasm GC targets. Neither adapter is an OS sandbox for a process that
escapes its assigned containment.

### Telemetry shutdown

`TelemetrySession` retains at most 2,048 observations and 128 metric descriptor
series. Metric aggregation precedes trace retention and queue limits. Construct
with `record_traces=false` to retain metrics without local trace rows; this does
not change propagated W3C sampling flags. Dropped delivery remains in `metrics()`.

Call `flush()` after execution and outside publication locks for a bounded local
file drain. `flush_to_process(node, helper, program, args, timeout=1000,
cancel_file="")` instead sends the queued observations and metrics as native Ion
on the exporter's stdin. Supply the shipped `build-provider/telemetry.mjs` worker
and an explicit exporter command. The worker supervises that asynchronous process
with a separate allowance, capped at five seconds, and a 1-KiB diagnostic budget.
Host shutdown allows another 500 ms for worker termination. The local batch write
and exporter share the flush allowance; this does not consume an execution deadline.
The batch is capped at 4 MiB. Export failure, cancellation and timeout account for
all undelivered queued observations, clear the queue, and use direct stderr health
messages. Repeated shutdown performs no second export. IDs, timestamps and semantic
results are unchanged by drain. This host operation is available on desktop adapters;
it is not an OpenTelemetry adapter or collector integration.

`NativeTelemetry` is an explicit host capability for the separately built
[OpenTelemetry adapter](../../apps/morphir-otel/README.md). The constructor checks
host, binary identity, accepted archive receipt, transport and allowance before
execution. Flush ships a native Ion batch through the packaged process helper,
which rechecks binary identity and clears inherited `OTEL_*` configuration. The
portable engine and generated drivers retain their existing observation contract.

Local sinks accept `@stderr` only with `text` or `json-lines`; the host drains
through its bounded file worker without adding log records to result stdout.

### Explicit process metadata authority

`host.register_process_metadata_provider(engine, grants, workspaceRoot,
invocationRoot)` composes the scoped session owner with the qualified one-shot
service. Parse an explicit host document through
`metadata/grants.Grants::decode`; selections from project configuration never
create grants. A missing authority refuses only when metadata is actually used,
so planning and unused providers acquire no resources.

The owning host retains the same metadata-session owner through planning and
`run_content`. Node/service executable pins and the fixed helper bundle are
checked before and after each exchange. Original frames and policy/lock bytes
remain bounded snapshots. Context capabilities resolve from the retained graph
only. Cleanup failures retain callbacks for explicit retry and block publication.
Telemetry uses the existing observer, with fixed lifecycle codes and independent
project/operation correlation, excluding raw provider and trust bodies.

See the [CLI grant format](../../apps/morphir/README.md#authenticated-metadata-provider)
and the [binary envelope](metadata/README.md). Qualified JS/native process hosts
are distinct from the pure four-target wire package. The shared portable MVP
assumptions remain in force; hardened assurance is unavailable.

### Metadata invocation audit records

Pass `audit_sink=logs.metadata_audit_sink()` alongside the ordinary observer when
registering the process provider. The CLI wires both when logging is enabled.
The existing destination and bounded flush worker carry separate
`morphir-metadata-invocation-v1` records, annotated
`morphir_metadata_invocation_v1` in Ion. Binary Ion remains the default beneath
`.morphir/logs/frontend.ionb`; explicit paths and formats keep their meaning.

Each record identifies the run, operation and project, phase, outcome and
duration. Evidence distinguishes the granted service digest from verification,
and the requested portable MVP profile from a successful capability probe.
The native revision appears only after snapshot validation. Declaration validation
is a separate pure-consumer notification; it does not mean generation or
publication succeeded. Cleanup records follow the existing disposal gate.

Audit records contain no provider/context payloads or policy/lock bodies. They
never grant authority, enter semantic naming receipts, or add metric dimensions.
Retention is bounded to 256 audit records and 2048 total retained records per
session. Sink failures and dropped records cannot change provider decisions.
Logging off writes no invocation receipt. Consumers of mixed telemetry streams
should dispatch by profile, rather than assuming every record is an observation.

This slice qualifies local audit sinks. An external exporter must explicitly
support the new record profile. The native OpenTelemetry adapter's existing
observation/metric qualification does not qualify metadata audit export.

### Cooperative interruption adapters

A process owner can install `platform.InterruptionScope` with a probe of its
run's cancellation state. `interruption_requested` then consults that probe;
closing the scope restores the enclosing probe and repeated close does nothing.
Install scopes for one process owner and close nested scopes in reverse order.
Legacy standalone callers keep their existing interruption APIs.

Native shallow listings, including configuration discovery, use the existing
single-pass bounded reader. A listing permits at most 65536 entries, at most
4096 UTF-16 units per name and at most 1 MiB of UTF-16 name units in total.
Concurrent entry creation or removal cannot leave uninitialized result slots;
the listing remains an observation, rather than an atomic directory snapshot.
This avoids the two-traversal race reported in
[moonbitlang/x#357](https://github.com/moonbitlang/x/issues/357).
Oversized directories fail with `directory.entry_limit` or
`directory.name_limit`. Native CLI qualification changes an ancestor's entries
while running 100 real discovery commands and checks their JSON results.
The ordinary `list` API retains its non-interruptible behavior, so finalizers
can enumerate owned scratch after cancellation. `list_bounded` continues to
poll the owning interruption probe. Neither operation clears a retained stop.

Native process waits and bounded directory enumeration call the same probe at
safe points through a C function pointer. POSIX stdin polls at 10 ms intervals,
so a cancel file can end an otherwise idle read. A child gets SIGINT once; after
five seconds without completion the adapter escalates to terminate and kill,
then reaps it. These adapters install no additional signal handler while a run
owns the scope. The owning host selects the final signal reason and exit code.

The terminal launcher selects a worker from the leading Morphir command after
its declared global controls. It never examines an opaque child argument tail.
The parent owns signal delivery while synchronous worker code runs: the existing
shared flag distinguishes interrupt and terminate, and a second signal exits
immediately with that signal's status. Stdin remains a bounded request/reply
channel. Command results and wire payloads retain their existing shapes.

The Node synchronous process adapter keeps its child on an owned worker, while
the calling command polls the run's cooperative probe. This lets signals and
cancel files reach a child while the command waits, without changing child argv
or the existing `{exitCode, stdout, stderr}` result. Successful completion waits
for the child's streams to close. Captured stdout and stderr retain their
16 MiB limits; timeout remains exit 124 and spawn failure remains -1. The worker
escalates an unacknowledged cancellation and confirms close before returning.
A bridge that cannot confirm cleanup returns failure.

`platform.ProcessScope` connects owned process launches to a run's logger.
Native/JS platform calls announce their program, and local JS supervision
adapters can use `process_started` without adding protocol fields. A diagnostic
observer cannot alter the child argument array or its successful output.

Configuration directory listings retain inaccessible entries as the framework's
`Inaccessible` kind. A locked sibling, such as a Windows drive-root system file,
does not prevent discovery. If that entry is an actual configuration candidate,
the loader requests its contents and the regular-file read boundary reports the
failure; the candidate is never silently treated as absent.

`platform.CooperativeProcessScope` lets a protocol helper that already receives
the cancel file finish its own child cleanup. The process adapter still polls
the run's single stop state. When the file is visible to the helper, it retains
the existing five-second grace before escalation instead of killing the helper
before it can confirm cleanup. Signal delivery without that cooperative scope
keeps its existing behavior. Closing a scope restores the enclosing policy.

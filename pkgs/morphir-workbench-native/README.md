# Native Workbench workers

The native host owns the existing Workbench execution owner and starts its own packaged
executable in worker mode. Renderer input cannot select executable paths, arguments
or environment variables. Only typed evaluation runs in the child.

Each child receives one big-endian 32-bit length-prefixed UTF-8 JSON request and
returns one frame of terminal evidence. Both frames are limited to 1 MiB. Stderr
is drained with a 64 KiB limit. The host observes resident memory every 20 ms,
cancels a worker above 256 MiB or after 30 seconds, and waits for exit before
publishing terminal evidence. Resident-memory sampling is an observed process
budget, with possible overshoot between samples, rather than an allocation cap.

At most two workers execute concurrently. The shared owner retains its eight-execution,
16 MiB evidence limits and admits each execution claim once. Returned outcomes
survive late cancellation; cleanup failures remain separate evidence. Failure to
confirm exit keeps the execution nonterminal and prevents further execution claims.

The native service has macOS and Linux process acceptance. Packaged Proton execution
discovery is enabled on macOS Apple Silicon. Linux and Windows retain browser
workers until their packaged GUI/lifecycle lanes are independently qualified.
The bundled host/renderer pair uses the accepted native `0.2.0-draft.1` wire mapping.
Public conformance advertisement still waits for fresh packaged target
qualification. Independent wire, reply, client and controlled owner MCK evidence
does not establish a platform's packaged lifecycle behavior.

`bridge.Owner` composes the actual execution and workspace services with the portable
session and raw request/reply codecs. Only trusted host callbacks supply caller
context, the executable and picker results. It revalidates page/session authority
after awaited cleanup and selection. Native errors use explicit stage-based
effects and fixed messages; workspace owner failures are conservatively unknown.
The internal `request` helpers remain for existing CEF-free service acceptance;
they are not the renderer transport. Terminal budgets include the complete native
reply wrapper, and a workspace grant is validated before replacing the old one.

`Owner::with_services` accepts typed trusted execution/workspace factories. Their
presence enables the capability; construction and predecessor cleanup must
succeed before an offer is published. `Owner::new` preserves the production
native services. `workspace.RootAccess` supplies host IO while the production
workspace service retains discovery, picker generations, immutable captures,
offset checks and sequence retirement.

## Controlled owner qualification

Exact offline MCK draft.18 drives production `bridge.Owner`, portable session
policy, `workspace.Service` and the production `executions.Host`. The shared Rust MCK
owns the corpus, verdicts and independent saved-report checks. The native adapter
only drives requests and records observations. It receives no expectations or
case IDs.

```sh
MORPHIR_MCK_BIN=/path/to/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.18 \
mise run test:workbench-native-owner-mck
```

The task checks debug/release reports, portable session/execution tests on all four
targets, and complete JSON/Ion fixture inputs through the production importer
and evaluator. `MORPHIR_WORKBENCH_EVIDENCE` overrides the default evidence folder
`.dev/native-owner-mck/reports`.

Context, in-memory roots, picker delivery, execution completion and shared cleanup
confirmation are controlled host inputs. Scoped opaque-identity aliases preserve
equality and freshness; unresolved fixture references remain visible failures.
Held effects advance only through explicit actions. Shutdown waiters share one
memoized cleanup result. Final teardown drains controlled resources outside the
recorded observation.

These traces qualify owner coordination. They do not establish authenticated OS
caller provenance, filesystem containment or races, actual native worker
scheduling/exit, or packaged platform conformance. Real worker, bridge, workspace
and packaged acceptance remain separate. Live native `0.2.0-draft.1` and historical MCK
drafts.1 through .9 stay unchanged.

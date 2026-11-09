# Qualify the packaged Moonx entry

This application test executes the actual launcher selected by the release
orchestrator. It does not replace the launcher or supply an unpublished
dependency. The release orchestrator must verify the candidate archives before
calling it. Public consumers use the default registry and an owned credential-free
Moon home. Actual packaged qualification remains required before release.

Run `node apps/morphir/scripts/moonx/qualification.mts --help --json` for the
command contract. `--json` writes one `morphir/command-result` version `0.1.0`
document to stdout. Success has `state: "succeeded"`, `exitCode: 0`, `diagnostics`
and `result`; failure has `state: "failed"` and `error: {code, message}` instead
of `result`. Syntax exits 2 and a failed qualification exits 1. Child diagnostics
and recovery details stay on stderr. Help starts no process or filesystem work.

The caller supplies these environment values:

| Variable, prefixed with `MORPHIR_MOONX_` | Meaning |
| --- | --- |
| `PROGRAM` | Absolute selected stock `moonrun` or `moonx` executable |
| `PREFIX_JSON` | Exact JSON argument array, either `["ABSOLUTE.wasm", "--"]` or `["finos/morphir/moonx@VERSION"]` |
| `KIND` | `archive` for the verified extracted entry, or `public` for the actual registry coordinate |
| `VERSION` | Expected shared Morphir release version |
| `COMPILER_HOME` | Selected owned stock 0.10.20+65efd5b93 home |
| `CONTROLLER` | Windows only, the test controller compiled from the adjacent fixture data |

The test checks the selected compiler, Moon and Moonrun identities. The minimum
and producer currently select the same stock release, with independent consumer
homes and caches; neither receipt claims support for older compilers. It exercises
real launcher help, application version, malformed worksheet JSON and missing
Node. Startup reports must leave application stdout empty. A separate preload
fixture, checked as TypeScript and loaded by Node from `preload.cts`, proves
empty and Unicode arguments, delimiters, reserved-looking tails,
one MiB of exact binary stdin/stdout, separate stderr bytes and retained child
status 23. This transport fixture exits before application code and is labelled
`applicationExecuted: false` in the proof.

Cancellation retains the application's existing JSON forms: an unstarted
command can return `{"successful":false,"error":"Cancelled","committed":[]}`, while a started worksheet reports
`completion.status: "cancelled"`. The proof preserves the actual document and
requires the real child status in either case.

Observation mode delegates to the real application. It records the existing
bounded stdin request, delivered Node signal and actual Node exit without
adding a signal handler. POSIX cases send SIGINT and SIGTERM to the launcher,
hold stdin open through exit, and require actual child 130/143. Windows uses a
private real console and `GenerateConsoleCtrlEvent`; it checks delivered
SIGBREAK, child 131 and full parent `0xC000013A`. A deliberately unresponsive
Node event loop separately proves bounded forced cleanup. Its application code
is withheld and its OS exit is read through a retained process handle.

Every successful process proof checks reaping and payload removal before
emergency cleanup. Failure recovery has its own deadline independent of pipe
closure; it terminates known descendants before waiting and reports any
remaining recovery failure without replacing the original error. Observation
and control records are consumed only after a complete newline.

The controller sources are fixture data, not another published module or a
production console adapter. The orchestrator copies them into an owned scratch
module with published `moonbitlang/async@0.22.7` and `moonbitlang/x@0.5.5` before
testing and building. Its private Moon home initializes its own registry index.
Cleanup traverses only real owned directories and unlinks compiler-directory
links themselves. On Windows, an access-denied unlink of a regular registry
file retries once after `attrib.exe -R` on that exact file. Cleanup failure
refuses success; during another failure it is reported separately on stderr.
The console topology code is adapted under Apache-2.0 from
[Moon-Lander commit 93dfb141](https://github.com/moonrockz/moon-lander/tree/93dfb1411e0d2873a5848cb8b86acb0723770ae0/tests/moonx-console-controller).
Changes select actual Morphir arguments, add library-owned JSON controls and
retain the real Node exit status. Preserve that provenance when changing it.

Compiler checks, Windows object compilation and probe self-tests do not count
as actual packaged or genuine Windows console qualification. The release must
retain the corresponding real host and public-consumer results.

# Native client lifecycle qualification

Exact offline Workbench MCK **`0.1.0-draft.9`** adds `run-native-client`, with
JSON transport. It exercises a production client against controlled reply
delivery for the unchanged `morphir/workbench/native` `0.1.0-draft.1` profile.
Historical MCK drafts.1 through .8 are unchanged.

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.9 \
  --adapter /path/to/client-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.9 --report report.json
```

The existing Rust runner validates fixture infrastructure, negotiates the exact
draft, sends only inputs, and compares fixed parent-owned observations. It does
not link a client, parse native reply text, or compute expected lifecycle results.
The independent checker reloads the original corpus bytes, verifies their hash,
inventory and capabilities, and recomputes verdicts. Transcript replay tests the
runner, not a production implementation. An explicit adapter must use the actual
client, receipt cursor and native response validation code.

## Controlled input

The [schemas](schemas/) define all closed shapes. Capabilities require exactly
`operations: ["run-native-client"]`, `formats: ["json"]`, `suite: "workbench"`,
and `contractVersion: "0.1.0-draft.9"`. Build-suffixed or adjacent drafts reject.
The existing bounded NDJSON session and positive safe-integer request IDs apply.
The case request carries that suite/version, the operation, `format: "json"`,
and this input:

- `evaluation` contains the complete immutable model string, entry, and inputs
  with `format: "json"` or `"ion-text"` and a source string. JSON arguments must
  be a whole, duplicate-free JSON array. Ion source remains opaque to the runner.
- `inspectionSuccess` controls the local model inspector's success result.
  The trace observes its exact request bytes and order. This controlled result
  alone does not prove a model valid; implementations must separately import
  and evaluate the concrete corpus assets through their production model reader.
- `checkSource` is the complete raw `session.check` response text.
- `invocations` contains unique ASCII IDs, a native operation other than
  `session.check`, raw response `source` or null for a lost reply, and `held`.
  Each actual call consumes the next unused invocation for its operation.
  A held reply belongs to the originating promise even after newer work starts.
- `actions` explicitly starts `initialize`, `evaluate`, `resume`, `cancel`,
  `choose`, or `open`. Each start has a unique attempt ID; `open` also has a
  project token. `deliver` names one declared held invocation and may appear
  at most once per invocation. `poll` releases one polling pause. `dispose`
  disposes the client. `set-check` replaces the raw authority-check reply.

Validly framed `session.check` calls are transparent: they use the current
`checkSource` without consuming an invocation or appearing in request counts.
This permits implementations to repeat authority checks. Changed or malformed
check replies still pass through production validation. Invalid command names or
check wrappers are recorded as unconfigured calls, so they cannot silently pass.
Delivery of a declared held call that the client has not made is observed as
`unavailable`, allowing the runner to report a compatibility mismatch.

No elapsed time determines a verdict. Each action drains promise continuations
at a task boundary. Polling and held replies advance only through explicit
fixture actions. The adapter disposes and drains remaining controlled work after
capturing the final observation, without recording this cleanup.

The compact encoded input is at most **491,520 bytes**, leaving room for bounded
production framing. Limits are 128 invocation outcomes, 32 actions and 512 actual
wire calls. Strings are bounded in Unicode code points: model 262,144, entry 512,
argument source 16,384, and raw reply/check source 393,216. IDs contain 1–128
characters from `[A-Za-z0-9_.-]`. All fixture sources and expectations are inline
in `cases.json`; its original byte hash closes over the complete fixture.

## Observations and failure evidence

Every scenario with valid fixture infrastructure returns `{"status":"ok","value":...}`. There is no
`status: "invalid"` for this operation. Client refusals and native failures are
observed attempt outcomes; malformed fixture, framing, observation or report
shapes are infrastructure failures.

The projection contains an ordered `steps` snapshot after each action, substantive
`requests`, job `progress`, `localCalls`, and consumed/remaining invocation counts.
Each step records its action, request/progress/local counts, session and disposal
state, current public job state, workspace capture state, ordered attempts, and
optional delivery result. Jobs retain the public job view and the flags active,
polling, releasePending, uncertainSubmission, suspended and cancelOnSubmit.
Workspace observations retain grant, projects, pending release, choosing/opening,
sequence and disposal state.

An attempt records pending, returned or rejected. Returned results retain success,
operation, cancellation, typed value, terminal outcomes and original artifact.
Errors retain native/code/effect, submissionUnknown and jobTransport. A diagnostic
code is used when no attached error code exists. Private error messages are omitted.
Native effects `none` and `unknown` remain distinct.

Nested public views, wire frames, local calls and returned artifacts use canonical
JSON strings with recursively sorted object keys. Array order and opaque source
strings are unchanged. Consecutive identical progress views are collapsed.
Literal scalar types are checked before typed conversion, including objects named
after JSON library private markers. Existing transport, per-observation, aggregate
observation and 32 MiB report budgets also apply.

A well-formed observation that differs from a golden is a compatibility failure.
An infrastructure error produces truthful failure evidence. The checker accepts
truthful reports of either kind while refusing forged qualification, verdicts,
capabilities, inventory, observations or corpus hashes. A CLI check exits nonzero
for a truthful unqualified report.

## Scope of evidence

The [48-case corpus](../mck/draft.9/README.md) covers client reconciliation,
submission uncertainty, cancellation races, stale callbacks, workspace captures,
and concrete JSON/Ion byte transfers. The MoonBit workbench's production client
is TypeScript shared by browser and Proton CEF. Its explicit adapter runs in Node
and Chromium with debug/release compiled production MoonBit job cores. Portable
MoonBit cursor tests also run on JS, native, Wasm and WasmGC.

These runs do not qualify a native executable client, native owner lifecycle,
authenticated window/origin authority, real picker/filesystem grants, process
exit, or a packaged OS/architecture. Those require owner and platform acceptance
evidence. The live native profile and capability advertisement do not change.

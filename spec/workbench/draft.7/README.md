# Native request frame qualification

Workbench MCK **`0.1.0-draft.7`** adds the single offline operation
`validate-native-frame`, JSON transport only. It qualifies raw request decoding
for the unchanged [`morphir/workbench/native` `0.1.0-draft.1`](../native/draft.1/README.md)
profile. The native profile is not MCK draft.7. Historical MCK drafts.1–.6,
connected v1, HTTP host draft.1, jobs draft.1 and terminal draft.5 remain unchanged.

Use the existing shared Rust runner with an explicit implementation adapter:

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.7 \
  --adapter /path/to/native-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.7 --report report.json
```

The runner admits the corpus and infrastructure envelope, negotiates this exact
draft, sends only inputs and compares fixed observations. It never decodes a
native source, links an implementation codec or derives expected results from
the implementation. `check` loads the corpus again, verifies its byte hash,
operation and format inventory, capabilities and observations, and recomputes
every result and qualification. A saved transcript tests this boundary; it does
not establish that an implementation performed decoding.

Literal JSON token kinds are preserved across corpus admission, live adapter
observations and saved reports. An object cannot impersonate a number, string,
boolean or projection, including when its member names resemble a JSON library's
private representation markers. Closed raw shapes are admitted before typed
conversion; malformed observations remain adapter exchange errors.

## Transport and compact inputs

The existing bounded newline-delimited request/response transport and IDs apply.
Capabilities require exactly `operations: ["validate-native-frame"]` and
`formats: ["json"]`, with `suite: "workbench"` and
`contractVersion: "0.1.0-draft.7"`. Empty, historical, future and build-suffixed
draft claims reject. The case request uses `op: "validate-native-frame"`, the
same suite and version, `format: "json"`, and the closed input below. The shared
runner never sends a case ID, expected observation or qualification hint.

```json
{
  "encoding": "utf8",
  "source": "{\"profile\":\"morphir/workbench/native\",\"contractVersion\":\"0.1.0-draft.1\",\"operation\":\"session.open\"}",
  "generate": {"prefix": {"repeat": " ", "count": 1048576}}
}
```

`encoding` is `utf8` or `hex`; `source` is required and remains opaque to the
runner. UTF-8 materialization encodes the decoded source string without adding
or removing a BOM or normalizing text. Hex materialization decodes complete
ASCII hexadecimal byte pairs, either letter case, without whitespace. Empty
source is allowed as an input to the implementation. `generate` is optional,
cannot be null and contains exactly `prefix`, which contains exactly `repeat`
and `count`. `repeat` is exactly one ASCII space; `count` is an integer from zero
through 1,048,576. Decimal and exponent spellings such as `1.0`, `1e0`
and `10e-1` denote the same integer. Counts are checked against their exact
decimal value, so rounding and underflow cannot admit fractional values. Prefix
bytes precede the materialized source.

The compact encoded input, including recipe, must fit the existing 1 MiB input
budget. The adapter must validate that envelope before allocation and reject
materialization beyond 2 MiB. There are no referenced fixture assets: the corpus
hash closes over all source bytes and recipes within `cases.json`. The runner
hashes the original file bytes, including whitespace. External asset closure
would require a separately versioned contract.

A malformed compact input is a corpus/adapter infrastructure failure. It cannot
produce a domain `invalid` observation. Adapter exceptions, unsupported methods,
transport failures, malformed projections and unknown rejection codes likewise
remain infrastructure errors. A well-formed observation differing from the
fixed expectation is a compatibility failure instead.

## Decoder stages and observations

Adapters invoke the production request decoder, without dispatching it or
creating any native authority. Stage precedence is:

1. Bound the complete materialized frame to 1,048,576 bytes, including whitespace
   and envelope. Reject excess bytes before UTF-8 decoding or JSON parsing.
2. Decode strict UTF-8 without replacement or BOM removal. Reject invalid,
   overlong and surrogate-encoding byte sequences.
3. Decode exactly one whole JSON value, reject duplicate decoded member names
   at every object depth, and enforce parser budgets. Root value depth is zero;
   each child value increments depth. Maximum depth is 64, maximum aggregate
   value nodes is 100,000, and maximum aggregate decoded string units is
   1,048,576 UTF-16 units, including member names. Member names are not nodes.
   Whitespace can precede/follow the value; a second value or BOM cannot.
4. For any of the six recognized `workspace.*` operations, bound the complete
   raw command to 4,096 bytes before closed-shape admission.
5. Check the closed public native draft.1 request shape, including operation,
   version, tokens, frozen payload shapes, integer ranges and UTF-16 identity
   bounds. Session equality and active capability ownership are not authenticated
   by this stage.
6. For `job.submit`, decode `payload.model` as exactly one duplicate-aware,
   budgeted generic JSON document. This is not IR, definition or function
   admission. Even a generic scalar may pass this stage.
7. If the submission input format is `json`, decode `inputs.source` in the same
   bounded whole-value manner and require its root to be an array. Typed argument
   admission is separate. `ion-text` remains an opaque source string here.

The successful observation is exactly:

```json
{"status":"ok","value":{"frameAccepted":true}}
```

Rejections are exactly `{"status":"invalid","code":"…"}` with one of:

| Code | First failed stage |
| --- | --- |
| `native.frame.limit` | Whole-frame byte, workspace command byte or outer parser budget |
| `native.frame.utf8` | Strict UTF-8 |
| `native.frame.json` | Outer whole JSON syntax or duplicate member |
| `native.frame.shape` | Closed native request shape |
| `native.frame.model` | Nested model whole JSON, duplicates or parser budget |
| `native.frame.arguments` | Nested JSON arguments whole array, duplicates or parser budget |

There are no diagnostic messages, parsed values, paths, session credentials or
submission effects in this projection. A rejection does not dispatch a request.
The outer budget takes precedence over later syntax; after outer admission,
shape precedes nested model, and nested model precedes JSON arguments.

## Evidence and remaining qualification

The [138-case independent corpus](../mck/draft.7/README.md) includes all 16
published raw rejection expectations, all 78 published structural request cases,
valid counterparts, every native operation, exact and excessive byte/depth/node
boundaries, decoded-name duplicates, nested whole-value consumption, UTF-16
identity bounds and deliberate separation from IR/value/Ion admission.

This qualifies offline request-frame acceptance only. It does not authenticate
window/origin/top-level caller context; open a session; choose an OS directory;
read files; bind a grant; run a function; reduce a job; validate a native response;
exercise navigation/reload cleanup, worker exit or race handling; advertise a
public native endpoint; or qualify any packaged desktop platform. Client and
owner lifecycle MCK operations, actual OS fixtures, runtime protocol adoption and
target-specific packaged qualification remain separate work.

The shared infrastructure JSON parser is not the native decoder oracle. Its
own transport/corpus limits and number normalization do not define native
request behavior. Schemas express closed structural contracts; the runner and
adapter enforce byte sizes, duplicate names, UTF-16 budgets, corpus identity and
runtime parsing rules that JSON Schema alone cannot establish.

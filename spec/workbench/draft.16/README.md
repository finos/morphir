# Native reply qualification

Exact offline Workbench MCK **`0.1.0-draft.16`** adds only
`validate-native-reply`, with JSON transport. It qualifies raw response decoding
for the current [`morphir/workbench/native` `0.2.0-draft.1`](../native/0.2.0-draft.1/README.md)
profile. The current native version is 0.2.0-draft.1. Historical published kits remain unchanged.

Use the existing shared Rust runner and an explicit production adapter:

```sh
morphir mck workbench run --kit spec/workbench/mck/draft.16 \
  --adapter /path/to/native-adapter --report report.json
morphir mck workbench check --kit spec/workbench/mck/draft.16 --report report.json
```

The runner validates infrastructure, negotiates the exact draft, sends only
inputs, and compares parent-owned fixed observations. It does not parse native
source, link an implementation codec, or calculate expected decoder behavior.
The independent `check` command reloads and hashes the original corpus bytes,
checks capabilities, inventory and observations, and recomputes each verdict and
qualification. Transcript replay tests the runner, not production decoding.

## Captured call and compact input

Capabilities require exactly `operations: ["validate-native-reply"]` and
`formats: ["json"]`, with `suite: "workbench"` and
`contractVersion: "0.1.0-draft.16"`. Historical, future and build-suffixed drafts
reject. Existing bounded newline-delimited transport and request IDs apply.
Case requests carry that suite/version, `op: "validate-native-reply"`,
`format: "json"`, and this closed input:

```json
{
  "expectedOperation": "session.close",
  "expectedSession": null,
  "encoding": "utf8",
  "source": "{\"ok\":true,\"operation\":\"session.close\",\"value\":{}}",
  "generate": {"prefix": {"repeat": " ", "count": 0}}
}
```

`expectedOperation` is one of the thirteen native 0.2.0-draft.1 operations.
`expectedSession` is required and is either null or an ASCII token of 1–128
characters from `[A-Za-z0-9_.-]`. A non-null capture requires equality wherever
the production reply contract carries session authority. Null disables that
captured-session comparison; it does not disable internal descriptor/receipt
identity consistency. Captures are fixture context, not proof of caller authority.

`encoding` is `utf8` or `hex`. UTF-8 encodes the decoded source string without
BOM removal, replacement or normalization. Hex accepts complete ASCII byte
pairs of either letter case, without whitespace. Empty source is permitted as
an input to the decoder. Source remains opaque to the runner.

The optional `generate` object contains exactly `prefix`, which contains exactly
`repeat: " "` and integer `count` from zero through 1,048,576. Prefix bytes precede
source bytes. Integral decimal/exponent spellings such as `1.0` and `10e-1` are
accepted by exact decimal value. Fractional, rounded and underflowed values must
not become integers. Null recipes, unknown keys and other repeated strings reject.

The compact input, including captures and recipe, is limited to 1 MiB; materialized
bytes to 2 MiB, checked before allocation. Every source and recipe is inline in
`cases.json`; hashing its original file bytes closes over the complete fixture.
There are no external fixture assets. Case IDs and expectations never reach the
adapter. Literal token types are validated before typed conversion in corpus,
observation and report handling. Objects named after JSON library private markers
cannot impersonate scalars or projections.

## Production decoding and projections

The adapter materializes the bytes and calls the production response decoder
with the captured operation and optional session. The decoder checks:

1. For `workspace.choose`, the complete raw reply is at most 524,288 bytes.
   Every reply is at most 1,048,576 bytes. Byte limits precede UTF-8 and JSON.
2. Strict UTF-8, without replacement or BOM removal.
3. Exactly one whole JSON value, with duplicate decoded member names rejected
   at every depth. Root depth is zero, maximum depth is 64, maximum aggregate
   value nodes is 100,000, and maximum aggregate decoded string length is
   1,048,576 UTF-16 units including member names. Member names are not nodes.
4. A closed success or native-error envelope. Successful operation must equal
   the captured operation; operation-specific payloads obey the native profile.
5. Descriptor offer/session equality, captured session equality, execution identity
   and receipt consistency, initial submit state, unique project IDs, bounded
   integer values and canonical padded base64 workspace chunks. A chunk is at
   most 262,144 base64 characters and 196,608 decoded bytes; an empty chunk
   requires `done: true`. These runtime rules exceed structural JSON Schema.

A validated success yields exactly:

```json
{"status":"ok","value":{"replyAccepted":true,"ok":true,"operation":"session.close"}}
```

A validated native failure yields exactly:

```json
{"status":"ok","value":{"replyAccepted":true,"ok":false,"error":{"code":"unavailable","effect":"unknown"}}}
```

Portable error codes are `invalid_request`, `unauthorized`, `unavailable`,
`not_found`, `conflict` and `limit`. Effects are `none` or `unknown`; neither may
be collapsed into the other. MCK `status: "ok"` means the reply was validated,
including a validated native failure. It is not a claim of successful execution.
Messages, paths, session IDs, receipts and workspace/model bytes are omitted.

Decoder rejection is `{"status":"invalid","code":"…"}`:

| Code | Failed validation |
| --- | --- |
| `native.reply.limit` | Raw byte or JSON parser budget |
| `native.reply.utf8` | Strict UTF-8 |
| `native.reply.json` | Whole JSON syntax or duplicate names |
| `native.reply.shape` | Closed envelope, payload or internal consistency |
| `native.reply.operation` | Successful operation differs from captured call |
| `native.reply.authority` | Descriptor offer/session or captured-session correlation |

Malformed compact inputs, transport failure, malformed observations, unknown
codes and invalid saved reports are infrastructure errors. A well-formed
observation differing from the fixed expectation is a compatibility failure.
A truthful report can record either; it must never claim qualification for them.

## Evidence and remaining work

The [185-case independent corpus](../mck/draft.16/README.md) includes all 97
published structural response fixtures with explicit runtime expectations,
all operations, both native error effects, call correlation, byte/parser
boundaries, exact numeric tokens, project uniqueness and base64 canonicality.

This qualifies offline reply validation. It does not exercise the native client
or owner lifecycle, authenticate window/origin provenance, create real picker or
filesystem grants, prove process exit, or qualify a packaged OS/architecture.
Those require executable lifecycle kits and separate platform acceptance.

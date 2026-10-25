# MEP as a Smithy model

This folder holds the Morphir Extension Protocol (MEP) as a
[Smithy IDL 2.0](https://smithy.io/2.0/) model. The model uses the `smithy.rpc`
JSON-RPC traits of [moonrockz/smithy](https://github.com/moonrockz/smithy).
moonrockz/smithy uses this model to generate MEP extension code in MoonBit,
Python and Go, and later MCP and LSP bindings. The same model validates
JSON-RPC messages and session transcripts.

The model is interim. Later, Morphir defines the protocol in Morphir itself.
[`../contract/src/mep.gleam`](../contract/src/mep.gleam) stays the source of
truth. This model follows it and the wire mapping table in
[`../README.md`](../README.md). It does not replace the Gleam contract, and no
tool generates it from the contract yet. When you change the contract, change
this model in the same pull request. The check below compares the two.

## Scope

- **Protocol version:** MEP `0.2.0-draft.1`, the version in
  `contract/gleam.toml`. This draft keeps every legacy `0.1` method and shape,
  and adds `morphir.frontend.compileModel` and `morphir.backend.generateModel`.
  So one model covers legacy `0.1` sessions and `0.2.0-draft.1` sessions. The
  services have `version: "0.2.0-draft.1"`.
- **JSON-RPC version:** 2.0 only.
- **Not in scope:** Content-Length framing, which is transport, and admission
  rules that need decoded payloads or trust decisions: payload length and
  SHA-256 agreement, decoded depth and node limits, evidence binding, and
  lossy projection. See [`../model-transport.md`](../model-transport.md).

## Layout

```text
spec/mep/smithy/
  README.md
  model/
    mep.smithy              protocol, session, services, operations, error codes
    handshake.smithy        peers, initialize, describe, capabilities, claims
    compile.smithy          legacy compile request and result
    generate.smithy         generate request and result, diagnostics
    model-transport.smithy  rich model transport (0.2.0-draft.1)
  transcripts/              session transcripts, checked as tests
  values.json               JSON examples that are not JSON-RPC messages
  mck-expectations.json     expected findings for each MCK model-transport case
```

## How the model maps MEP

- `morphir.mep#MepSession` is the `@jsonRpcProtocol`. Its peers are `host`,
  which accepts `HostService` (`morphir.progress`), and `extension`, which
  accepts `ExtensionService` (every other method).
- `@jsonRpcSession` declares the states `starting`, `initializing`, `ready`,
  `stopping` and `stopped`, and capabilities read from the
  `morphir.initialize` result. `@jsonRpcLifecycle` on each operation gives the
  states where it is allowed, its transitions and the capabilities it needs.
- `$/cancelRequest` has `@jsonRpcCancels(idMember: "id", code: -32800)`, so
  the reply of a cancelled request can be `-32800`.
- Smithy member names are the wire names, including the snake_case members
  of `ExtensionInfo`. Use the default `--member-names smithy`.
- A Gleam `Json` value is a Smithy `document`. A member that is "read as
  empty when absent" has a default (`= []`, `= {}` or `= false`).
- The contract does not define the results of `morphir.ping` and
  `morphir.shutdown`, or the payloads of `morphir.validator.validate`,
  `morphir.transform.transform` and `morphir.workspace.discover`. Their
  results are any JSON value. The Rust SDK sends `{"ok": true}` for ping and
  `{}` for shutdown.
- `ErrorCode` is an `intEnum` of every MEP code, for code generation.

## Run the checks

```sh
mise run spec:mep-smithy-check
```

The task runs [`tools/spec-mep-smithy.ts`](../../../tools/spec-mep-smithy.ts).
It calls the smithy CLI through `moonx moonrockz/smithy-cli@0.6.0`, which
comes with the pinned MoonBit toolchain in `.config/mise/config.toml`. The
script:

1. validates the model and checks that it is in `smithy format` form;
2. checks each transcript as a session of `morphir.mep#MepSession`;
3. checks that every JSON-RPC example in the
   [protocol draft](../../../docs/design/draft/extensions/protocol.md) is a
   message of a transcript, and every other JSON example is in `values.json`;
4. validates each value in `values.json` against its shape;
5. validates the request, the result and the two transport offers of each
   case in [`../mck/model-transport.cases.json`](../mck/model-transport.cases.json),
   and compares the findings with `mck-expectations.json`;
6. compares the types of `mep.gleam` with the shapes of the model: the fields
   of each record with the members of its structure, by wire name, and the
   constructors of each enum with its members. `CONTRACT_EXCEPTIONS` in the
   script lists each known difference and its reason.

The CI `docs` job runs the task when `spec/mep/**`, a Markdown file or the
script changes.

To check one transcript by hand:

```sh
moonx moonrockz/smithy-cli@0.6.0 validate rpc transcript \
  --protocol morphir.mep#MepSession \
  spec/mep/smithy/model/*.smithy spec/mep/smithy/transcripts/session-legacy.md
```

## Transcripts

Each transcript is Markdown. A fence `jsonrpc host -> extension` is one
message. A transcript with a `jsonrpc-expect` fence passes when its findings
match that list.

| Transcript | Content | Result |
| --- | --- | --- |
| `doc-initialize.md` | protocol.md initialize request and result, framing ping | Valid |
| `doc-version-mismatch.md` | protocol.md initialize request and -32011 error | Valid |
| `doc-compile.md` | protocol.md compile request, progress, success result | Valid |
| `doc-compile-failure.md` | protocol.md compile request, failure result | Valid |
| `doc-cancel.md` | protocol.md compile request, cancel, then -32800 | Valid |
| `doc-generate.md` | protocol.md generate request and result, backend capability | Valid |
| `session-legacy.md` | a complete `0.1` session, with the protocol.md claim set | Valid |
| `session-model-transport.md` | a `0.2.0-draft.1` session with MCK cases model-0028 and model-0001 | Valid |
| `lifecycle-violations.md` | requests in the wrong state, capabilities not advertised | 7 expected findings |
| `protocol-errors.md` | unknown method, bad params, wrong reply id, unsolicited reply | 6 expected findings |

## MCK cases

All 35 requests of `model-transport.cases.json` and their transport offers
are valid, except model-0033, which the validator refuses as an unknown
member. Of the five results, model-0020 (`model: null` on failure) is
refused. The other cases that MEP refuses fail at admission, which a message
model does not check, or at a rule that is a gap below.
`mck-expectations.json` states the reason for each case.

## Gaps

At each of these places, the `smithy.rpc` traits or the smithy CLI 0.6.0
cannot state or check a MEP rule. Each gap is a beads issue in
moonrockz/smithy, under the epic smithy-2qe.34, with the label `mep`. The
model marks each place with a `GAP smithy-2qe.34.N` comment.

| Issue | MEP rule that the model cannot state or check |
| --- | --- |
| smithy-2qe.34.15 | Error codes -32000 to -32004 and -32010 to -32014 are in the reserved range, so `rpcError` cannot declare them or the `data` of -32011. |
| smithy-2qe.34.16 | `morphir.initialized`, `morphir.exit`, `$/cancelRequest` and `morphir.progress` are notifications; a request with an `id` is accepted. |
| smithy-2qe.34.17 | Receivers ignore unknown members unless `critical` names them; the validator refuses unknown members, and the transcript command has no `--unknown-members`. |
| smithy-2qe.34.18 | `ExtensionCapabilities` and `CompileOptions` carry extra members beside the named members, and `CompileOptions` refuses `sourceRootUri` and `sourceRoot`. |
| smithy-2qe.34.19 | The extension refuses a request in the wrong state with -32014, and a capability that is not advertised with -32013; the reply code is not checked. |
| smithy-2qe.34.20 | Rich methods need `protocolVersion` `0.2.0-draft.1` and a session tuple for the method; validate and transform need the extension type. A pointer only tests presence. |
| smithy-2qe.34.21 | `CompileModelResult` requires `model` when `success` is true and forbids it when false; a claim set has exactly one of `claimsVersion` and `statementVersion`. |
| smithy-2qe.34.22 | A request id is a number or a string; the model uses a `document`. |
| smithy-2qe.34.23 | An unknown `PeerKind` is read as `unspecified`; the validator refuses it. |
| smithy-2qe.34.24 | Relations between values: the selected version and tuples come from the offers, `options.irVersion` equals `output.irVersion`, progress names an active request, `baseline` only for an incremental frontend. |
| smithy-2qe.34.25 | Params of validate, transform and workspace discover are any JSON value; there is no `paramsMember`. |
| smithy-2qe.34.26 | A canonical base64 pattern on a model payload exceeds the default validation work budget, and the CLI cannot raise it, so `content` has no pattern. |

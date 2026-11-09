# Proposal

## Why

MEP `0.2.0-draft.1` has the extension type `validator`, the legacy method
`morphir.validator.validate` with no defined payload, and the error code
`ValidationError` (`-32003`). It has no request, no result, no capability
record and no model-transport operation for validation. Thus an extension
cannot claim validation in a form that a host can check, and a host cannot send
a model to it. finos/morphir-dotnet needs this contract for external model
analyzers. The design started as the morphir-dotnet proposal
[MEP validateModel payload](https://github.com/finos/morphir-dotnet/blob/main/docs/content/contributing/design/proposals/mep-validate-model.md).
Damian Reeves decided its open questions on 2026-11-09. This change records
them.

## What Changes

- Add the model-tier method `morphir.validator.validateModel` and the model
  operation value with the same string. The method needs the exact MEP
  `0.2.0-draft.1`, the `validator` capability and an admitted validateModel
  tuple, as `compileModel` and `generateModel` need theirs.
- Add `ValidateModelRequest`: the model, the selected `input` tuple and
  extension-owned `options`. Add `ValidateModelResult`: a required list of
  diagnostics and no success flag. A validator that cannot run answers with
  `-32003`.
- Add `ValidatorCapability` (`irVersions` and `rules`) as the member
  `validator` of `ExtensionCapabilities`. Each `ValidatorRule` has an absolute
  IRI `id` and the diagnostic `code` that the rule reports.
- Edit `0.2.0-draft.1` in place. A host offers validateModel tuples only to
  an extension whose describe result or recorded claims list at least one,
  because existing extensions refuse an offer with an operation that they do
  not know.
- Extend host conversion to validateModel, without loss only. The host never
  sends a lossy conversion for validation, even when the user allows loss.
- The legacy `morphir.validator.validate` does not change.
- No new JSON-RPC error number and no change to the draft version.

## Capabilities

### New Capabilities

- `mep/validate-model`: the validateModel method, its request, result and
  capability, the offer rule for validateModel tuples, and host conversion for
  validation.

### Modified Capabilities

None. `openspec/specs/` has no capability for MEP model transport.

## Tracking

- Pull request finos/morphir#1139.
- Design source: task 7.1 and design UP-1 of the morphir-dotnet change
  `add-mep-core`.
- Follow-up: an issue that proposes an optional model-node IRI in
  `Diagnostic` for all methods (decision VAL-4).
- Follow-up: bead `morphir-sugs` (IR regeneration with the Gleam extension on
  the MoonBit CLI), through a `--types-only` flag on
  `morphir extension compile` in finos/morphir-moonbit.

## Impact

- `spec/mep/contract/src/mep.gleam` and the generated
  `spec/mep/generated/mep.ir.json`.
- `spec/mep/smithy/model/` (new `validate.smithy`; `mep.smithy`,
  `handshake.smithy`, `model-transport.smithy`), two transcripts, and
  `spec/mep/smithy/mck-expectations.json`.
- `spec/mep/model-transport.md`: the offer rule, the validate request and
  result, and "Host conversion for validation".
- MCK cases model-0036 to model-0041 in
  `spec/mep/mck/model-transport.cases.json`.
- `spec/mep/README.md`, `spec/mep/smithy/README.md`, `spec/mep/mck/README.md`,
  the protocol draft `docs/design/draft/extensions/protocol.md` and
  `crates/morphir/tests/mep_contract.rs`.
- SDKs and hosts add the method in their own repositories. Existing peers need
  no change, because no host offers a validateModel tuple to them.

# Tasks

## 1. Contract (finos/morphir#1139)

- [x] 1.1 Add `ModelOperation.ValidateModelOperation`, `Method.ValidateModel`, `ValidatorCapability`, `ValidatorRule`, `ExtensionCapabilities.validator`, `ValidateModelRequest` (with `input`) and `ValidateModelResult` to `spec/mep/contract/src/mep.gleam`, with their wire rules; verified by `gleam build` and `mise run spec:mep-check`.
- [x] 1.2 Regenerate `spec/mep/generated/mep.ir.json` with the Gleam frontend of finos/morphir-gleam (`morphir-gleam-binding` 0.4.0, commit `a529add`), types only, IR 4, and check that the same program gives a byte-identical IR for the unchanged contract on `main`; verified by `mise run spec:mep-check`.
- [x] 1.3 Add the Smithy shapes, the operation, the offer rule comment and the two transcripts; verified by `mise run spec:mep-smithy-check`.
- [x] 1.4 State the offer rule, the validate request and result, the rule IRIs and "Host conversion for validation" in `spec/mep/model-transport.md`, the wire rules in `spec/mep/README.md`, and the method table, offer rule and conversion text in `docs/design/draft/extensions/protocol.md`; verified by `mise run spec:mep-check`.
- [x] 1.5 Add MCK cases model-0036 to model-0041 and their Smithy expectations; verified by `mise run spec:mep-check` and `mise run spec:mep-smithy-check`.
- [x] 1.6 Validate this change; verified by `openspec validate add-mep-validate-model --strict` and `mise run openspec:verify`.

## Workflow follow-up

- Follow AGENTS.md for review, archive, tracker closure and release approval.
- Resolve finos/morphir#1144, the follow-up issue for a model-node IRI in `Diagnostic` (VAL-4).
- SDK, host and guest support for `validateModel` follows in finos/morphir-rust, finos/morphir-moonbit and finos/morphir-dotnet.
- IR regeneration with the MoonBit CLI follows bead `morphir-sugs` and finos/morphir-moonbit#325.

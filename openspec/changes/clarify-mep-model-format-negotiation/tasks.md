# Tasks

## 1. Spec text (bead morphir-1q2c, finos/morphir#1115)

- [x] 1.1 State offer order, the default tuple, the required single-tuple offer and the empty-agreement failure in `spec/mep/model-transport.md` ("Offer order and the default tuple"); verified by `mise run spec:mep-check` and `mise run mck:check`.
- [x] 1.2 Make the Gleam contract comments, the generated `spec/mep/generated/mep.ir.json`, the Smithy comments, the `spec/mep/README.md` wire-rule table and `docs/design/draft/extensions/protocol.md` agree; verified by `mise run spec:mep-check` and `mise run spec:mep-smithy-check`.
- [x] 1.3 State host conversion for `generateModel` with the loss, digest and revision, and guarantee rules, and the details left to the host, in `spec/mep/model-transport.md` ("Host conversion for generation") and the same agreeing files; verified by `mise run spec:mep-check`, `mise run spec:mep-smithy-check` and `mise run mck:check`.
- [x] 1.4 Validate this change; verified by `openspec validate clarify-mep-model-format-negotiation --strict` and `mise run openspec:verify`.

## 2. MCK checks (bead morphir-hv6m)

- [ ] 2.1 Add MCK cases and runner support for (a) host order kept, (b) first agreed tuple used, (c) required offer with no overlap gives `extension.tuple_unavailable`, (d) missing default with another agreed tuple succeeds, and (e) generate with host conversion; verified by the acceptance criteria of bead `morphir-hv6m` and `mise run mck:check`.

## Workflow follow-up

- Follow AGENTS.md for review, archive, tracker closure and release approval.
- Host and SDK changes follow in finos/morphir-moonbit#281 and the owning repositories.

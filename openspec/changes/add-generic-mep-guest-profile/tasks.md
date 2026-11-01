# Tasks

## 1. Generic profile (bead morphir-ukvn.5.64.36.15)

- [x] 1.1 Add the kit file `spec/mep/mck/guest-generic-json.json` with the fixed package, the `morphir-fixture-flags`, `python` and `gleam` source sets, and the `3.0.0` and `4.0.0` expected IR recorded from a real guest; verified by `cargo test --locked -p morphir-mck`.
- [x] 1.2 Add the profile `generic-json-library-v1` to the runner: kit loading and URI rules, plan selection from the describe claim, requests, IR equivalence, round trip, refusals and report recheck; verified by unit tests with synthetic observations in `cargo test --locked -p morphir-mck`.
- [x] 1.3 Run `morphir mck mep guest-run` and `report-check` against the SDK fixture (finos/morphir-moonbit `apps/morphir/fixtures/sdk-guest`) and the published Python 0.4.2 guest, and record the receipts in the pull request; verified by exit 0 and `qualified=true` for both.
- [x] 1.4 Run the published Gleam 0.4.0 guest and record the result; verified by the report. Result: not qualified at `roundtrip-vfour` (the regenerated code compiles with output type `Unit`); the model-tier round trip `roundtrip-model-vfour` shows the same defect. A local-only build that skipped the legacy v4 round trips passed every other case up to that one, including `compileModel`, `generateModel` and the bad-digest refusal.
- [x] 1.5 Document the profile in `spec/mep/mck/README.md`, `spec/mck/cli-contract.md` and `CHANGELOG.md`; verified by `mise run check`.
- [x] 1.6 Check that the existing kit files and digests do not change; verified by `git diff --stat origin/main -- spec/mep/mck/guest-moonbit-bool.json spec/mep/mck/guest-python-json.json`.
- [x] 1.7 Validate this change; verified by `openspec validate add-generic-mep-guest-profile --strict` and `mise run openspec:verify`.

## Workflow follow-up

- Follow AGENTS.md for review, archive, tracker closure and release approval.
- The Gleam v4 round trip defect, if confirmed by the run, belongs to finos/morphir-gleam.

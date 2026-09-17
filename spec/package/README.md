# Morphir package specification drafts

The [Library contract](library-contract.md) is the first specification Stage 0 slice of the
[model package design](../../kb/bundles/morphir/morphir-package-system/package-system-design.md).
It contains two current-v4 Library examples, draft release-manifest and lock-core schemas,
and candidate [MCK package cases](mck/README.md).

The wire marker `0.1.0-draft.1` identifies a restricted experimental profile. It is not a
stable interchange contract or a claim that Stage 0 is complete. No package resolver,
registry client or installer ships in this slice.

The [resolution contract](resolution-contract.md) separately specifies experimental
`0.1.0-draft.2` replay, initial selection, targeted updates, and structured diagnostics.
Its schemas and fixed MCK expectations drive shared-core checks against TypeScript and
independent Rust resolution implementations. [Parent PR #820](https://github.com/finos/morphir/pull/820)
landed these checks with merged TypeScript and Rust pins on 2026-09-17 UTC.
Results are metadata projections, not installable locks or verified payload/API compatibility. The draft.1
integrity contract and content digest separator remain unchanged.

Run `mise run package:schema-check` from the repository root after the required checkout setup.
It validates schema syntax and example structure using the existing JSON Schema tool.
Run `mise run package:check` to execute the package corpus through the TypeScript MCK core,
both in-process and through its executable adapter. Reports appear in `.dev/out/mck/`.
Run `mise run package:check:rust` to build the pinned Rust adapter and execute the same
corpus through the same TypeScript driver against the independent Rust implementation.
The dedicated package CI job runs both integrity implementations and uploads their reports.
The suite checks normalization, digests, schemas, and the worked Library set's integrity.
It does not establish full package-system compatibility or complete Stage 0.

The resolution integration adds `mise run package:resolution-check` for both TypeScript
transports and `mise run package:resolution-check:rust` for Rust through the same driver.
These tasks explicitly select draft.2 and
write separate `package-resolution-*.json` reports. See the [MCK suite](mck/README.md)
for the exact pins, corpus hashes, and passing integration CI evidence.

The [shared MCK core decision](../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md)
places package case execution in finos/morphir-typescript. The implementation lives in
`ecosystem/morphir-typescript/packages/mck/src/package/`; this repository only invokes it.
Rust production behavior lives in `ecosystem/morphir-rust/crates/morphir-package/`.
Its `mck-adapter-rust --suite package` adapter delegates to that library; default invocation
continues to serve the IR protocol. Rust does not supply another compatibility runner.
Implementation changes must land upstream before the parent merges the corresponding submodule pin.
A dependent draft may pin a published feature commit for CI, then replace it with the merged commit.
No standalone package compatibility runner ships here.

The planned user-facing lockfile is `morphir.lock`. The current `lock-core.json` fixture
and `lock-core.schema.json` describe only a partial graph, not an installable lockfile.

The candidate [local Library contract](local-library-contract.md) adds draft.3 full-lock,
registry-record and release-statement schemas around the unchanged resolution graph.
Its [unsigned worked shapes](mck/fixtures/local-registry/unsigned/README.md) use the existing
two-Library identities and digests, but are not executable trust evidence. The accompanying
[trust profile](package-trust-profile.md) proposes TUF/DSSE rules and durable local authorization.
The candidate also specifies filesystem bounds, publication and recovery, and structured diagnostics.
Its [MCK definitions](mck/README.md#candidate-local-registry-contract) describe fixed scenarios
with explicit pending asset bindings. They are not an executable compatibility corpus yet.
Wire-contract review was approved on 2026-09-17. The
[signed two-Library fixture](mck/fixtures/local-registry/assets/signed/README.md) passed
user review on 2026-09-17. Shared TypeScript runtime support, independent Rust support
and parent integration are the next implementation stages.
The later local workflow adds packing, publication, acquisition, and verified consumption;
distributed registries and advanced multi-version graphs remain separate stages.

Executable extensions and installable tools retain separate contracts. Nothing here
requires their manifests or lifecycles to adopt the model-package format.

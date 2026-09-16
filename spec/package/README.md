# Morphir package specification drafts

The [Library contract](library-contract.md) is the first specification Stage 0 slice of the
[model package design](../../kb/bundles/morphir/morphir-package-system/package-system-design.md).
It contains two current-v4 Library examples, draft release-manifest and lock-core schemas,
and candidate [MCK package cases](mck/README.md).

The wire marker `0.1.0-draft.1` identifies a restricted experimental profile. It is not a
stable interchange contract or a claim that Stage 0 is complete. No package resolver,
registry client or installer ships in this slice.

Run `mise run package:schema-check` from the repository root after the required checkout setup.
It validates schema syntax and example structure using the existing JSON Schema tool.
Run `mise run package:check` to execute the package corpus through the TypeScript MCK core,
both in-process and through its executable adapter. Reports appear in `.dev/out/mck/`.
The suite checks normalization, digests, schemas, and the worked Library set's integrity.
It does not establish full package-system compatibility or complete Stage 0.

The [shared MCK core decision](../../kb/bundles/morphir/morphir-package-system/decisions/0001-package-compatibility-uses-the-shared-mck-core.md)
places package case execution in finos/morphir-typescript. The implementation lives in
`ecosystem/morphir-typescript/packages/mck/src/package/`; this repository only invokes it.
The TypeScript changes must land upstream before the parent merges the corresponding submodule pin.
A dependent draft may pin a published feature commit for CI, then replace it with the merged commit.
No standalone package compatibility runner ships here.

Executable extensions and installable tools retain separate contracts. Nothing here
requires their manifests or lifecycles to adopt the model-package format.

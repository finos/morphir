---
type: Decision Record
title: One legacy name grammar and one FileStem definition
description: "Both IR v4 schemas use the core legacy word grammar ^[a-z0-9]+$, FileStem with its truncation suffix is defined once in the document-tree schema, pathBudget stays required, and ModuleManifestFile gains the fileNames map decision 0001 promised."
state: Accepted
decided: 2026-09-04
tags: [ir, ir-v4, naming, document-tree, schema, mck]
status: draft
---

# One legacy name grammar and one FileStem definition

The two v4 schema files disagree with each other and with the naming corpus in two places that decision 0001 left
half-applied. This record closes both and keeps `pathBudget` required.

| Item | Decided |
| ---- | ------- |
| Legacy name-array item grammar | `^[a-z0-9]+$` in both schemas; a word may be all digits |
| `FileStem` | Defined once in the document-tree schema as `^_?[a-z0-9]+(-_?[a-z0-9]+)*(__[0-9a-f]{8})?_?$`, referenced by the core schema; the truncation suffix stays |
| `pathBudget` in the distribution manifest | Required, as decision 0001 states |
| `fileNames` in the module manifest | Added as an optional map from canonical name to escaped stem, present whenever a stem was truncated |

```yaml
["f", "r", "2052", "a"]      # legacy array; 2052 is a word, so the tree schema's ^[a-z][a-z0-9]*$ was wrong

formatVersion: 4              # module manifest with one truncated stem
path: my-org/domain
types: [some-extremely-long-canonical-type-name-that-overflows]
fileNames:
  some-extremely-long-canonical-type-name-that-overflows: some-extremely-long-canon__3f9a1c04
```

| Option | Outcome | Why |
| ------ | ------- | --- |
| Core grammar in both schemas | Chosen | The naming corpus's `["f","r","2052","a"]` case and morphir-elm's `Name.fromString` both produce digit-only words |
| Tree schema's grammar (`^[a-z][a-z0-9]*$`) | Rejected | Rejects every v3 name containing a number run, such as the FR2052A regulation names |
| Keep the truncation suffix | Chosen | Decision 0001 defines it and the `fileNames` map makes it reversible |
| Drop the suffix to match the corpus | Rejected | The corpus omits it only because its generator cannot hash yet (decision 0003); that is a gap in the corpus, not a rule |
| `pathBudget` optional, absent means a frozen 4000 | Considered, not taken now | Equivalent for readers and friendlier for authored YAML, but it freezes the default for v4 and catches a silently truncating writer one step later; revisit once authored trees exist |

## Why

Decision 0001 introduced the escape layer, the budget, and the truncation suffix, and listed the schema changes as
consequences. The schemas were updated for the name patterns but not for the rest, so `FileStem` exists only in the
core schema where no file name lives, the tree schema restated the legacy grammar with a stricter pattern, and
`fileNames` existed only in prose. The Morphir Compatibility Kit's first run recorded the gaps as case `names-0007`.

Keeping `pathBudget` required preserves the guarantee 0001 wanted: a reader that cannot honor a tree's budget says
so once, up front, from a recorded value rather than an implied one. The optional form was weighed and deferred,
not rejected: its one cost is freezing the default for v4, and its one benefit, terser hand-authored trees, has no
demand to measure yet.

## Consequences

1. `morphir-ir-v4-document-tree-files.yaml` defines `FileStem` and `fileNames`, keeps `pathBudget` required, and
   changes its legacy item pattern; `morphir-ir-v4.yaml` references `FileStem` from the tree schema (or, until
   cross-file references exist, carries an identical copy that the generated schema of specification step 7.2
   replaces).
2. The naming corpus generator gains truncation cases marked host-verified, so the suffix pattern is tested.
3. Kit `names-0007` becomes active with `["item", "2"]` and `["f", "r", "2052", "a"]` as accepted legacy spellings;
   a truncated-stem module manifest is added to `document-tree.md`; `document-tree-0001` keeps `pathBudget`.
4. A module manifest whose `fileNames` maps a stem that does not match `FileStem`, or whose truncated stem is not
   also listed in `types` or `values` under its canonical name, is invalid.

## Revisit when

- Hand-authored document trees appear and the required `pathBudget` proves to be friction, at which point the
  optional form above is the change to make, with 4000 frozen for v4.

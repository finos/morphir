# `acme/orders` bounded-generation fixture

Start with [cases.json](cases.json). Each row gives the semantic IR version,
four tree roots and an expanded single-file JSON baseline. Paths in the row
are relative to this directory. The classic trees write `"3.1.0"` in every
file, and the equivalent classic Library writes integer `3` in its single
file. The v4 inputs use integer `4` in both layouts.

Each tree has the same nine extensionless document paths. Add `.json` or
`.yaml` for the selected profile. The plain JSON tree also supplies the
expanded document for every contextual JSON and YAML twin. The contextual inputs use
hand-selected aliases to exercise decoding, including in classic type and
expression attribute slots. They pin no compaction writer output bytes.

[expected.json](expected.json) records the expected inventory and body facts
independently of a host. The SDK dependency is a small integer interface whose
files use `spec` below `deps/morphir/_sdk/@/basics`. The private `audit` module
is present in the Library. In `domain`, enumerate types before values and use
the listed name order within each kind for this case. With two members per
page, page two contains `total-in-USD`, stored as `total-in-_usd.value`. Its
body references the value `order`, whose body contains integer `73`. The type
also named `order` has its own document. `classicAttributes` uses JSON
Pointers into expanded v3.1 documents.

The fixtures follow the [v3.1 tree contract](../../../../../docs/spec/ir/schemas/v3/document-tree-files.md),
[v4 tree contract](../../../../../docs/spec/ir/schemas/v4/document-tree-files.md)
and [contextual envelope examples](../../../../../docs/spec/ir/context/examples/README.md).
Each contextual YAML tree carries the same typed tables and name references
as its contextual JSON twin.

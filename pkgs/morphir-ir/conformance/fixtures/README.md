# Upstream JSON fixtures

Content is vendored under Apache-2.0. The selected cases are reproduced without changing their input JSON. Generated MoonBit tests preserve their number lexemes and duplicate object keys.

| Local file | Repository and source |
| --- | --- |
| `mck.json` | finos/morphir, JSON fences in `spec/ir/mck/{names,types,values,patterns-and-literals,definitions,distributions,versions}.md` |
| `v3-greeting.json` | finos/morphir, `spec/ir/mck/node-address-fixtures/v3-greeting.json` |
| `naming-conformance.json` | finos/morphir, `docs/spec/ir/fixtures/naming-conformance.json` |
| `format-version-conformance.json` | finos/morphir, `docs/spec/ir/fixtures/format-version-conformance.json` |
| `v1-rentals.json` | finos/morphir-elm, `tests-integration/cli/test-data/rentals/expected-morphir-ir-v1.json` |
| `v2-rentals.json` | finos/morphir-elm, `tests-integration/cli/test-data/rentals/expected-morphir-ir.json` |

Commits are pinned in `scripts/refresh-ir-fixtures.mbtx` and the module README. The historical rentals files are accepted inputs; canonical writers additionally emit the documentation wrappers present in Elm's codecs. Handwritten `elm_wire_test.mbt` assertions pin those encoder behaviors and the historical v2 literal spelling.

The naming corpus also contains filesystem rendering cases. This module tests canonical names and legacy name decoding, not filesystem paths or filename truncation. Format tests use this implementation's v1–v4 support table, which includes historical v1/v2 in addition to the upstream table.

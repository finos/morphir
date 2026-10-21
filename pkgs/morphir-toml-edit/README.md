# morphir-toml-edit

A host-independent TOML 1.0 parser and format-preserving editor in MoonBit.
The parser retains the source and a concrete syntax tree of source spans.
Printing an untouched document returns exactly its original text, including
comments, whitespace, quoting, key order and line endings.

```moonbit
let doc = @edit.parse("[workspace]\nmembers = ['core'] # keep\n")
let next = doc.append(["workspace", "members"], "'app'")
assert_eq(next.encode(), "[workspace]\nmembers = ['core','app'] # keep\n")
```

Paths are arrays of decoded key segments. `["project", "name.with.dot"]`
addresses the quoted key `"name.with.dot"` in `[project]`. A dot inside a
segment never acts as a path separator.

| Operation | Behavior |
| --- | --- |
| `parse`, `parse_bytes` | Parse TOML 1.0, including dotted keys and arrays of tables. The byte boundary validates UTF-8 strictly. |
| `encode`, `encode_bytes` | Return the original or edited text, without normalization. |
| `get` | Read a value's original spelling in a standard or inline table. |
| `set` | Replace a value or insert a key into a standard or inline table. Existing implicit parent tables gain a header when necessary. Create missing intermediate tables with `add_table`. |
| `remove` | Remove a key, retaining surrounding comments and whitespace. |
| `add_table` | Append a standard table, quoting path segments as needed. |
| `remove_table` | Remove a table and its descendants, including sections interleaved with unrelated tables. |
| `append`, `remove_item` | Add or remove array items, retaining existing item text and comments. |

Edits return a new document. They validate the supplied TOML value, apply only
local source patches, and parse the candidate again before returning it.
A rejected edit leaves the original document intact. A value argument must
contain exactly one value, with no trailing comment or injected statement.
Use TOML string syntax for string values, such as `"'app'"`.

Tier 1 refuses edits affecting dotted-key definitions, including their
intermediate tables, and arrays of tables, including their ancestors or
children. It also refuses creating dotted keys inside supplied inline values.
Unrelated entries in the same document remain editable. Dotted-key editing
belongs to `morphir-ukvn.5.86.16`; array-of-tables editing belongs to
`morphir-ukvn.5.86.17`. Use a value parser for semantic reads of these constructs.

The editor preserves existing trivia rather than guessing its ownership.
Removing an entry leaves its trailing comment as a standalone comment; removing
a table retains its comments and blank lines. Inserting new text uses the
existing CRLF convention when present and LF otherwise. Existing spacing is
never reformatted. A leading BOM is rejected rather than stripped.

`Diagnostic` includes a typed reason, message and position. Offsets are
zero-based UTF-16 units; lines and columns are one-based, with columns also
counting UTF-16 units. Invalid UTF-8 diagnostics identify the byte offset in
the message and the decoded preceding text's position. No filesystem or host
access is required.

Offset date-times with second `60` must identify a recorded UTC leap second,
including the shift across dates for numeric offsets. The leap-second table
is pinned to IERS Bulletin 72 from July 2026 and must be updated when IERS
announces another insertion. Local times and local date-times have no offset
with which to determine the UTC instant.

The engine's existing `config` parser and `Document::encode` remain unchanged
for semantic reads and files written from scratch. The engine depends on this
package; this package has no dependency on the engine or another TOML parser.

## Validation

`conformance_test.mbt` and `encoding_test.mbt` contain all 709 TOML inputs in the
TOML 1.0 manifest from [toml-lang/toml-test](https://github.com/toml-lang/toml-test)
at revision `ff49d109861c1ad25af53f687f2aef19ab650600`, including nine malformed
UTF-8 fixtures. Their source bytes, including CRLF, are preserved in MoonBit
literals. Valid fixtures round-trip through both the text and byte APIs;
invalid fixtures must raise `InvalidToml`. The upstream MIT license is included
in `TOML-TEST-LICENSE`.

Additional tests check exact text after edits and refusals. Engine integration
tests in `pkgs/morphir-engine/config/toml_edit_test.mbt` compare edited output
with expected values through the existing config parser.

```sh
moon test -p finos/morphir-toml-edit finos/morphir-engine/config --target js --deny-warn
mise run test
mise run lint:moonbit
```

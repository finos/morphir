# Morphir file context examples (0.1.0-draft.1)

These files are fixed examples of the name context that a Morphir file can carry: a single-file model or one
manifest, module, type or value file of a document tree, wrapped in an envelope with file-local name tables. The
contract is the `ir/name-compaction` requirement set in
`openspec/changes/add-bounded-model-access/specs/ir/name-compaction/spec.md`. The envelope's JSON Schema is
`website/static/schemas/ir-context/0.1.0-draft.1/document.schema.json`, published as
`https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json`. The examples are data for readers
in other repositories, which pin them with their own provenance. They are not kit cases.

## The envelope

```json
{
  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
  "context": {
    "names": { "t": "invoice-line" },
    "fqNames": { "i": "morphir/SDK:basics#int" }
  },
  "document": { "formatVersion": 4, "name": { "$name": "t" }, "...": "..." }
}
```

- `$schema` identifies the envelope. A top-level `$schema` marks a file as an envelope, because no plain Morphir
  document has that member. A reader refuses a URL it does not declare.
- `context` holds up to four tables, `names`, `packagePaths`, `modulePaths` and `fqNames`. Each maps an alias id
  (ASCII letters and digits, starting with a letter) to the fully expanded canonical spelling of its type: a name such
  as `invoice-line`, a path such as `my-org/billing`, or an FQName such as `morphir/SDK:basics#int`. A missing table is
  empty. The same id may appear in two tables; a position resolves only through its own table.
- `document` is the ordinary document, keeping its own `formatVersion`. At a typed name position, the reference
  `{"$name": "<id>"}` may stand for the spelling. Expansion writes the spelling as the document's version writes that
  position: a canonical string in v4 and in the envelope members of a v3 tree file, classic word arrays in a classic
  v3 slot.
- `critical` (optional) lists member paths the reader must understand. Draft.1 recognizes `$schema`, `context`,
  `context.names`, `context.packagePaths`, `context.modulePaths`, `context.fqNames`, `critical` and `document`.
- Unknown optional members of the envelope and of `context` are ignored.
- `context` comes before `document`. A whole-file reader refuses a file where it does not.

The YAML spelling uses the same envelope members and the explicit YAML data model. In
[the YAML type-file example](valid/v4-type.yaml), the `name` mapping is written as:

```yaml
name:
  $name: t
```

The reader resolves `t` through `context.names`, yielding `invoice-line`. The JSON and YAML examples expand to
the same plain document. A contextual YAML reader applies the [YAML reader restrictions](../../schemas/v4/yaml-profile.md#reader-restrictions)
before resolving the Morphir references.

## Limits

A reader refuses a context that exceeds either limit, before it expands any reference. A writer never exceeds them.

| Limit | Value | Diagnostic |
| --- | --- | --- |
| Entries in one table | 16,384 | `context.too_many_entries` |
| UTF-8 bytes of one expanded spelling | 1,024 | `context.name_too_long` |

- **16,384 entries per table.** The largest model in this repository, `website/static/ir/examples/v3/lcr-morphir-ir.json`
  (3.5 MB), uses 917 distinct names and 839 distinct FQNames, so the limit leaves about 18 times that headroom for one
  file while capping what a hostile table makes a reader index.
- **1,024 bytes per spelling.** The longest FQName in that model is 210 bytes, so the limit is about five times the
  longest real spelling, and with the entry limit it bounds a table's spellings at 16 MiB.

Spellings are ASCII, so their UTF-8 byte length is their length in characters. Context bytes also count toward the
reader's limit on the size of the file.

## Diagnostics

| Diagnostic | Rule |
| --- | --- |
| `context.undeclared_schema` | `$schema` is not a URL the reader declares |
| `context.after_document` | `document` comes before `context` (a whole-file reader refuses it; bounded reading may accept it later) |
| `context.invalid_envelope` | The envelope has no `context` or no `document`, either is not an object, or `critical` is not an array of strings |
| `context.duplicate_entry` | A table, the context or the envelope has the same member twice |
| `context.unknown_critical` | `critical` names a path draft.1 does not recognize |
| `context.too_many_entries` | A table has more than 16,384 entries |
| `context.name_too_long` | An expanded spelling is longer than 1,024 bytes |
| `context.invalid_entry` | A table is not an object, an alias id is not ASCII letters and digits starting with a letter, or a spelling is not a string or not a spelling of its table's type |
| `context.unknown_alias` | A reference's id is not in the table of its position |

## The cases

`cases.json` lists every example: its `file`, IR version (`ir`), file `kind`, the `expected` outcome (`valid` or the
diagnostic) and `schemaValid`, whether the envelope schema alone accepts it. A valid case names its `expanded` twin,
the plain document a reader must produce. Every case uses one small model: package `my-org/billing`, module
`invoicing`, the record type `invoice-line` and the value `line-total`, which multiplies two of its fields with
`morphir/SDK:basics#multiply`.

| Case | What it shows |
| --- | --- |
| `valid/v4-single-file.json` | A v4 `Library`: a package path, and FQNames in record fields, an input type, an output type and a value reference |
| `valid/v4-manifest.json` | Package paths in `package` and `dependencies` |
| `valid/v4-module.json` | A module path and names in `types` and `values`; a `critical` list; an unknown optional `context.prefixes`, ignored |
| `valid/v4-type.json` | A name in `name` and one FQName used twice |
| `valid/v4-value.json` | The id `a` in both `names` and `fqNames`, resolved by position; a doc string holding the text of a reference, kept |
| `valid/v3-single-file.json` | A classic v3 `Library`: every table, each expanding to classic word arrays |
| `valid/v3-manifest.json` | A v3 tree manifest: package paths expand to canonical strings |
| `valid/v3-module.json` | A v3 tree module manifest: canonical strings |
| `valid/v3-type.json` | One table feeding a canonical-string position (`name`) and classic slots (a field name, FQNames) |
| `valid/v3-value.json` | Classic FQName slots and variable names |
| `invalid/undeclared-schema.json` | An `ir-context` version the reader does not declare |
| `invalid/unknown-alias.json` | A reference to `zz`, which no table defines |
| `invalid/duplicate-entry.json` | `fqNames` defines `i` twice; JSON Schema cannot see it |
| `invalid/unknown-critical.json` | `critical` names `context.prefixes` |
| `invalid/too-many-entries.json` | A `names` table of 16,385 entries |
| `invalid/name-too-long.json` | A 1,025-byte name |
| `invalid/context-after-document.json` | `document` before `context` |
| `invalid/critical-not-a-list.json` | `critical` is the string `"context.names"`, not an array |
| `invalid/mixed-case-entry.json` | `fqNames` maps `i` to `morphir/Sdk:basics#int`, whose segment `Sdk` is neither a word nor an initialism; the envelope schema refuses it too |

The invalid cases change one thing each in `valid/v4-type.json`. `bun run tools/check-ir-context.ts` checks that every
case is what `cases.json` says, and `bun test tools/check-ir-context.test.ts` runs it with checks that it can fail.
Each valid JSON example also has a `.yaml` twin with the same stem. The tests check that every YAML twin maps to
the same envelope members in order, preserves the numeric tokens, and passes the published envelope schema.

## What these examples do not cover

Reading one name without building the document, accepting a context after the document through bounded spill, and
passing unknown optional members through byte for byte belong to bounded model access (tasks 2.2 and 2.3 of
`add-bounded-model-access`), not to these whole-file examples. The writer policy and its fixed bytes are in `../policy/morphir.compact-0.1.0-draft.1/`.

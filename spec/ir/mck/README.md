# Morphir Compatibility Kit (MCK)

This directory is the Morphir Compatibility Kit: the executable contract for the Morphir IR serialization profiles.
Every binding (TypeScript, Gleam, Python, and later Scala and Rust) is driven through it by the mck driver in
finos/morphir-typescript. A binding is MCK-compatible at a kit version when the driver reports no failures against it.

The kit states meaning by example. The semantic model lives in TypeScript; the YAML profile is the reference
text form; JSON is the second profile. When a spec page and a kit case disagree, the case wins and the page is
corrected. Design rationale is in `kb/bundles/morphir/morphir-ir/ir-v4-stabilization.md`.

## Files

| File | Holds |
| --- | --- |
| `names.md` | canonical strings, legacy arrays, document-tree escapes |
| `types.md` | type expressions |
| `values.md` | value expressions |
| `patterns-and-literals.md` | patterns and literals |
| `definitions.md` | type and value specifications and definitions, access, docs, annotations |
| `distributions.md` | whole Library, Specs, and Application documents |
| `document-tree.md` | manifest, module, and node files; layout equivalence |
| `versions.md` | cross-version reading and writing |
| `documents/` | large fixtures referenced by path |
| `report.schema.json` | the JSON Schema of an MCK report |

## A case

An H2 is one case. The heading is `## <topic>-<NNNN>: <title>` with optional keys in braces:

```markdown
## types-0007: Type reference with one argument {node=Type version=4}
```

- `<topic>` is the file's name without `.md`. `NNNN` is four digits, zero-padded. An ID is assigned once and is
  never reused or renumbered; gaps are fine. Beads, decision records, and reports cite cases by ID.
- Keys: `node=<Kind>` names the model type the fences decode to. `version=<N>` pins the IR version (default: the
  current version). `status=pending` marks a case whose canonical spelling is not decided yet. `compare=attributes`
  compares values with attributes instead of after `stripAttributes`.
- Text after the heading is prose. Say why the case exists and which decision or bead it closes.

## Fences

Fences are the data. The info string is `<language> <role> [key=value ...]`.

| Role | Meaning | Keys |
| --- | --- | --- |
| `canonical` | The spelling a writer must emit for this profile. At most one per language per case. | none |
| `accepted` | A spelling a reader must normalize to the same value as `canonical`. | none |
| `rejected` | A spelling a reader must refuse with the named diagnostic, or decode as a different node. | exactly one of `diagnostic=<code>` or `expect=<Kind>` |
| `file` | One document of a multi-file input (a document tree). | `path=<logical path>` required; `set=<name>` groups files |

Languages are `yaml`, `json`, and `text` (a list of paths, one per line, relative to the repository root; the
kit's own fixtures live under `spec/ir/mck/documents/`). In a report, a text fence takes the profile of the
file's extension: `.json` is `json`, `.yaml` or `.yml` is `yaml`. A fence with any other info string, such as a
`ts` illustration, is prose and is ignored.

A fence whose info string is only a language, such as a bare `yaml` or `json` block, is an illustration and is
ignored by the parser. Pending cases use these to show the spellings under discussion.

```yaml canonical
Reference: ["morphir/SDK:list#list", a]
```

```json accepted
{ "Reference": { "fqname": "morphir/SDK:list#list", "args": ["a"] } }
```

```yaml rejected expect=Tuple
["morphir/SDK:list#list", a]
```

## What the driver does with a case

1. Decodes `canonical` and every `accepted` fence; every result re-encoded canonically must be byte-equal to the
   others and to the `canonical` fence of the same profile (one trailing newline allowed).
2. Decodes every `rejected` fence and requires the named diagnostic, or the named node kind for `expect=`.
3. Builds each `file` set into a document tree, reads it, and compares with the case's `canonical` single-file
   document; writes it back and compares the emitted files with the fences.
4. Reports a `pending` case as `skipped`. A case whose fences are all `rejected` is active and is checked normally.

## Errors the parser reports

Running `mck check spec/ir/mck` fails on: a malformed or duplicate ID; an ID whose topic does not
match the file; an unknown heading key or value; a data fence before the first case; more than one `canonical` per
language in a case; an active case that has `accepted` or `file` fences but no `canonical`; a case with no data
fences at all; a `pending` case carrying anything but `rejected` fences; an unknown language, role, or key; a
`rejected` fence without exactly one of `diagnostic` and `expect`; a `file` fence without `path`; an unterminated
fence; a fence key without a value or with a duplicate key. Nothing is skipped silently.

## Adding a case

1. Pick the file by topic and the next unused number in that file.
2. Write the prose: why the case exists, and the decision or bead it belongs to.
3. Write the YAML `canonical` fence first, then the JSON one, then every `accepted` spelling the profile allows,
   then `rejected` spellings with their diagnostic.
4. Run `mise run mck:check`.
5. If the case decides something that was open, record the decision in
   `kb/bundles/morphir/morphir-ir/decisions/` and close its bead.

# Morphir Compatibility Kit (MCK): IR suite

This directory is the IR suite of the [Morphir Compatibility Kit](https://github.com/finos/morphir/blob/main/spec/mck/README.md): the executable contract for the Morphir IR serialization profiles.
The native `morphir mck` runner drives each binding through an explicit external adapter. Parent CI
runs the TypeScript and Rust adapters. An IR compatibility claim names the kit version and required capabilities; every required case must pass.
Unsupported capabilities can be reported as skipped, so a successful driver exit alone does not prove complete coverage.
The MCK package suite has its own operations and compatibility requirements.

Ownership of the driver moved to this repository on 2026-09-18. The Rust CLI now implements kit
checking, vendoring, runs, vocabulary coverage, offline schema gates, draft report checking and optional
HTML rendering. Historical parity evidence remains frozen. Package integrity and resolution suites also use the native runner under #852. TypeScript retains its independent adapter and draft.3 assurance/publisher helpers. See the
[MCK overview](https://github.com/finos/morphir/blob/main/spec/mck/README.md#ownership-and-transition).

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
| `report-draft.schema.json`, `report-draft.example.json` | production consolidated report `2.0.0-draft.1` and example |
| `report.schema.json`, `report.example.json` | historical version 1 evidence for parity only |
| `allowed-failing.json` | empty parent baseline for the TypeScript adapter gate |
| [`metadata-contract-draft.json`](metadata-contract-draft.json) | fixed reference expectations for future linked metadata; not yet executable support |
| [`protocol.schema.json`](protocol.schema.json) | the JSON Schema of the adapter protocol, contract version 1 |

The [draft node-address reference corpus](../../../docs/spec/ir/fixtures/node-addresses-draft.json)
records V3/V4 URI parsing, legacy sidecar-key conversion, sidecar roundtrips,
layout equivalence and resolution expectations for [#957](https://github.com/finos/morphir/issues/957).
The separate [executable node-address corpus](node-address-draft.json) runs fixed
V3/V4 JSON artifacts through the draft `node-address` adapter suite and checks
both outcomes and resolved semantic nodes. The version-1 IR adapter protocol is
unchanged. The shared `morphir mck` runner remains the sole compatibility runner;
reference-only cases do not count as executable evidence.

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
| `accepted` | A spelling a reader must normalize to the same value as `canonical`. With `warning=<code>` the reader must also report exactly that warning diagnostic (the one-release window of decision 0006); without it the reader must accept silently. | optional `warning=<code>` |
| `rejected` | A spelling a reader must refuse with the named diagnostic, or decode as a different node. | exactly one of `diagnostic=<code>` or `expect=<Kind>` |
| `file` | One document of a multi-file input (a document tree). | `path=<logical path>` required; `set=<name>` groups files; `mode=read` optional |

A `file` set may be written in either profile: every fence of a set is `yaml` or every fence is `json`, and the
set is read and written back in that profile. A set's logical paths carry no extension; the profile supplies
`.yaml` or `.json` at the physical boundary. The driver stays profile-agnostic about one value it needs before
decoding anything: it reads `pathBudget` **lexically** out of the set's `manifest` fence, with one expression
that matches both spellings (`"pathBudget": 4000` and `pathBudget: 4000`). A `file` set whose manifest has no
readable budget is a `kit-error`.

`mode=read`: the set is read and compared, never written back; every fence of a set carries it or none. It marks
a set whose input a conforming writer never reproduces — `document-tree-0005`, whose files carry `$meta` members
that readers ignore and writers never emit.

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

Run `morphir mck run --kit spec/ir/mck --adapter <exe>` against a binding. There is no implicit binding
or in-process fallback. The runner performs these steps against the cases:

1. Decodes `canonical` and every `accepted` fence; every result re-encoded canonically must be byte-equal to the
   others and to the `canonical` fence of the same profile (one trailing newline allowed).
2. Decodes every `rejected` fence and requires the named diagnostic, or the named node kind for `expect=`.
3. Builds each `file` set into a document tree, reads it, and compares with the case's `canonical` single-file
   document; writes it back and compares the emitted files with the fences.
4. Reports a `pending` case as `skipped`. A case whose fences are all `rejected` is active and is checked normally.

Before any of that, the driver asks the testee for its `capabilities`: its `formatVersions`, the binding's
support table in canonical interval notation (see the format-version page, Recognition and compatibility), and
the IR versions, profiles, layouts, paths, and node kinds it supports. A fence whose case needs a version, profile, layout, path, or node the
testee did not declare is reported `skipped` rather than run; an adapter that never learned YAML, for example,
skips every YAML fence without failing the run. The wire shape of `capabilities` and every other exchange is
the adapter protocol, `protocol.schema.json`, contract version 1.

## Running the driver against a binding

From the parent checkout, run the native CLI and check the resulting JSON:

```sh
morphir mck run --kit spec/ir/mck --adapter ./my-adapter --report report.json
morphir mck report check report.json allowed-failing.json --kit spec/ir/mck
morphir mck report render report.json --format html --output report.html
```

`mise run mck:run` and `mise run mck:run-rust` build and use the native runner for the two parent CI
adapters, with native coverage and report checking. Use `morphir mck schema check --kit spec/ir/mck`
for the offline schema/example gate. A binding adopting a released CLI
can use `morphir mck kit vendor` to pin a kit snapshot; release and binding CI cutover is tracked in
[the migration plan](../../mck/migration.md), separately from parent authoring-gate adoption.

The consolidated JSON contains provenance, complete negotiated capabilities, explicit selection,
session outcome and ordered records. It is authoritative. HTML is an optional standalone view
that opens offline without a server or CDN. Rendering a report successfully does not establish
passing tests or a valid compatibility claim.

The draft semantic node-address contract has a separate executable suite at
[`node-address-draft.json`](node-address-draft.json). Run it with
`morphir mck node-address run --adapter ./mck-adapter-rust --adapter-arg=--suite --adapter-arg=node-address`.
It uses `0.1.0-draft.1` capabilities and fixed V3/V4 resolve outcomes, leaving this IR
decode protocol's numeric version 1 unchanged. The adapter decodes IR and builds its
index; the shared MCK runner only reads fixture bytes and compares answers.
Resolved cases compare the full normalized semantic node with a fixed corpus
value, as well as its kind and canonical URI; a same-kind wrong target fails.
The [closed wire schema](node-address-protocol.schema.json) describes its JSON-lines
`capabilities`, `resolve`, and `exit` requests and resolved/failure responses.
`resolve.input` is the exact UTF-8 text of one V3 or V4 single-file JSON artifact;
`resolve.uri` is a portable Morphir node URI. A successful response contains a
node kind, canonical URI, and normalized semantic node. A failure contains one
specific resolver outcome. The first suite covers JSON artifact inputs; the
core index separately tests equivalent V4 JSON, YAML, and document-tree layouts.

`report check` strictly validates the draft schema without remote references, then independently
loads the kit and verifies the snapshot digest and exact record inventory. Missing digest or a
failed adapter session cannot pass. By default it requires a full-kit report; checking a filtered
report requires the same independently supplied `--filter` pattern. Failure allowances are checked
in both directions, so regressions and stale allowances fail. A development baseline is not a
compatibility certificate, and capability skips still limit the claim with an empty baseline.

The report version is the string `2.0.0-draft.1`; the adapter protocol remains integer version 1.
Stable `2.0.0` needs an explicit stabilization decision, without an indefinite old-draft support
promise. The legacy report and provenance-sidecar schemas remain only for historical evidence.

## Errors the parser reports

Running `morphir mck check spec/ir/mck` fails on: a malformed or duplicate ID; an ID whose topic does not
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
   A legacy spelling that decision 0006 keeps for one release is an `accepted` fence with `warning=legacy_spelling`; at the release that closes the window it becomes `rejected diagnostic=unknown_member`.
4. Run `mise run mck:check`.
5. If the case decides something that was open, record the decision in
   `kb/bundles/morphir/morphir-ir/decisions/` and close its bead.

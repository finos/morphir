---
title: The compatibility kit with Ion as the reference encoding
sidebar_label: MCK Ion reference
sidebar_position: 2
status: draft
tracking:
  github_issues: [946]
  beads: [morphir-vvgi.9]
---

# The compatibility kit with Ion as the reference encoding

> **Builds on:** [A Gherkin foundation for Morphir verification](./gherkin-foundation.md). By the time this draft is built, the kit's cases are plain `.feature` suites that run through `morphir-bdd`. A case is a scenario, and its options are tags (`@node:Value`, `@version:4`). Its checks are steps whose doc strings hold the documents. This draft uses that form throughout.

This draft changes how the Morphir Compatibility Kit (MCK) states a case. Today most cases spell one document once for each profile. The change makes Ion the kit's reference encoding and adds `ion` as a profile. Each case says one of two things. A **spelling case** says how a node shape is written in each format. A **semantic case** says what a document means, and it says it once, in Ion. The runner checks every other format by a round trip. The kit also gets an HTML report for a run, and CI shows each run's results.

A mismatch now reports a git-style unified diff, not only the first line that differs.

This draft covers the primitives. Moving the existing cases to spelling and semantic cases, and the Ion sweep of bead `morphir-vvgi.9` (Ion-only cases, the Ion diagnostics table, and removal of the hand-copied fixture in morphir-rust), follow on top of it.

## Why

Three problems come from the same cause:

- **Repetition.** 105 of the 131 cases spell the same document twice, as YAML and as JSON canonical spellings. The runner compares strings line by line and never parses a document (`crates/morphir-mck/src/ir/compare.rs:14-46`). So every profile needs its own spelling in every case.
- **A new profile costs a copy of the kit.** Ion is not a kit profile. `Profile` is the closed set `["json", "yaml"]` (`spec/ir/mck/protocol.schema.json:7`). morphir-rust tests Ion against 84 JSON documents that were copied by hand from the kit at one commit (`crates/morphir-common/tests/fixtures/ion/mck-canonical-cases.json`). Nothing checks that copy for drift.
- **Two jobs in one case.** A case such as `values-0003` shows the canonical spelling of a node in each format, and it also checks meaning. The deeper cases repeat the spelling but add only meaning.

## Today

`values-0003` from `spec/ir/mck/values.md`, in the kit's custom grammar:

````markdown
## values-0003: Reference shorthand {node=Value}

```yaml canonical
Reference: morphir/SDK:basics#add
```

```json canonical
{ "Reference": "morphir/SDK:basics#add" }
```

```json accepted
"morphir/SDK:basics#add"
```
````

The runner sends each canonical and accepted document to the adapter in its own profile and compares the answer with the canonical document of that profile. The [foundation draft](./gherkin-foundation.md#the-compatibility-kit-on-gherkin) moves this case to a `.feature` file unchanged in meaning.

## Design

### Profiles

`Profile` becomes `ion | json | yaml` in the protocol schema and in the engine's `Profile` and `RecordProfile` types. The kit's steps accept `ion` as a doc-string content type. An adapter declares the profiles it reads and writes in `capabilities.profiles`, as today. The Rust adapter declares `ion`. An adapter that does not declare `ion` never receives Ion input.

The change is not additive for a published driver. A v1 driver reads `Profile` as the closed set `json | yaml` (`crates/morphir-mck/src/transport/protocol.rs`), so a capabilities answer that lists `ion` fails its negotiation. So the protocol moves to `contractVersion` `2`:

- **The capabilities request** carries the driver's `contractVersion`. A v1 driver sends none.
- **An adapter** lists `ion` in `capabilities.profiles` only when the request carries `contractVersion` `2` or later. For a v1 driver it answers exactly as today.
- **A v2 driver** accepts an adapter that answers with `contractVersion` `1`, and never sends that adapter Ion.

No published driver or adapter breaks. An old driver sees no `ion`, and an old adapter never receives Ion.

### Two kinds of case

A tag names what a case asserts. Tags are native Gherkin, so any Gherkin tool can filter by them.

| Tag | Asserts | Steps |
| --- | --- | --- |
| `@spelling` | How one node shape is canonically written in each format | Only canonical-spelling steps, usually one outline with a row per format, at most one per format. Each is pinned byte for byte. |
| `@semantic` | What a document means: its canonical form, the spellings a reader accepts, and the diagnostic that refuses the rest | Accept, reject and tree-file steps in any format, usually as outline rows. A case that has an accept step or a tree read-back step has exactly one "Given a &lt;Node> whose canonical form is:" step with an `ion` doc string, because those steps compare with it. A case with only reject or reads-as steps has none |

A spelling case may leave out a format. The runner then reports that format as `not-pinned`, not as a pass. A case with neither tag keeps its behaviour from the foundation's conversion, so the kit stays valid while the cases move over.

`values-0003` as a spelling case, and a semantic case that uses the same shape (sketch). Both are scenario outlines: one check over several formats, or over several inputs. Each `Examples` row runs as its own scenario and gives one report record.

```gherkin
@node:Value @version:4
Feature: Values

  @spelling
  Scenario Outline: values-0003 Reference shorthand
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling                                   |
      | Ion    | (ref 'morphir/SDK:basics#add')             |
      | YAML   | Reference: morphir/SDK:basics#add          |
      | JSON   | { "Reference": "morphir/SDK:basics#add" }  |

  @semantic
  Scenario Outline: values-0031 A reference is read from its other spellings
    Given a Value whose canonical form is:
      """ion
      (ref 'morphir/SDK:basics#add')
      """
    Then a reader of <format> accepts <input>

    Examples:
      | format | input                                                                    |
      | JSON   | "morphir/SDK:basics#add"                                                 |
      | JSON   | { "Reference": { "attributes": {}, "fqname": "morphir/SDK:basics#add" } } |

  @semantic
  Scenario Outline: values-0032 A malformed reference is refused
    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input                                              | diagnostic     |
      | JSON   | { "Reference": "morphir/SDK:basics#add", "x": 1 }  | unknown_member |
      | YAML   | Reference: not-a-name                              | invalid_name   |
      | Ion    | (ref 42)                                           | invalid_type   |

  @semantic
  Scenario Outline: values-0033 A tuple spelling is not a reference
    Then a reader of <format> reads <input> as a <node>

    Examples:
      | format | input                               | node  |
      | YAML   | [ morphir/SDK:basics#add ]          | Tuple |
```

The kit's steps (a step library in `morphir-mck`; `<format>` is `Ion`, `YAML` or `JSON`, and `<Node>` is a node kind such as `Value`):

| Step | Checks | Old fence role |
| --- | --- | --- |
| `Given a <Node> whose canonical form is:` with an `ion` doc string | Sets the case's reference document | none (new) |
| `Then its canonical <format> spelling is <spelling>` or `…is:` with a doc string | A writer emits exactly this spelling | `canonical` |
| `Then a reader of <format> accepts <input>` | A reader reads the input as the canonical form, with no warning | `accepted` |
| `Then a reader of <format> accepts <input> with warning <code>` | The same, and the reader reports exactly that warning | `accepted warning=` |
| `Then a reader of <format> rejects <input> with <diagnostic>` | A reader refuses the input with that diagnostic | `rejected diagnostic=` |
| `Then a reader of <format> reads <input> as a <Node>` | A reader decodes the input as a different node kind | `rejected expect=` |
| `Given the tree file "<path>" in set "<set>":` with a doc string | Adds one file to a document-tree set | `file path= set=` |
| `Then the <set> tree reads back as:` / `…is refused with <diagnostic>` | Reads the set as a tree, and compares the result or the refusal | `file` sets with `canonical` or `rejected` |

Each step also takes a doc string in place of its last inline argument, for documents that span several lines.

A case can also check part of a larger document. It reads a whole document or tree through the adapter, then selects one node by node address, legacy NodeID, selector or relative step, and checks that node. The source, selection and filter steps come from `morphir-inspect` ([ingesting and selecting](./syntax-and-inspect.md#morphir-inspect-ingesting-and-selecting)); the kit supplies the adapter as the source:

```gherkin
Scenario: document-tree-0020 A value inside a v3 tree keeps its body
  Given the tree file "manifest" in set "v3-library":
    """json
    { "formatVersion": "3.1.0", "distribution": "Library", "package": "my-org/my-project", "pathBudget": 4000 }
    """
  And the tree file "pkg/my-org/my-project/domain/total.value" in set "v3-library":
    """json
    { "formatVersion": "3.1.0", "name": "total", "def": { … } }
    """
  When the adapter reads the "v3-library" tree
  And I select the node "morphir://ir/pkg/my-org/my-project#/module/domain/value/total/body"
  Then its canonical Ion spelling is (apply (ref 'morphir/SDK:list#sum') (variable 'orders'))
```

The outline rules for kit cases:

- **One-line documents** go in an `Examples` table. A `|` inside a cell is written `\|`, as Gherkin requires.
- **Documents of several lines** stay as doc strings in plain scenarios, one check per step, because a table cell holds one line.
- **Case ids:** a row's report record carries the case id from the scenario name and the row's position, for example `values-0003 row 2`.

### How the runner checks a semantic case

For each profile P that the adapter declares:

- **P is Ion:** the runner sends the Ion canonical fence and requires the answer to equal it byte for byte.
- **P is another format:** the runner transcodes the Ion reference to P and sends it. It then transcodes the adapter's P answer back to Ion, and requires the result to equal the Ion canonical byte for byte.

```mermaid
sequenceDiagram
    participant K as Kit case
    participant R as Runner
    participant C as Reference codecs
    participant A as Adapter
    K->>R: ion canonical fence
    alt adapter declares ion
        R->>A: decode (ion, fence)
        A-->>R: ion canonical answer
        R->>R: compare bytes with the fence
    else adapter declares only P (json or yaml)
        R->>C: transcode fence to P
        C-->>R: P input
        R->>A: decode (P, input)
        A-->>R: P canonical answer
        R->>C: transcode answer to ion
        C-->>R: ion text
        R->>R: compare bytes with the fence
    end
```

This check is about meaning. P's byte spelling is pinned only by spelling cases. For that reason, the kit does not take morphir-rust's YAML and JSON writers as the standard for every binding.

`accepted` and `rejected` fences run in their own language, as today. When the runner compares an adapter's answer to an `accepted` fence, it transcodes the answer to Ion and compares it with the Ion canonical. If the adapter does not declare the fence's language, the fence is `skipped` with a reason.

The runner transcodes in-process with the morphir-common codecs. The report states the codec version the runner used.

### Failures

| Condition | Record | Blamed on |
| --- | --- | --- |
| The Ion reference fence does not transcode | `kit-error`, with the codec diagnostic | the kit |
| The adapter's answer does not read in its own profile | `fail`, reason `answer-not-readable`, with the diagnostic | the adapter |
| The round-tripped Ion differs from the reference | `fail`, with a unified diff of the two Ion texts | the adapter |
| The adapter declares no profile the case can use | `skipped`, with the reason | none |

### Diffs for a mismatch

Today a mismatch reports only the first line that differs (`check_canonical`, `crates/morphir-mck/src/ir/compare.rs:37-46`):

```text
line 3 differs: expected   name: add got   name: plus
```

Every canonical mismatch now carries a git-style unified diff of the expected and actual text: spelling cases, semantic round trips, `accepted` fences and document-tree files. The diff has `---`/`+++` headers that name the case, fence and profile, three lines of context, and `@@` hunk headers (sketch):

```diff
--- expected values-0003 step 2 (canonical YAML)
+++ actual   morphir-rust (yaml)
@@ -1 +1 @@
-Reference: morphir/SDK:basics#add
+Reference: "morphir/SDK:basics#add"
```

For a semantic round trip the diff compares the two Ion texts, and a note names the profile P that the answer came from. A document-tree mismatch has one diff for each file that differs, headed by the file's logical path.

Where the diff appears:

- **Report:** each failing record gains an optional `diff` member that holds the unified diff text. The first-line `reason` stays, so a short report still reads well.
- **Terminal:** `morphir mck run` prints the diff under each failure, coloured when the output is a terminal.
- **HTML:** each failing cell opens to the diff, with removed and added lines coloured.
- **CI job summary:** the first diffs, up to a size limit, in a fenced `diff` block; the full set is in the artifact.

The engine produces the diff with a line-diff library such as `similar` (none is in the workspace today). The diff is capped in size, and a capped diff says how many lines it left out.

### Grammar checks

`morphir mck check` enforces the new rules:

- A spelling case has only canonical-spelling steps, with at most one for each format.
- A semantic case with an accept step or a tree read-back step has exactly one canonical-form step, and its doc string is `ion`. A semantic case with only reject and reads-as steps has no canonical-form step. No semantic case has more than one.
- A case has at most one of `@spelling` and `@semantic`.
- A tag in the kit's namespaces (`@node:`, `@version:`, `@compare:`) with an unknown value is an error, with the tag's span.

### Report and HTML

Each report record gains an optional `check` member: `spelling`, `semantic` or `round-trip`. It keeps `profile`. A report without `check` reads as `semantic`, which is today's meaning, so `report render` accepts old reports.

`morphir mck run --html <FILE>` writes the HTML report beside `--report`, through the renderer that `morphir mck report render` uses today. The HTML groups records by case and shows a profile matrix: one column for each of Ion, YAML and JSON, and each cell is pass, fail, skip or not-pinned.

### CI

CI already renders the HTML and uploads the JSON and HTML reports on every run: `mck-reports` for the TypeScript binding and `mck-report-morphir-rust` for the Rust binding (`.github/workflows/ci.yml:489-503`, `:529-547`). This draft adds:

- A job summary for each kit run: the counts, the failed case ids, and a link to the artifact. The step runs when the run fails too. A small renderer function writes the summary, and its tests check it.
- The run's transcript in the artifact, beside the JSON and HTML reports.

### Frozen baselines

The parity tests replay recorded transcripts (`crates/morphir-mck/tests/runner_parity.rs`). New checks send new requests. Each change records the Rust transcript again under the append-only rule in `spec/mck/baseline/README.md`: earlier records and exchanges stay unchanged and in order. The TypeScript transcript changes only when TypeScript receives new requests. With transcoding, the TypeScript adapter now runs semantic cases instead of skipping them, so its transcript grows too.

## Testing

- **Engine unit tests:** the grammar rules; transcoding in both directions; each failure kind, with a fake adapter; the unified diff for a canonical, a round-trip and a tree-file mismatch, and the size cap; `--html` output; an old report without `check` or `diff` still rendering.
- **Kit gates:** `mck:run-rust` with `ion` declared; `mck:run` for TypeScript, which runs semantic cases through transcoding.
- **Proof of the primitives:** this work converts a handful of cases, for example `values-0003` into a spelling case and one semantic case. Both paths then run end to end before the rest of the cases move.

## Alternatives considered

- **Keep a canonical fence for each format in every case, and add the round trip only for Ion.** No fence is removed, and each format's spelling is pinned everywhere. It leaves the 105 duplicated cases and the per-node repetition in place.
- **Require every adapter to read Ion.** Simpler, because the runner does not transcode. But the TypeScript adapter, which does not read Ion ([finos/morphir-typescript#36](https://github.com/finos/morphir-typescript/issues/36)), would skip almost the whole kit.
- **Compare the adapter's answer with the reference codec's spelling in P, byte for byte.** Every case would pin every format's spelling. But the kit would take morphir-rust's writers as the standard for every binding.
- **Keep JSON as the reference until every adapter reads Ion.** JSON is the most familiar format to readers. But the kit wants to move to Ion anyway, and transcoding already removes the adapter requirement.

## Open questions

- **Which cases are spelling cases?** The move of the existing cases must list them from each profile's written rules: one case for each rule, not one for each node. That list is how the kit keeps the clarity of "this is how you encode this shape in this format".
- **How are Ion fences pinned byte for byte?** They depend on a canonical Ion text writer. The Ion draft (`docs/design/draft/ir/ion.md`) must say which writer settings (spacing, symbol quoting, struct order) are canonical before the first `ion canonical` fence is frozen.

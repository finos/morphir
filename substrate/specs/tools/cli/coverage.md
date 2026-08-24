# Coverage

The `substrate coverage` command analyses one or more substrate documents and
reports how they relate to the language specification. It answers two
complementary questions in a single run:

- **What language features does this document exercise?** — the set of spec
  sections the document touches, both through its parsed structure and through
  the links in its prose.
- **How much of this document is recognised as substrate?** — the share of the
  document that the language understands semantically, as opposed to plain
  prose that passes through unchanged.

The same command, run over the `examples/` directory or any other corpus,
aggregates these per-document numbers into a coverage profile for the language
as a whole.

## Synopsis

```
substrate coverage [<path>...] [--format <format>] [--against <glob>]
```

With no arguments, `substrate coverage` analyses the current package. One or
more paths may be given to restrict the analysis to specific files or
directories.

### Arguments

| Argument   | Description                                                                                  |
| ---------- | -------------------------------------------------------------------------------------------- |
| `<path>`   | A file or directory to analyse. Directories are walked recursively for `.md` files.          |

### Options

| Option                | Description                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------ |
| `--format <format>`   | Output format: `text` (default, human-readable), `json` (machine-readable), or `markdown` (report document). |
| `--against <glob>`    | The spec corpus to measure against. Defaults to the language spec installed for the current package.         |

## What the command measures

`substrate coverage` reports three metrics per input document, plus one
aggregate metric across the input set.

### 1. Structural coverage — what the parser saw

The pipeline parses, typechecks, and (where applicable) evaluates each input.
Every AST node it produces corresponds to a language construct, and every
language construct has a canonical home in the spec — by convention, the path
of the spec file plus the anchor of the section that defines it.

Structural coverage lists the spec anchors reached by at least one AST node in
the document. It is the most trustworthy of the three metrics: a construct
either appeared in the parsed tree or it did not.

Three sub-totals are reported, because the parser, the typechecker, and the
evaluator can each accept or reject a construct independently:

- **Parsed** — the parser produced a typed node.
- **Typechecked** — the typechecker accepted the node.
- **Evaluable** — the evaluator could execute the node (only meaningful for
  expressions and operations).

The gap between *parsed* and *typechecked* is the list of features the
language can read but not yet understand; the gap between *typechecked* and
*evaluable* is the list it understands but cannot yet run. Both gaps are
useful as a development backlog in their own right.

### 2. Narrative coverage — what the prose claims

Independently of the parser, the command collects every link in the document
whose target resolves to a section of the language spec. These are the
features the document explicitly *claims* to be about — typically appearing in
introductory prose, headings, or "see also" lists.

Narrative coverage is the set of spec anchors reached by these links.

### 3. Divergence — claims vs. reality

The command reports two divergence lists:

- **Claimed but not used** — spec anchors linked from the prose that no AST
  node in the document corresponds to. Either the link is decorative, the
  example does not actually exercise the feature, or the feature is named in
  the prose but absent from the body.
- **Used but not claimed** — spec anchors reached by the parser that no link
  in the document mentions. The example is exercising features it does not
  advertise. For an example written as documentation, this usually indicates
  missing cross-references.

Divergence is reported per document; neither list is treated as an error by
default, but `--format json` exposes them so tooling can fail a build on
either condition.

### 4. Recognition — language vs. prose

A substrate document is markdown with islands of language content. Recognition
measures the share of the document that the language interpreted as a known
construct, as opposed to plain prose that was passed through unchanged.

Recognition is reported as three percentages over the same denominator
(non-trivial AST nodes of the markdown tree):

- **Parsed %** — share of nodes that the substrate parser claimed as a known
  construct.
- **Typechecked %** — share of nodes the typechecker also accepted.
- **Evaluable %** — share of nodes the evaluator could execute.

Whitespace, headings used purely as structure, and other syntactically empty
nodes are excluded from the denominator.

The command additionally flags **suspicious unrecognised regions** — markdown
constructs that look like they were intended to be language content but did
not match any known pattern. The current heuristics are:

- Code fences whose info string is a non-empty token that does not correspond
  to a documented expression form.
- Definition-style list items, tables, or admonitions that follow the shape
  of a known construct but fail to parse.

Each suspicious region is reported with file, line, and a one-line excerpt.
These are the most direct source of new-feature proposals.

### Aggregate coverage of the language

When more than one input is analysed, the command also reports the union of
structural coverage across all inputs as a percentage of the spec's total
addressable anchor set. The denominator is the set of spec sections under
`specs/language/` (or the corpus given by `--against`) that are marked as
normative — that is, sections that define a language construct, as opposed to
explanatory prose, design notes, or appendices.

A section is treated as normative when its file path lives under a normative
subtree of the spec (for example, `specs/language/expressions/` and
`specs/language/concepts/`); the exact rule is part of the spec's own
configuration and is not hard-coded in the tool.

## Output

### Text format

```
$ substrate coverage examples/assessment-grading-pipeline.md

examples/assessment-grading-pipeline.md
  recognition          parsed 78%  typechecked 71%  evaluable 64%
  structural           17 anchors reached
  narrative            12 anchors linked
  claimed but unused   2  (specs/language/expressions/let.md#shadowing,
                          specs/language/concepts/pipeline.md#error-handling)
  used but unclaimed   7  (run with --format markdown for details)
  suspicious regions   1  line 84: ```pipeline:strict  (unknown info string)

language coverage (1 file)
  structural / normative anchors    17 / 92   (18.5%)
```

### JSON format

`--format json` emits one object per input plus a top-level `aggregate` field.
Each per-input object exposes the four metrics as arrays of anchor strings
(e.g. `specs/language/expressions/let.md#binding`) and counts. The shape is
intended to be stable enough to drive CI checks.

### Markdown format

`--format markdown` emits a coverage report suitable for committing to a
package's documentation. It is the format used by the `coverage` horizontal
that ships with the language spec.

## Conventions this command depends on

`substrate coverage` does not introduce new metadata. It relies on two
existing conventions of the project:

1. **Spec anchors are stable IDs.** Every language construct is defined in a
   single section of the spec, identified by its file path plus its GitHub-
   Flavoured Markdown anchor. The `refactor rename` command exists precisely
   to keep these identifiers stable across edits.
2. **AST node kinds correspond to spec sections by name.** The mapping from a
   parsed node to a spec anchor is derived from the node's kind, not from
   per-section frontmatter. When a node has no corresponding spec section the
   tool reports it as *implemented but undocumented*, which is itself a useful
   signal.

Both conventions are properties of the language and its specification, not of
the coverage tool; the tool only reads them.

## Exit status

By default, `substrate coverage` exits with status 0 regardless of the numbers
it reports — it is a measurement, not a gate. CI integrations should use
`--format json` and apply their own thresholds.

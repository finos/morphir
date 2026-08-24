# `substrate write`

Embed substrate constructs into existing markdown documents.

This is the write-side counterpart to the dev viewer's read-side
rendering: an LLM (or human) hands the CLI a snippet of substrate YAML
and points it at a section anchor, and the CLI splices the snippet into
that section, replacing any existing block in place.

## Synopsis

```bash
substrate write interpretation <file> <anchor> < snippet.yaml
```

## `substrate write interpretation`

Read substrate YAML from stdin and embed it into `<file>` under the
section identified by `<anchor>`.

### Behaviour

- Reads the entire stdin as the YAML payload. Empty input aborts.
- Validates the YAML through the same parser the dev UI uses
  (`src/substrate/parse.ts`). Both YAML syntax errors and substrate
  language errors are surfaced. Any parser diagnostic at `error`
  severity aborts the write with a non-zero exit code; warnings are
  printed but allowed.
- Stamps a fresh `last-interpreted-at` ISO-8601 timestamp directly
  under the `substrate:` mapping in the YAML text. If the input already
  carries a `last-interpreted-at`, it is overwritten. Author formatting
  (comments, key order, indentation) is otherwise preserved — the YAML
  is not round-tripped through the parser/serializer.
- Aligns the markdown file's mtime with the embedded
  `last-interpreted-at` so the dev viewer's staleness check reads
  "up to date" immediately after the write.
- Locates the target section by slugifying every ATX heading in the
  file (GFM convention: lowercase, spaces → `-`, non-alphanumeric
  stripped) and matching against `<anchor>`. A leading `#` on the
  anchor argument is tolerated. Headings inside fenced code blocks are
  ignored.
- The section spans from the matched heading to (exclusive) the next
  heading of equal or shallower depth, or to EOF.
- Within that section, looks for a fenced code block (` ```yaml ` or
  ` ```yml `) whose first non-blank content line begins with
  `substrate:`. If one is found, it is replaced in place. Otherwise a
  new fenced block is appended as the section's last piece of content,
  separated from preceding prose by a single blank line.

### Arguments

| Position | Meaning |
| --- | --- |
| `<file>` | Path (absolute or cwd-relative) to the markdown file. |
| `<anchor>` | Section heading slug, e.g. `overview` or `#overview`. |

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | YAML validated and the file was updated. Warnings may have been printed. |
| 1 | Empty stdin, invalid YAML, missing section, or write failure. |

### Diagnostics

Parser diagnostics are printed to stderr in the form
`SEVERITY <line>:<col> (<path>): <message>`, mirroring the structure
the dev viewer surfaces. The `<path>` segment names mapping keys and
sequence indexes through the offending node.

### Notes

- This command does **not** rewrite cross-document links, manage
  vendored dependencies, or touch any file other than `<file>`. Use
  `substrate refactor rename` for link-aware renames.
- The companion read path is `substrate dev`, which renders the
  resulting block in the interpretation viewer.

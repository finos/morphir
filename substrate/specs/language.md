# Language Specification

This specification organizes the language into modular, human-readable markdown files. Each module describes a distinct aspect of the language, focusing on clarity and traceability.

## [Concepts](language/concepts/)

## [Expressions](language/expressions/)

## Markdown Conventions

### Syntax Policy

Modules use native markdown syntax wherever possible. Extended syntax is
permitted only when it is broadly supported, with GitHub-flavored Markdown
as the primary compatibility target. This keeps modules readable and
renderable with standard tooling.

### Links as Primary Enrichment

Links are the principal mechanism for attaching semantic meaning to a
document. Every reference to a type, operation, or module should be a
relative markdown link to its definition. This turns plain prose into a
navigable semantic graph that both humans and tools can traverse.

### Link References

When the same hyperlink target appears multiple times in a module, prefer
_reference-style link definitions_ over repeating the full inline URL. Place
all link definitions together at the end of the file, one per line, sorted
alphabetically by label:

```markdown
[label]: relative/path/to/target.md
[label2]: relative/path/to/target.md#anchor
```

Then use the label throughout the file:

```markdown
Returns a [Boolean][bool] value.
```

This is not mandatory for links that appear only once, but is encouraged
whenever a target is referenced two or more times in the same file.

### Document Inclusion

A heading whose entire inline content is a single link acts as an
**inclusion heading**: the tooling embeds the linked content as a
subsection, adjusting heading levels to nest correctly. This lets authors
split a growing document across files without losing a unified heading
hierarchy.

#### Sibling Convention

A file and a directory that share a stem name form a pair: `language.md`
and `language/` are siblings. An inclusion heading may only reference
**direct children** of the file's paired directory. Links that do not
satisfy this rule — parent traversals, grandchild paths, external URLs —
are treated as ordinary navigational links without errors or warnings.

For example, `language/expressions/` is a direct child of `language/` and
qualifies, as does any individual file such as `language/expressions/boolean.md`.

#### File Inclusion

The link target is a markdown file:

```markdown
### [Boolean](language/expressions/boolean.md)
```

The file's contents are inserted under the heading with heading levels
adjusted to nest correctly.

#### Directory Inclusion

The link target is a subdirectory:

```markdown
### [Types](language/types/)
```

Every markdown file in the directory is included as a subsection, ordered
alphabetically by filename. Numeric prefixes (e.g., `01-boolean.md`,
`02-integer.md`) control ordering. The same rules apply recursively.

## Alternative Formats

When markdown alone is insufficient for precision or conciseness, alternative
intermediate formats may be used within a module. These may appear as code
blocks inside the markdown file or as separate artifact files referenced from
it. In either case, every alternative-format fragment must carry a provenance
reference --- a link or annotation that identifies the specification section
or operation it belongs to.

## User Modules

User modules are markdown files that describe business logic using the language's building blocks. Business logic is expressed as nested lists:

- The parent item is a reference to an operation (linked to its definition in a type class module).
- Each child item is an argument passed to that operation, which may itself be a nested operation call.

This mirrors function application in a readable, non-syntactic form.

### Example

- [Add](language/expressions/number.md#addition-operation)
  - [Multiply](language/expressions/number.md#multiplication-operation)
    - `unit_price`
    - `quantity`
  - `tax`

This reads as: add the result of multiplying `unit_price` by `quantity` to `tax`.

Leaf values (e.g., `unit_price`) refer to named inputs or constants defined elsewhere in the user module. A [Boolean](language/expressions/boolean.md) value can be used as a condition in the [If-Then-Else](language/expressions/boolean.md#if-then-else-operation) control-flow construct.

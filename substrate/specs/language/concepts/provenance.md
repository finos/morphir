# Provenance

A Provenance section records the authoritative sources from which a
specification artifact derives. Any artifact — a [Record](record.md)
type, a [Choice](choice.md), a [Decision Table](decision-table.md), an
[Operation](operation.md), or a whole module — that encodes material
from an external document should declare its sources in a Provenance
section.

Provenance exists to make traceability explicit and machine-readable.
The rendered markdown remains the specification; the Provenance section
attaches the citations that turn it into an auditable artifact.

A provenance section is identified by a heading whose text is a link to
this concept page:

```markdown
### [Provenance](../concepts/provenance.md)
```

Its scope is the enclosing heading: a provenance section placed under a
specific declaration documents that declaration; one at module level
documents the module as a whole. Multiple provenance sections may appear
in the same document at different scopes.

## Contents

A Provenance section is free-form markdown. The following conventions
apply.

### Sources

At least one link to an authoritative source document is required.
Sources are listed as a bulleted list. Each entry links to the most
specific stable address available — for codified regulations, a deep
link to the cited section; for published rules, a deep link to the
Federal Register or equivalent; for PDFs, a link to the published PDF
with the citation marker (page, section) in the link text.

```markdown
- [12 CFR §249.32(a)(1)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a)(1))
- [Federal Register, Vol. 79, No. 197, pp. 61440–61541 (Oct 10, 2014)](https://www.federalregister.gov/documents/2014/10/10/2014-22520)
```

Multiple sources are allowed and expected: a single rule may derive from
a statute, a codified regulation, an international framework, and
supervisory guidance. Each should be cited distinctly.

### Quoted Passages

When the specification encodes specific normative text, the passage
should be quoted directly using a markdown blockquote, immediately
following the source it is drawn from. A leading reference to the
source identifier makes the quote self-contained.

```markdown
- [12 CFR §249.32(a)(1)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a)(1))

  > A covered company shall apply a 3 percent outflow rate to the
  > amount of FDIC-insured stable retail deposits held by a natural
  > person...
```

Quoted passages are optional but strongly encouraged when the artifact
encodes a specific rate, threshold, classification, or verbatim
obligation. A quote pinned to an artifact protects the spec against
silent upstream drift: a later edit that contradicts the quoted passage
is an observable inconsistency.

### Identifier

When the source is cited by a conventional identifier (a CFR section,
a paragraph number, a Basel paragraph), the identifier should appear in
the link text itself. Readers should not need to dereference the link
to know what is being cited.

## Relationship to Internal Provenance

The [vision document](../../vision.md) describes source-map-like
provenance between structured nodes and the natural-language fragments
they were derived from within the specification. That internal
provenance is a metadata mechanism carried on nodes.

A Provenance section, by contrast, documents **external** sources of
authority — regulations, standards, statutes, published guidance. Both
mechanisms are traceability tools; they operate on different axes and
do not replace each other.

## Example

```markdown
### Retail Outflow Rate [Decision Table](decision-table.md)

#### [Provenance](../concepts/provenance.md)

- [12 CFR §249.32(a)](https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-249/subpart-D/section-249.32#p-249.32(a))

  > Outflow amounts resulting from retail funding.

- [Federal Register, Vol. 79, No. 197, p. 61490 (Oct 10, 2014)](https://www.federalregister.gov/documents/2014/10/10/2014-22520)

  > The agencies are adopting a 3 percent outflow rate for stable
  > retail deposits, a 10 percent outflow rate for other retail
  > deposits, and higher rates for brokered deposits reflecting their
  > reduced stability during periods of liquidity stress.

#### Rules

...
```

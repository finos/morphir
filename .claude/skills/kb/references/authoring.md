# Authoring Concepts

`add-concept` writes the frontmatter and wires up the index and log. This covers the part it cannot do.

The authoritative conventions live in [kb/AGENTS.md](../../../../kb/AGENTS.md); read that first if you are unsure
about the format. What follows is about writing well within it.

## Frontmatter

`type` is the only universally required field, but a concept with only `type` is a poor concept.

| Field | Guidance |
| ----- | -------- |
| `type` | Reuse a type already present in the bundle. Coining `Design Doc` next to an existing `Design Note` fragments the vocabulary for no gain. Use `Glossary` and `Data Dictionary` for term catalogs. |
| `title` | Human-readable. It is what search and indexes display |
| `description` | **One sentence that stands alone.** It appears in the index bullet, in search results, and nowhere near the body that would give it context |
| `tags` | Cross-cutting categories, not a restatement of the title |
| `status` | `draft` when the source itself is a draft, or when the content is unverified |
| `stale_after` | Set it when the source is expected to churn. It is a promise to re-read, not decoration |
| `sources` | Every factual concept should have at least one, with a **commit-pinned** URL |

### Pin your sources

```yaml
sources:
  - id: ir-spec
    resource: https://github.com/finos/morphir/blob/4d5e5c06a7cf269c5f86b050a16a6f82bb5c29bc/docs/spec/ir/morphir-ir-specification.md
    title: Morphir IR Specification
```

A `main` URL tells a future reader nothing about what you actually read. A pinned URL lets them check, and lets
`morphir kb check` detect that upstream has moved. For a source in this repository, the SHA is the current commit:

```bash
git rev-parse HEAD
```

For an external repository, get it from the reference checkout:

```bash
git -C .refs/<org>/<repo> rev-parse HEAD
```

## Writing the body

**Place the document in its capability's story.** Per `altitude.md` in the style cards, every document either
is a capability's narrative home or is linked from one. Before writing a new fine-grained concept, know which
narrative links to it, and add that link in the same change.

**Pick the register first.** The `type:` decides whether the body reads as an article, a white-paper, or a
reference; the routing table is in [SKILL.md](../SKILL.md). Apply the matching card from
[`../styles/`](../styles/), and `voice.md` there in every case. The banned-pattern list in `voice.md`
(em-dashes included) is absolute for new and touched content. When the body describes a flow, structure, or
state machine, follow `diagrams.md` there: a captioned Mermaid diagram or SVG beats paragraphs of narration.

**Open with the answer.** Someone arriving from a search result should learn the thing in the first paragraph. Build
up to it and they will leave first.

**Write for a junior to early mid-level developer.** See `voice.md` Audience. Do not assume PhD-level or deep
domain knowledge. When background is required, include it, summarize it, link a Glossary or Data Dictionary
(same bundle or co-located sibling is enough to skip an inline sidebar), link another kb concept, or (least
preferred) link an external reference.

**Say what is unresolved.** A knowledge base earns trust by being honest about its edges. Where sources disagree,
record the disagreement and say which is authoritative — or that neither is. Where you did not verify something, say
so. A concept that quietly smooths over a contradiction is worse than no concept.

**Prefer tables for enumerable things** — node kinds, field lists, version differences. Prefer prose for anything
with a *because* in it.

**Link the neighbours.** Bundle-relative links (`/naming.md`) beginning at the bundle root are the stable form. A
concept nobody links to and which links to nobody is a leaf that will rot unnoticed.

**Do not restate the source.** If a concept says exactly what the spec says in the same order, it adds nothing over
reading the spec. The value is in structure, cross-references, and the "why" the source assumes you already know.

## Divergence notes

When the concept covers something where sources conflict, or where the specification and an implementation differ,
say so explicitly, in its own section, with both positions. Do not pick a winner unless a source does.

The morphir-scala knowledge base carries the worked example, in its `morphir-ir-v4-draft` bundle
(`ecosystem/morphir-scala/kb/bundles/morphir/morphir-ir-v4-draft/design/divergences.md`).

## After writing

```bash
morphir kb check
```

Then confirm the index bullet still matches your `description` — if you edited the description after scaffolding,
`index-description-drift` will tell you.

## Updating the log

`add-concept` appends a `**Creation**` entry. Substantive later edits deserve an `**Update**` entry saying what
changed and why; a reader of `log.md` should be able to reconstruct how the bundle got to its current state. Follow
the existing date-heading format, newest first.

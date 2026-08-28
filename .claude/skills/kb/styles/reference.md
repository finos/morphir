# Register: reference

For content an agent or person looks things up in: API surveys, version-pinned implementation notes,
specification summaries, mirrored-source companions. Nobody reads it start to finish. Apply
[voice.md](./voice.md) throughout.

## Shape

1. **Answer first.** The single most useful fact of the page goes in the opening paragraph.
2. **Baseline section when versioned.** What version or commit the claims were verified against, where the
   source of truth lives, and what to do when the pin moves. A reference without a pin is a rumor.
3. **Tables for anything enumerable.** Variants, flags, type mappings, version differences. Prose only where
   there is a "because" to carry.
4. **Verbatim artifacts.** Signatures, commands and error strings appear exactly as the source has them, in
   code blocks. Do not paraphrase code.
5. **Citations per claim.** Footnote or inline link to the pinned source file, close to the claim it supports.
6. **Diagrams for structural facts.** State machines, effect-handler nesting, and type relationships read
   faster as Mermaid than as prose; see [diagrams.md](./diagrams.md). Diagrams document the source's shape;
   they never argue for a design.

## Tone

- Minimal connective prose. No narrative, no motivation sections, no direct address.
- Sentence fragments are acceptable inside table cells; complete sentences elsewhere.
- Density is the virtue. If a sentence exists only to bridge two facts, delete it.

## Limits

- If a section starts arguing for a design position, that content wants the
  [whitepaper](./whitepaper.md) register.
- If a section starts teaching a workflow, that content wants the [article](./article.md) register.
- Do not restate the source in the source's order; the value of a reference here is selection, structure and
  cross-links the source lacks.

## Glossary and Data Dictionary

Two `type:` values use this register for term catalogs. They are not narrative homes.

| `type:` | Holds | Typical shape |
| --- | --- | --- |
| `Glossary` | Domain words and short meanings | One heading per term, then a few sentences. Headings make fragment links work. |
| `Data Dictionary` | Named fields, types, flags, columns | A table: name, kind, meaning, constraints. Prose only for a "because". |

Prefer `glossary.md` and `data-dictionary.md` at the bundle root. Split into a directory only when one file would mix unrelated catalogs.

A Design Note or Intent in the same bundle (or a co-located sibling) may link here instead of defining the term inline. That is how those pages keep flow. Do not copy the catalog back onto the narrative page.

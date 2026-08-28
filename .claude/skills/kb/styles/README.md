# Knowledge base style cards

Style cards for writing and reviewing content under `kb/`. They are plain markdown so any agent or editor can
apply them; nothing here depends on a specific AI tool.

- [voice.md](./voice.md) applies to every register: audience (junior to early mid-level), sentence mechanics, vocabulary, and the banned-pattern list. Background may live on the page, in a summary, in a Glossary or Data Dictionary, in another kb concept, or (least preferred) in an external link.
- [diagrams.md](./diagrams.md) also applies to every register: when a Mermaid diagram or SVG clarifies a point
  better than prose, and the rules for using one.
- [altitude.md](./altitude.md) also applies to every register: documents are sized to capability stories, each
  capability in flight has one narrative home, and fine-grained concepts must be reachable from it. Glossaries and
  data dictionaries are an allowed split so narratives do not grow definition sidebars.
- [article.md](./article.md), [whitepaper.md](./whitepaper.md) and [reference.md](./reference.md) are register
  cards. A document gets exactly one, chosen by its `type:` frontmatter.

The routing table from `type:` to register lives in the kb skill
([`../SKILL.md`](../SKILL.md)). Structural conventions (frontmatter,
indexes, links) stay in [`kb/AGENTS.md`](../../../../kb/AGENTS.md); these cards only govern how the prose reads.

Scope: new documents and documents you already touch for another reason. Do not sweep existing content to
retrofit style.

# Altitude

Altitude is the height a document flies at over its subject. A high-altitude document is the 10,000-foot
view: the whole capability visible in one frame, details small but their arrangement clear. A low-altitude
document flies close to the ground: one API, one mechanism, one pinned version, in full detail. Both are
necessary; the failure mode this card exists to prevent is a knowledge base with only low-altitude documents,
where every detail is recorded and no document shows how they arrange into a capability.

This card gives the rules for choosing a document's altitude and for connecting the altitudes. The registers
say how a document reads; this card says what a document is responsible for.

## The capability is the unit of story

Knowledge in this kb exists to unlock capabilities. Every document either tells a capability's story or serves
one that does. A reader who finds any document must be able to reach the story it serves in one link.

- **Each capability in flight has one narrative home**: a Design Note at capability altitude. It states the
  capability in plain words, narrates the research so far with links to the evidence, records the constraints
  adopted, lists what is unresolved, and maps the intents that partition delivery. It updates as understanding
  improves; that is what distinguishes it from a Decision Record.
- **Fine-grained concepts must be reachable from a narrative home.** A pinned reference, a mechanism survey, or
  a comparison document earns its separate existence by being independently reusable or independently
  version-pinned, not by being a fragment. If a document serves a capability and no narrative links to it, fix
  the narrative.
- **An intent is a feature definition, not a ticket.** A reader should learn what the capability delivers and
  why from the intent alone: problem, approach, scope boundary. If the intent only makes sense next to five
  sibling documents, it is too thin.

## When to split, when not to

Split a document only when a piece is one of:

- independently reusable by another capability,
- independently pinned to a version or commit with its own verification cadence,
- owned by a different register (evidence does not live inside an argument; an argument does not live inside a
  reference),
- a Glossary or Data Dictionary of terms the bundle uses. Put term catalogs there so narrative pages do not grow
  definition sidebars. Same bundle is best. A co-located sibling bundle (same grouping directory) is also fine.

Do not split because a document is long, because sections feel conceptually distinct, or to make review
easier. A long document with one responsibility beats three short ones whose story lives in nobody's head.

## When writing or reviewing

- Writers: name the capability the document serves in its opening or its frontmatter links, and link its
  narrative home. When creating a fine-grained concept, add the link from the narrative home in the same
  change.
- Reviewers: flag a concept no narrative reaches, an intent too thin to define its feature, and a narrative
  home that has drifted behind the documents it links.

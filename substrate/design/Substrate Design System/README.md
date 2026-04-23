# Substrate Design System

Substrate is an **LLM-native executable specification language** designed for
spec-driven development. The primary artifact isn't code — it's a markdown
document that is both the human-readable specification and the executable
program. Programs are typed dataflow graphs whose nodes are transformations
and decisions, and whose edges are explicit data contracts. Everything is
traceable to the natural-language fragment it derives from.

The product is deliberately modest in visual scope: the brand is a lattice,
two polylines, and a small green/blue/orange palette. The design system
codifies those primitives and extends them into UI surfaces for the
specification editor, CLI output, and documentation.

---

## Source material

This system was built from the following sources. Links point into the
originals; every asset used here has been copied into the project.

- Uploaded reference — rendered by author ahead of the project:
  - `uploads/logo.html` (4×4 triangular lattice + two polylines)
  - `uploads/style.html` (full-bleed lattice background canvas)
  - `uploads/style.md` (geometry, palette, stroke specs)
  - Copies preserved in [`reference/`](reference/).
- GitHub repo: [`AttilaMihaly/morphir-substrate`](https://github.com/AttilaMihaly/morphir-substrate)
  - `specs/vision.md` — the executable-specification vision document
  - `specs/language.md` — markdown conventions, document-inclusion rules
  - `specs/language/concepts/*.md` — decision tables, provenance, records, choice, etc.
  - `specs/language/expressions/*.md` — the primitive operation catalog
  - `specs/tools/cli/commands.md` — the `substrate` CLI (`test`, `eval`, `list`)
  - `examples/order-total.md` — a complete worked example
  - `branding/` — identical to the uploaded references

No Figma was provided. There is no production UI; Substrate today is a
CLI + a markdown corpus. The UI kits here are a high-fidelity *design
proposal* for the concepts described in `vision.md` (live data binding,
impact analysis, the markdown-native debugger), grounded in the brand.

---

## Index — what's in this project

Root files:

- `README.md` — this document (start here)
- `colors_and_type.css` — design tokens: colour, type, spacing, shadow, motion
- `SKILL.md` — Agent-Skill entry point for reuse inside Claude Code
- `assets/` — logo variants, lattice background script
- `reference/` — verbatim copies of the author's uploaded HTML/MD
- `fonts/` — (none; faces loaded from Google Fonts — see Caveats)
- `preview/` — small HTML cards that populate the Design System tab
- `ui_kits/spec-editor/` — markdown-native debugger + impact analysis UI
- `ui_kits/docs-site/` — documentation site & CLI terminal UI

UI kits each contain:

- `index.html` — interactive click-through
- `README.md` — what's mocked, what's aspirational
- `*.jsx` — component modules

---

## CONTENT FUNDAMENTALS

Substrate's prose is the product. The specs ARE the program, so the
copywriting rules are unusually load-bearing.

### Voice

- **Third-person, declarative, precise.** The specs describe *what the
  system is*, not what the reader should do. Example from `vision.md`:
  *"The language prioritizes meaning over form. Structure emerges from
  semantic intent."* Not "you should prioritize…"
- **Definitional over persuasive.** A concept is introduced, named,
  and then cross-referenced by link. There is no marketing voice, no
  benefit-oriented copy, no "unlock", "supercharge", "seamlessly".
- **Second person only appears in instructional CLI copy** (e.g. the
  `--verbose` flag "Show passing cases in addition to failures"). Even
  then it avoids "you".
- **First person is absent.** No "we", no "our".

### Tone

- Quiet, exact, slightly academic. Reads like a well-edited RFC or a
  regulatory standard. *"A row matches when every condition cell
  matches. A matching row's output cells determine the result."*
- Comfortable with jargon (dataflow, provenance, Voronoi cells, Choice,
  catch-all, projection) *and* with restating those terms in plain
  English once per section.
- No exclamation marks. No emoji. No hedging adverbs.

### Casing

- **Concept names are Title Cased when referenced as entities**
  (Decision Table, Record, Provenance, If-Then-Else, Choice) — this
  mirrors how a linked markdown heading reads. In running prose they
  revert to lowercase.
- **Headings are sentence case** (`Structure`, `Condition Cells`,
  `Otherwise Row`). Display text never shouts.
- **Code identifiers stay as authored** — `unit_price`, `discount_rate`,
  `counterparty`, snake_case throughout.

### Markdown posture

- Headings, bullet lists, fenced code blocks, GFM tables, reference-style
  link definitions. That's the full kit.
- Every reference to a type or operation is a link — prose is a
  navigable semantic graph. The design system mirrors this: component
  previews should hyperlink every type/concept, not bold it.
- Footnotes are reserved for inferred type annotations (`[^type-price]`).

### Example patterns to imitate

- **Definitional opener:** "A Decision Table is a tabular representation
  of a conditional: a set of rules, evaluated top to bottom, where the
  first rule whose conditions all match determines the result."
- **Rule statement:** "A row whose first cell is the literal word
  `otherwise` is a catch-all: it matches any input and must appear as
  the last row."
- **CLI copy:** "Runs all test cases embedded in a user module. Exits
  with code `1` if any test fails."

### Patterns to avoid

- CTAs like "Get started", "Try it free", "Learn more →".
- Bulleted benefit lists ("Fast. Reliable. Open.").
- Any copy that would feel at home on a SaaS landing page.
- Decorative metaphors — the metaphor in the brand (a crystalline
  substrate, a lattice, a dataflow graph) is enough; don't add more.

---

## VISUAL FOUNDATIONS

### Colour

Three colours do almost everything:

- **Pine** — a family of desaturated greens from `#1A2820` to `#EEF4EF`.
  This is the surface system, the text system, and the lattice ink. Pine
  is the visual substrate the name suggests.
- **Blue `#16A2DC`** — the first polyline in the logo. Used for links,
  input/source nodes in dataflow, `info` state, primary interactive
  accents.
- **Orange `#F26A21`** — the second polyline. Used for derived values,
  emphasis, `warn`-adjacent highlights in impact diffs, and as the
  complement in any two-up colour layout.

Blue and orange are deliberately kept as *signals* — they read as the
two traces on an oscilloscope, not as decoration. A view should default
to pine-on-paper and only introduce a hue when something is being
pointed at.

Backgrounds use a soft radial gradient from `#F7F9F7` (paper) to
`#EEF4EF` (pine-50). Full saturation backgrounds are reserved for cover
slides and deliberate emphasis.

Status colours (ok/warn/fail) are calibrated against pine so they read
as quiet annotations inside prose, never alarm-bell red on white.

### Typography

There's no declared typeface in the source material — the authors set
`Segoe UI, Tahoma, Geneva, Verdana, sans-serif` as a web-safe stack.
We substitute:

- **Display / prose headings:** `Fraunces` — warm, slightly editorial
  serif; echoes the academic-regulatory tone of the specs.
- **Body / UI:** `Inter` — neutral, high-x-height humanist sans with
  good tabular figures for spec tables.
- **Code / expressions:** `JetBrains Mono` — dense, disambiguated
  letterforms for operation trees and CLI output.

Type is set on a modest scale (12/13/15/17/20/24/32/44/60) with tight
tracking on display (`-0.01em`) and slightly loose tracking on caps
eyebrows (`0.08em`). Body is 15px/1.55. Prose uses `text-wrap: pretty`;
headings use `text-wrap: balance`.

### Spacing

4px base grid. The design system *also* honours two lattice constants
— `s = 40px` (default background spacing) and `s = 80px` (large-format
logo). Layout rhythm prefers multiples of 8 at the UI level and
multiples of 40 for full-bleed compositions.

### Backgrounds

The triangular lattice is the single recurring motif. Three usages:

1. **Full-bleed** on cover slides and landing sections (dots + lines at
   default opacity).
2. **Tinted** — same pattern, colours swapped to match local theme
   while preserving the 2:1 dot-to-line opacity ratio.
3. **Absent** — most UI surfaces are plain paper. The lattice is not
   carpet; it is used deliberately, not universally.

No stock photography, no hand-drawn illustrations, no repeating motifs
other than the lattice.

### The logo as system

The logo is two polylines tracing partial hexagons in the lattice. The
same construction rule is the design grammar:

- **Blue and orange may only appear as strokes**, never as fills, in
  brand contexts. (UI surfaces can use them as fills for chips, buttons,
  badges; see the component kit.)
- **Rounded stroke caps and joins** (`stroke-linecap: round`,
  `stroke-linejoin: round`) are the one inviolable detail — every
  line-drawn mark in the system inherits this.
- **Strokes are thick.** The canonical logo uses stroke-width = `2.4 × s`;
  display strokes in the UI are generous.

### Motion

- Easings: `cubic-bezier(0.2, 0.6, 0.2, 1)` for entrance/standard;
  `cubic-bezier(0.4, 0, 1, 1)` for exit. No springs, no bounces.
- Durations: 120 / 180 / 260ms. Anything longer is a
  deliberate *reveal*, not a UI transition.
- Preferred effects: fade + 4–8px translate, colour wash-in. Avoid
  scale transforms on text. The lattice dots never animate.

### Hover / press / focus

- **Hover on surfaces:** shift background one pine step darker
  (`--pine-50 → --pine-100`), no elevation change.
- **Hover on coloured buttons:** shift to the `-ink` variant (e.g.
  `--brand-blue → --brand-blue-ink`).
- **Press:** `transform: translateY(1px)` — no shrink, no ripple.
- **Focus:** 3px outer ring in `color-mix(brand-blue 22%, transparent)`,
  never a default browser outline.

### Borders, radii, shadows

- Borders are **hairlines** (`1px solid --pine-200`) on cards, fields,
  and table rows. No heavy divider lines.
- Radii: 3 / 6 / 10 / 14 / 20px + pill. 10px is the default card radius.
- Shadows are green-tinted (`rgba(36, 50, 40, ...)`), layered 2-deep,
  and tiny. Nothing floats dramatically. There is no glow / neon / glass
  morphism.
- Inner shadows (`--shadow-ink`) are used for sunken code wells.

### Cards

Paper on paper. `background: #FDFEFD`, `border: 1px solid #D5DFD8`,
`border-radius: 10px`, `box-shadow: --shadow-1`. Padding defaults to
16–24px. A card with lifted emphasis uses `--shadow-3` and a 14px
radius. No coloured-left-border cards.

### Transparency & blur

Used sparingly. The only canonical usage is the backdrop-blurred caption
chip in the brand reference files: `rgba(255,255,255,0.7)` with a 2px
blur. UI panels that float over the lattice (e.g. the debugger overlay)
may use the same recipe.

### Layout rules

- Content column is typically **720–760px** for prose (a specification
  reading width), **960–1100px** for tables and dashboards, full-width
  for the live-debug view.
- Fixed elements (sidebars, toolbars, status bars) are pine-toned paper
  with hairline borders — they recede.
- Prefer CSS Grid for composition; flexbox for clusters. Avoid absolute
  positioning except for overlays.

### Imagery

No photography in the system. If imagery is ever needed, it should be
monochrome, desaturated, and treated with the pine palette.

---

## ICONOGRAPHY

Substrate today has no icon font, no SVG icon set, and no emoji use in
the source material. The repo's only graphic is the logo polyline.

### Decision & substitution

- **System in use:** [Lucide](https://lucide.dev) (CDN-linked via
  `lucide@latest`), picked for its thin 1.5–2px stroke weight and
  rounded caps — a natural match for the logo's stroke grammar.
- **Stroke width:** `1.75px` for 20–24px icons; `2px` for ≤16px icons.
- **Colour:** `currentColor`. Icons inherit text colour and follow the
  same blue/orange/pine discipline as everything else.
- **Size:** 16 / 20 / 24. 32+ is reserved for empty-state illustrations.
- **Filled vs outline:** outline is the default. Filled variants are
  permitted only for emphasis within the active state of a toggle.

**Flagging the substitution:** no icon family was specified in the
Substrate source material. Lucide is the closest visual match to the
brand's rounded-cap line grammar and is used throughout until the team
specifies otherwise.

### Unicode and mathematical symbols

The spec language itself uses mathematical operators as first-class
content: `→` marks output columns in decision tables; `≠ ≥ ≤ > <` are
condition operators; checkmarks (`✓`) appear in CLI output. These are
*content*, not decoration — they are typeset in the body or mono face
and never replaced with glyphs.

### Emoji

Not used. Do not introduce emoji anywhere in Substrate UI or marketing
copy.

### Logos

- `assets/logo.svg` — canonical two-colour mark, `220 × 220` viewBox
- `assets/logo-mono-ink.svg` — pine-ink monochrome fallback
- `assets/logo-lockup.svg` — mark + wordmark horizontal lockup

The mark scales by multiplying every coordinate *and* the stroke-width
by the same factor (see `reference/style-reference.md` §Logo).

---

## Caveats

- **Fonts are substitutions.** The author-supplied references use
  `Segoe UI, Tahoma…` as a web-safe stack. I substituted Fraunces +
  Inter + JetBrains Mono loaded from Google Fonts. If the team has
  preferred faces, swap `--font-display / --font-body / --font-mono`
  in `colors_and_type.css` and drop TTFs into `fonts/`.
- **Icon set is a substitution.** Lucide is my choice for its
  stroke-cap grammar. Confirm or replace.
- **UI kits are proposals.** The vision document describes a markdown-
  native debugger, impact analysis, and document enrichment; no
  production UI exists yet. The kits translate those descriptions into
  hi-fi surfaces using the brand grammar.
- **No Figma provided.** All component shapes were derived from the
  spec prose + the lattice construction rules.

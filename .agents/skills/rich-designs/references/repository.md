# morphir-moonbit

- `AGENTS.md` owns document/tracker policy. Start documents from `docs/templates/agent-document.html`; retain
  its head/CSS and optional pinned highlighter. Add no other external resources or scripts.
- Review drafts live in `.dev/`. Durable specifications, plans and reports live in the owning bead's design field
  in the shared Morphir tracker. `.dev` files are ignored and are not PR deliverables by themselves.
- Use [beads-companion](../../beads-companion/SKILL.md) for the shared-database guard, rich-design helper,
  notes/memory capture and sync. Run from the repository root:

```sh
moonx scripts/beads-check.mbtx
bd dolt pull
moonx scripts/beads-companion.mbtx design inspect BEAD_ID
moonx scripts/beads-companion.mbtx design export BEAD_ID
moonx scripts/beads-companion.mbtx design store BEAD_ID .dev/designs/review.html --replace
bd dolt push
```

The commands are examples of separate steps. Inspect and merge the latest content before replacing it.
The export defaults to `.dev/beads-specs/BEAD_ID.html` for HTML. Existing files/designs are protected unless
replacement is explicit. Use the full `beads:plan` workflow in `AGENTS.md` for plan import and ledgers.

The Wasm hosting and execution-profile study in `morphir-ukvn.5.55.7` is a concrete example of a complete HTML
design with inline SVG saved in beads. It contains proposed work as well as measured probes; retain that distinction.
Use it as an example, not a template for every design's technical claims or structure.

The site under `apps/morphir-site` is a possible publication surface. Inspect its current routes/build/navigation
before choosing it; storing local HTML in beads does not automatically publish a site route.

Before pushing code, run `mise run lint`, `mise run lint:moonbit` and `mise run validate`. Use focused browser,
script or code tests for changed behavior. `mise run test:ci` covers script/CI policy changes. Commits use
Conventional Commits without AI attribution. Explicit user authorization governs merges and releases.

# morphir-moonbit

- `AGENTS.md` owns document/tracker policy. Start documents from `docs/templates/agent-document.html` and retain
  its head. Its styles and the vendored highlighter are files in `docs/templates/assets/`, referenced by relative
  paths: correct the `assets/` prefix for the copy's location. Embed no CSS or JavaScript, and add no other
  external resources or scripts.
- The complete pinned [Archify package](../../archify/SKILL.md) is installed in `.agents/skills/archify/`.
  Its [upstream record](../../archify/UPSTREAM.md) identifies the revision and licenses. Use the project copy,
  not a personal installation or an unpinned download.
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

## Narrative and diagram workflow

Explain a user or contributor journey in connected prose, with a concrete input, the steps that transform it,
the result and the limits of the demonstrated behavior. Choose diagrams that answer different questions:
architecture for responsibilities, data flow for artifacts, sequence for calls and ownership, lifecycle for
states and cleanup. Keep claims tied to inspected source or recorded evidence.

- Mermaid is useful for concise editable sources. Keep the `.mmd` source beside a repository-owned SVG or in a
  clearly labelled source block in the document. Render or faithfully translate it to accessible SVG for the
  docs; do not add a browser-side Mermaid dependency. Check that the rendered topology matches the source.
- SVG is the portable rendering format. Use `viewBox`, readable labels, title/description and a prose equivalent.
  Scope SVG IDs and styles to avoid collisions with the site or other diagrams. Inspect wide and narrow layouts.
- Use Archify for richer diagrams and its schema, source-evidence and rendering checks. Read its relevant
  references before authoring. Run the installed CLI from the repository root through the pinned Node tool:

```sh
mise exec -- node .agents/skills/archify/bin/archify.mjs doctor
mise exec -- node .agents/skills/archify/bin/archify.mjs finalize sequence .dev/diagrams/example/candidate.json .dev/diagrams/example/sequence.html --repo-root . --quality showcase --json
```

Set the candidate's `meta.output` to that same `.dev/` output path. Keep working candidates, standalone viewers
and receipts in `.dev/diagrams/<subject>/`, overriding Archify's default `.archify/` directory. A passing native
diagram `finalize` receipt records validation, delivery, strict artifact checks and browser checks. Report unavailable
gates accurately and distinguish automated checks from visual inspection. Use the existing browser tooling;
do not download another browser stack just to render a document. If Archify cannot discover a cached Chromium
that the project already uses, set `ARCHIFY_CHROME` to its executable path for the command and rerun with a fresh
`--out-dir`. Keep machine-specific browser paths out of committed files.

For published docs, integrate a static SVG export into the site's existing page layout and narrative. Keep a
maintained diagram's editable Mermaid or Archify JSON source with its repository-owned artifact when committed.
Do not copy the standalone Archify viewer's scripts, head or CSS into a template document. Keep any interactive
viewer separate and publish it only when the requested docs scope calls for it. Recheck the integrated page,
because the standalone viewer's receipt does not validate a later SVG extraction or the site's layout.

For beads-owned designs, embed the complete SVG and any Mermaid source in the stored HTML so the document
remains readable after recovery. Preserve Archify candidates and a compact receipt summary in the owning bead's
notes or comments, including source revisions and reproduction paths; a link to an uncommitted `.dev/` file is
not recoverable on another machine. Keep user-facing documentation free of agent ledgers and tracker workflow.

Before pushing code, run `mise run lint`, `mise run lint:moonbit` and `mise run validate`. Use focused browser,
script or code tests for changed behavior. `mise run test:ci` covers script/CI policy changes. Commits use
Conventional Commits without AI attribution. Explicit user authorization governs merges and releases.

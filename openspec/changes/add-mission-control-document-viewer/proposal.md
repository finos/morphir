# Proposal

## Why

Reviewed documents in this repository are HTML pages that reference shared styles and scripts in
`docs/templates/assets/`. They are hard to view correctly:

- A design stored in beads must be exported by hand before it can be opened, and the export works only at a path
  whose relative asset links resolve.
- An OpenSpec change is part HTML (`design.html`) and part Markdown (`proposal.md`, `tasks.md`, `spec.md` files).
  The Markdown parts show as plain text, and an older change can have a Markdown design.
- A page opened from a `file://` URL loses its styles when it moves, for example when `openspec archive` moves a
  change one directory deeper.

`morphir-mission-control` is a new local app for the people and agents who work on Morphir. Viewing documents is its
first job. More jobs will follow; they are not part of this change.

## What Changes

- Add the app `morphir-mission-control`, with a command that opens a document in the browser, rendered with the
  agent document template and its assets. A document is one of:
  - a bead id: the app reads the bead's design from the shared beads tracker, with no manual export;
  - an OpenSpec change: the app shows every file of the change, with Markdown files rendered into the same template;
  - an HTML or Markdown file in the checkout.
- The app keeps one local server running for a checkout. A later command reuses that server: it does not start a
  second server or fail because the port is in use.
- Add a transform between the two forms of a document:
  - referenced: the page links to the shared assets (the form that is committed and stored);
  - standalone: the page holds its styles and scripts inline, so it renders with no checkout.

## Capabilities

### New Capabilities

- `mission-control/document-viewer`: open a bead design, an OpenSpec change or a document file, rendered in the
  browser through one reused local server.
- `mission-control/standalone-documents`: convert an agent document between the referenced form and the standalone
  form, in both directions.

### Modified Capabilities

None.

## Not decided yet

- What else mission control does, besides documents.
- When the server stops: on a command, after a time with no requests, or both.
- What a standalone copy is for: sharing with people who have no checkout, storing in beads, or both. The answer
  can change which form `beads-companion design store` writes.
- The implementation language and where the server code lives (MoonBit native, or TypeScript like
  `apps/morphir-site/scripts/serve.ts`).

## Beads

- **Tracked by**: `morphir-ukvn.5.97` (epic, child of Track 5 `morphir-ukvn.5`)
- **Related**: None found. Searches for mission control, document viewer, rich designs, HTML documents and
  beads-companion found no open bead for this work.

## Impact

- New app directory `apps/morphir-mission-control/` and a mise task to run it.
- Reads beads through the same path as `scripts/beads-companion.mbtx design export`.
- Can reuse the Markdown renderer in `apps/morphir-site/content` (`render_markdown`).
- Uses `docs/templates/agent-document.html` and `docs/templates/assets/` as they are.
- Opens a local port bound to the loopback interface only.

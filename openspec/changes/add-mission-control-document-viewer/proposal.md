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

`morphir-mission-control` is a new local app for the people and agents who work on Morphir. Its long-term job is to
coordinate intent and tasks: it will move tasks between a common representation and trackers such as GitHub, beads
and JIRA, use the Open Knowledge Format (OKF, through `moonrockz/okf`) as a standard form for documents such as
OpenSpec changes, let people view and work with all of these, and connect them to Morphir for executable specs.
This change builds only its first part: viewing documents. The rest is listed under Later work.

## What Changes

- Add the app `morphir-mission-control`, with a command that opens a document in the browser, rendered with the
  agent document template and its assets. A document is one of:
  - a bead id: the app opens the bead's page, with its design read from the shared beads tracker and no manual
    export;
  - an OpenSpec change: the app shows every file of the change, with Markdown files rendered into the same template;
  - an HTML or Markdown file in the checkout.
- Add a bead browser: a web page that lists every bead in the tracker, open and closed, and a page for each bead
  that shows all of its content: fields, labels, description, design, acceptance criteria, notes, comments, close
  reason, and links to its parent, children and dependencies.
- Build the app's web interface with Rabbita (`moonbit-community/rabbita`), the MoonBit web framework that
  `apps/morphir-site` and `apps/morphir-workbench` already use. Documents keep their agent document template.
- The app keeps one local server running for a checkout. A later command reuses that server: it does not start a
  second server or fail because the port is in use.
- Add a transform between the two forms of a document:
  - referenced: the page links to the shared assets (the form that is committed and stored);
  - standalone: the page holds its styles and scripts inline, so it renders with no checkout.

## Capabilities

### New Capabilities

- `mission-control/document-viewer`: open a bead design, an OpenSpec change or a document file, rendered in the
  browser through one reused local server.
- `mission-control/bead-browser`: list every bead of the tracker and show the full content of each bead as a web
  page.
- `mission-control/standalone-documents`: convert an agent document between the referenced form and the standalone
  form, in both directions.

### Modified Capabilities

None.

## Decisions

The maintainer confirmed these on 2026-10-25 (task group 1, `morphir-ukvn.5.97.1`):

- The server stops on a `stop` command, and also by itself after 30 minutes with no requests.
- The standalone form is for sharing a document with people, or with machines, that have no checkout and do not
  want to pull the repository. `beads-companion design store` keeps storing the referenced form.
- The app is MoonBit native, in `apps/morphir-mission-control`.
- The web interface uses Rabbita. Added on 2026-10-25 with the bead browser.

## Later work

These are the vision of mission control. They are not part of this change, and each needs its own change:

- A common representation of tasks, with import and export for GitHub Issues, beads and JIRA, added over time.
- OKF as the standard format for intent documents such as OpenSpec changes, through `moonrockz/okf` and its
  `openspec` profile (in the `moonrockz/mission-control` repository).
- Viewing and working with documents and tasks from all of these sources in one place.
- Integration with Morphir, so that specs become executable.

## Beads

- **Tracked by**: `morphir-ukvn.5.97` (epic, child of Track 5 `morphir-ukvn.5`)
- **Related**: None found. Searches for mission control, document viewer, rich designs, HTML documents and
  beads-companion found no open bead for this work.

## Impact

- New app directory `apps/morphir-mission-control/` and a mise task to run it.
- Reads beads through the same path as `scripts/beads-companion.mbtx design export`, for one bead and for the full
  list.
- Adds a Rabbita front end, compiled to JavaScript, at the version pinned by the other apps (`0.16.3`).
- Can reuse the Markdown renderer in `apps/morphir-site/content` (`render_markdown`).
- Uses `docs/templates/agent-document.html` and `docs/templates/assets/` as they are.
- Opens a local port bound to the loopback interface only.

## Purpose

Let a person open any reviewed document of this repository in the browser, rendered with the agent document
template and its shared assets, through one command and one reused local server.

## ADDED Requirements

### Requirement: Open a bead design

The app SHALL open the design of a bead, given its id, by reading it from the shared beads tracker. It SHALL not
require the person to export the design first.

#### Scenario: HTML design in a bead

- **WHEN** a person runs the open command with the id of a bead whose design is an HTML document
- **THEN** the browser shows that design with the template styles and code highlighting

#### Scenario: Bead without a design

- **WHEN** a person runs the open command with the id of a bead that has no design, or an id that does not exist
- **THEN** the command fails with a message that names the id and the reason, and opens no page

### Requirement: Open an OpenSpec change

The app SHALL open an OpenSpec change, given its name or directory, as a set of pages: one page for each file of
the change and an index page that links to them. This includes archived changes.

#### Scenario: Change with HTML design and Markdown files

- **WHEN** a person opens a change that has `proposal.md`, `design.html`, `tasks.md` and `spec.md` files
- **THEN** the index page links to each file, and each linked page renders with the template styles

#### Scenario: Older change with a Markdown design

- **WHEN** a person opens a change whose design is `design.md`
- **THEN** the design page renders the Markdown into the template, like the other Markdown files

### Requirement: Open a document file

The app SHALL open an HTML or Markdown file in the checkout, given its path.

#### Scenario: Exported design in .dev

- **WHEN** a person opens `.dev/beads-specs/<epic>.html`
- **THEN** the browser shows the page with the template styles and code highlighting

### Requirement: Render Markdown in the template

The app SHALL render a Markdown document as HTML inside the agent document template, with its styles, code
highlighting, heading ids and a table of contents of its sections.

#### Scenario: Markdown with code and headings

- **WHEN** a person opens a Markdown file that has `##` headings and a fenced code block with a language
- **THEN** the page has one table-of-contents entry for each `##` heading, and the code block is highlighted

### Requirement: Shared assets resolve wherever the document is

The app SHALL serve a document so that its references to the shared template assets load, whichever directory
holds the document, including a document whose relative asset prefix is one level too short or too long.

#### Scenario: Archived OpenSpec design

- **WHEN** a person opens a `design.html` that `openspec archive` moved without correcting its asset prefix
- **THEN** the page still renders with the template styles

### Requirement: Reuse one running server

The app SHALL keep one local server for a checkout. A later open command SHALL use the running server and open the
new page. It SHALL not start a second server or fail because the port is in use.

#### Scenario: Second open command

- **WHEN** a person runs the open command while the server from an earlier command is still running
- **THEN** the new page opens from the same server, and only one server process exists for the checkout

#### Scenario: Stale server record

- **WHEN** the app's record of a running server names a process that is no longer listening
- **THEN** the app starts a new server and replaces the record

### Requirement: Local access only

The server SHALL listen only on the loopback interface and SHALL serve only files from the checkout and documents
it renders itself.

#### Scenario: Request for a path outside the checkout

- **WHEN** a request names a path that resolves outside the checkout
- **THEN** the server refuses it and returns no file content

## Purpose

Let a person read everything in the shared beads tracker as web pages: a list of all beads, and a page for each bead
with its full content and links to the beads it relates to. The interface is built with Rabbita.

## ADDED Requirements

### Requirement: List all beads

The app SHALL show a page that lists every bead in the tracker, including closed beads, with its id, title, type,
status, priority and labels. The person SHALL be able to filter the list by status, type, label and text. (bead:
morphir-ukvn.5.97.5)

#### Scenario: Open and closed beads

- **WHEN** a person opens the bead list for a tracker that has open and closed beads
- **THEN** the list shows both, and each row links to that bead's page

#### Scenario: Filter by label

- **WHEN** a person filters the list by the label `repo:morphir-moonbit`
- **THEN** the list shows only beads that carry that label

### Requirement: Show the full content of a bead

The app SHALL show a page for each bead with all of its content: id, title, type, status, priority, labels, owner,
dates, spec id, description, design, acceptance criteria, notes, close reason and comments. Markdown fields SHALL
render as formatted text. (bead: morphir-ukvn.5.97.5)

#### Scenario: Bead with every field

- **WHEN** a person opens the page of a bead that has a description, an HTML design, notes and comments
- **THEN** the page shows each of them, the design renders with the template styles, and the comments show their
  author and date

#### Scenario: Unknown bead

- **WHEN** a person opens the page of an id that does not exist
- **THEN** the page says that the id was not found, and shows no other bead

### Requirement: Navigate between related beads

A bead page SHALL link to the bead's parent, its children and the beads it depends on or that depend on it, with the
type of each dependency. (bead: morphir-ukvn.5.97.5)

#### Scenario: Epic with children

- **WHEN** a person opens the page of an epic that has child tasks
- **THEN** the page lists the children with their status, and each one links to its own page

### Requirement: Bead content cannot run scripts

Bead content comes from a shared tracker that other people write. The app SHALL show it so that no script or remote
resource in it runs or loads. (bead: morphir-ukvn.5.97.5)

#### Scenario: Design with a script

- **WHEN** a person opens a bead whose design contains a `<script>` element or a remote image
- **THEN** the design shows, the script does not run, and the image is not fetched

### Requirement: Read only

The bead browser SHALL not change the tracker. It SHALL show when it last read the tracker, and SHALL read it again
when the person asks. (bead: morphir-ukvn.5.97.5)

#### Scenario: Refresh after a tracker change

- **WHEN** a bead changes in the local tracker database and the person asks the page to refresh
- **THEN** the page shows the new content and the new read time

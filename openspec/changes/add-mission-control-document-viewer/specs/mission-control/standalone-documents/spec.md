## Purpose

Convert an agent document between the referenced form, which links to the shared template assets, and the
standalone form, which carries those assets inline, so one document can be committed small and shared whole. The
standalone form is for people, and for machines, that have no checkout and do not want to pull the repository.
Committed documents and designs stored in beads keep the referenced form.

## ADDED Requirements

### Requirement: Make a document standalone

The app SHALL convert a referenced document into a standalone document: each reference to a shared template asset
becomes the inline content of that asset. The standalone document SHALL render with no checkout and no network.

#### Scenario: Template document made standalone

- **WHEN** a person converts a document that references the template CSS, the highlight.js files and the setup
  script
- **THEN** the output has those contents inline, has no reference to `docs/templates/assets/`, and renders with
  styles and code highlighting from a directory outside the checkout

### Requirement: Make a document referenced

The app SHALL convert a standalone document into a referenced document: each inline copy of a shared template asset
becomes a reference to that asset, with a relative path that is correct for the output location.

#### Scenario: Standalone document written into .dev

- **WHEN** a person converts a standalone document and writes the output to `.dev/beads-specs/`
- **THEN** the output references the assets with the prefix `../../docs/templates/assets/` and holds no inline copy
  of them

### Requirement: Content survives the round trip

Converting a document to standalone and back to referenced SHALL keep its `<main>` content unchanged.

#### Scenario: Round trip

- **WHEN** a person converts a referenced document to standalone and the result back to referenced
- **THEN** the `<main>` content of the final document equals that of the original

### Requirement: No unknown or remote resources

The conversion SHALL inline only the shared template assets. It SHALL not fetch from the network, and it SHALL
refuse a document that references any other script or stylesheet.

#### Scenario: Document with an extra remote script

- **WHEN** a person converts a document that loads a script from a remote URL
- **THEN** the conversion fails with a message that names that URL, and writes no output

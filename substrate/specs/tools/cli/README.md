# CLI

The `substrate` command-line interface parses, evaluates, and tests specification
modules, and manages package dependencies.

## Contents

- [Commands](commands.md) — the `test`, `eval`, and `list` commands and all their options.
- [Packages](packages.md) — the package system: manifests, versioning, vendoring, and the
  `init`, `install`, `update`, `validate`, and `publish` commands.
- [Refactor](refactor.md) — the `refactor rename` command: rename files and sections, move
  sections between files, and keep all cross-project references consistent.
- [Coverage](coverage.md) — the `coverage` command: measure which language features a document
  exercises and how much of a document is recognised as substrate rather than plain prose.
- [Design Decisions](design-decisions.md) — implementation rationale: pipeline architecture,
  TypeScript configuration, and testing strategy.

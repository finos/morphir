# CLI

The `substrate` command-line interface parses, evaluates, and tests specification
modules, and manages package dependencies.

## Contents

- [Commands](commands.md) — the `test`, `eval`, and `list` commands and all their options.
- [Packages](packages.md) — the package system: manifests, versioning, vendoring, and the
  `init`, `install`, `update`, `validate`, and `publish` commands.
- [Refactor](refactor.md) — the `refactor rename` command: rename files and sections, move
  sections between files, and keep all cross-project references consistent.
- [Migrate](migrate.md) — the `migrate from morphir` and `migrate to morphir` commands: convert
  modules between substrate markdown and Morphir IR JSON.
- [Design Decisions](design-decisions.md) — implementation rationale: pipeline architecture,
  TypeScript configuration, and testing strategy.

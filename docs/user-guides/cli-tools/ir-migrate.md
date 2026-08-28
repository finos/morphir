---
id: ir-migrate
title: IR Migration Guide
sidebar_position: 10
---

# IR Migrate Command

`morphir migrate` upgrades concrete Morphir IR version 3 to version 4. The
equivalent nested command, `morphir ir migrate`, is also available.

The default path reads and writes a single JSON file. For large version 3
models, such as the LCR model, this path visits and releases one module at a
time instead of building the complete source IR in memory.

## Usage

```bash
morphir migrate <INPUT> --output <OUTPUT> [OPTIONS]
```

| Option | Description |
|---|---|
| `-o, --output <PATH>` | Output JSON file or document-tree directory. Without this option, output is displayed. |
| `--target-version <VERSION>` | `latest`, `v4`, `4`, `classic`, `v3`, `3`, `v2`, `2`, `v1`, or `1`. The default is `latest` (v4). |
| `--output-layout <LAYOUT>` | `single-file` or `vfs`. A directory-like output path also selects `vfs`. |
| `--expanded` | Write expanded v4 type expressions instead of the default compact encoding. |
| `--allow-partial` | Permit recoverable incomplete v4 nodes and report diagnostics. |
| `--json` | Print a machine-readable command result. |
| `--force-refresh` | Refresh a cached remote source. |
| `--no-cache` | Do not use the remote-source cache. |

## Single-file migration

```bash
morphir migrate morphir-ir.json \
  --output morphir-ir-v4.json \
  --target-version v4
```

The output is staged and atomically published, so an existing output file is
not replaced when parsing or migration fails. Compact type encoding is used by
default. Use `--expanded` when a consumer requires explicit v4 type wrappers:

```bash
morphir migrate morphir-ir.json \
  --output morphir-ir-v4.json \
  --expanded
```

The bounded-memory streaming path currently applies to compact v3-to-v4
single-file output. Expanded output and document-tree conversion use the typed
in-memory representation.

## Document-tree (VFS) layout

The VFS layout stores a v4 distribution as a manifest and addressable package,
module, type, and value documents. It can be read back without requiring a
particular physical filesystem implementation.

```bash
# Single file to document tree
morphir migrate morphir-ir.json \
  --output morphir-ir-v4/ \
  --output-layout vfs

# Document tree back to a single file
morphir migrate morphir-ir-v4/ \
  --output morphir-ir-v4.json \
  --output-layout single-file
```

The transport is built on the `vfs` abstraction. The OS filesystem is the CLI
backend; memory-backed filesystems can use the same transport in tests and
embedded applications.

## Remote inputs

HTTP(S), GitHub shorthand, Git repositories, and gists supported by the Morphir
remote-source resolver can be used in place of a local input:

```bash
morphir migrate \
  https://lcr-interactive.finos.org/server/morphir-ir.json \
  --output lcr-v4.json
```

Remote content is first resolved to the local cache, after which it follows the
same migration path as a local file.

## Diagnostics and partial migration

Migration diagnostics include a stable code, severity, IR path, and message.
Without `--allow-partial`, an error diagnostic prevents publication. With the
flag, recoverable constructs may be represented by an explicit incomplete v4
node and reported in the command result. The flag never turns malformed input
or an unrecoverable conversion into success.

## Compatibility

| Source | Target | Status |
|---|---|---|
| Concrete v3 | v4 | Supported, including dependencies, package/module definitions, types, values, and patterns. |
| Concrete v3 | Classic | Preserved in its source representation. |
| v4 | v4 | Supported for re-encoding and layout conversion. |
| v4 | Classic | Not yet supported; the command emits an `unsupported-v4-distribution` diagnostic and leaves existing output untouched. |
| v1/v2 | v4 | Detected, but not claimed as fully compatible; unsupported input is diagnosed. |

The v4 implementation follows the formal v4 types and concrete examples. Some
published v4 schema clauses conflict with the prose and checked-in examples,
especially access-controlled definitions and value attributes/encodings. The
CLI preserves typed v3 information instead of silently dropping it. These
conflicts are tracked in `morphir-vibt`. Use the repository validator while
resolving them:

```bash
cd website
npm run validate:migrated-ir -- ../morphir-ir-v4.json
```

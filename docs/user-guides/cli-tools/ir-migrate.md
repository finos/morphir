---
id: ir-migrate
title: IR Migration Guide
sidebar_position: 10
---

# IR Migrate Command

`morphir migrate` converts concrete Morphir IR version 3 and version 4 between
native JSON and YAML storage. The equivalent nested command,
`morphir ir migrate`, has the same behavior.

Version migration, serialization, and physical layout are independent. A
single invocation can migrate v3 to v4, convert JSON to YAML, and split the
result into a document tree. The pipeline carries typed semantic IR events and
releases each completed module, including for the LCR model.

## Usage

```bash
morphir migrate <INPUT> [--output <OUTPUT>] [OPTIONS]
```

| Option | Description |
|---|---|
| `-o, --output <PATH>` | Output file or document-tree directory. Without this option, the IR artifact is written to stdout. |
| `--target-version <VERSION>` | `latest`, `v4`, `4`, `classic`, `v3`, or `3`. The default is `latest` (v4). |
| `--input-format <FORMAT>` | Input serialization profile. Built-in values are `json` and `yaml`. |
| `--output-format <FORMAT>` | Output serialization profile. Built-in values are `json` and `yaml`. |
| `--output-layout <LAYOUT>` | `single-file` or `vfs`. A directory-like output path also selects `vfs`. |
| `--expanded` | Write expanded v4 type expressions instead of the default compact encoding. |
| `--allow-partial` | Permit only explicitly recoverable incomplete v4 nodes and report diagnostics. |
| `--json` | Without `--output`, emit JSON IR. With `--output`, emit a JSON result envelope after publishing the selected artifact. |
| `--force-refresh` | Refresh a cached remote source. |
| `--no-cache` | Do not use the remote-source cache. |

## Format selection

Single-file output uses this order:

1. `--output-format`;
2. a recognized `.json`, `.yaml`, or `.yml` destination extension;
3. YAML.

A recognized extension that conflicts with `--output-format` is rejected
before publication. Input uses `--input-format`, then a recognized extension,
then bounded JSON-first content detection. JSON is tested first because JSON
syntax is also valid YAML syntax.

```bash
# V3 JSON to the default V4 YAML profile
morphir migrate morphir-ir.json --output morphir-ir-v4.yaml

# V4 YAML to V4 JSON
morphir migrate morphir-ir-v4.yaml --output morphir-ir-v4.json

# Unknown physical names with explicit profiles
morphir migrate model.data --input-format json \
  --output result.data --output-format yaml

# Same-version concrete V3 JSON to YAML
morphir migrate morphir-ir.json --target-version v3 \
  --output morphir-ir.yaml
```

Single-file output is staged and atomically replaced only after decoding,
transformation, encoding, and migration-report checks succeed. Stdout output is
also staged in a temporary file so a late failure does not emit a partial IR
artifact.

## Document-tree (VFS) layout

The v4 document-tree layout stores addressable package, module, type, and value
documents. YAML trees are the default and use these physical names:

- `manifest.yaml`;
- `module.yaml`;
- `*.type.yaml`;
- `*.value.yaml`.

JSON trees use the corresponding `.json` names. Every generated tree is
homogeneous. Discovery rejects a tree containing both supported manifests.

```bash
# V3 JSON to a V4 YAML tree
morphir migrate morphir-ir.json \
  --output morphir-ir-v4.morphir-dist \
  --output-layout vfs

# YAML tree back to one JSON file
morphir migrate morphir-ir-v4.morphir-dist \
  --output morphir-ir-v4.json \
  --output-layout single-file

# Request a JSON tree explicitly
morphir migrate morphir-ir-v4.yaml \
  --output morphir-ir-v4.morphir-dist \
  --output-layout vfs \
  --output-format json
```

The CLI builds the tree in a sibling staging directory, writes module manifests
after their definitions, writes the distribution manifest last, and then
replaces the destination with rollback protection.

## Remote inputs

HTTP(S), GitHub shorthand, Git repositories, and gists supported by the Morphir
remote-source resolver can be used in place of a local input:

```bash
morphir migrate \
  https://lcr-interactive.finos.org/server/morphir-ir.json \
  --output lcr-v4.yaml
```

Remote content is resolved to the local cache and then follows the same format,
version, streaming, and publication path as a local artifact.

## Diagnostics and partial migration

Transport diagnostics include a stable code, stage, severity, semantic cursor,
guidance, and a source location when the decoder supplies one. Malformed or
ambiguous YAML, lossy serialization, duplicate keys, unsupported tags, and
unsafe aliases are never made publishable by `--allow-partial`.

## Compatibility

| Source | Target | Status |
|---|---|---|
| Concrete v3 JSON or YAML | v3 JSON or YAML | Supported as a semantic same-version conversion. |
| Concrete v3 JSON or YAML | v4 JSON or YAML | Supported with module-bounded migration. |
| v4 JSON or YAML | v4 JSON or YAML | Supported for re-encoding and layout conversion. |
| v4 | v3 | Diagnosed as unsupported because v4-only constructs do not yet have lossless downgrade rules. |
| v1/v2 | v3 or v4 | Not claimed; the concrete converter reports an unsupported version. |

The v4 semantic model and JSON/YAML profiles are documented separately under
the IR specification. JSON Schema remains the bootstrap definition of the JSON
profile, not a restriction on native IR storage.

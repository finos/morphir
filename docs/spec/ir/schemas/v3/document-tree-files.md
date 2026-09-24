---
title: "Document Tree File Formats (Version 3)"
linkTitle: "Document Tree Files"
description: "File formats of a v3 document tree, introduced in Morphir IR 3.1.0: the v4 tree layout holding classic v3 payloads"
---

# Document Tree File Formats (Version 3)

A v3 document tree stores a classic `Library` or `Specs` distribution as a directory of files, one file per type or
value. It was introduced in IR format `3.1.0`. The tree uses the layout of the
[v4 document tree](../v4/document-tree-files.md) without change: the same logical paths, profiles, escaping, path
budget, truncation and `fileNames` map. Only the file contents differ. Every file says `"formatVersion": "3.1.0"`,
the envelope members hold canonical strings, and a `def` or `spec` payload is the classic v3 JSON of that entry.

The key words MUST, MUST NOT, SHOULD and MAY are used as in the rest of this specification.

## Serialization profile

A v3 tree maps the logical `manifest`, `module`, `NAME.type` and `NAME.value` documents to one physical profile, as
a v4 tree does:

| Logical document | JSON profile | YAML profile |
| --- | --- | --- |
| `manifest` | `manifest.json` | `manifest.yaml` |
| `module` | `module.json` | `module.yaml` |
| `NAME.type` | `NAME.type.json` | `NAME.type.yaml` |
| `NAME.value` | `NAME.value.json` | `NAME.value.yaml` |

A generated tree MUST use one profile for every file. If discovery finds both `manifest.json` and `manifest.yaml`, it
MUST report ambiguity and MUST NOT select one. The YAML profile holds the same values as the JSON profile. The examples
below use JSON, with one YAML tree in [Complete example](#complete-example).

> An Amazon Ion tree (`manifest.ion`) is an unreleased draft and is not part of this specification. It uses these
> logical paths with annotated Ion elements. See the [Ion draft](../../../../design/draft/ir/ion.md#document-tree).

### Choosing the version on read

The manifest's `formatVersion` decides how a tree is read. A reader that reads both versions MUST read a manifest of
major 3 with the v3 rules on this page, and any other manifest with the v4 rules. A reader of v4 trees only MUST refuse
a manifest of major 3 with `version_mismatch` at `manifest#/formatVersion`. It MUST NOT read such a tree as v4.

## Logical paths

The logical paths are the v4 paths:

```
manifest
pkg/<package path>/<module path>/module
pkg/<package path>/<module path>/<stem>.type
pkg/<package path>/<module path>/<stem>.value
deps/<package path>/@/<module path>/module
deps/<package path>/@/<module path>/<stem>.type
deps/<package path>/@/<module path>/<stem>.value
```

Each directory segment and each stem is the escape of a canonical name, as [Naming](../../../draft/names.md)
defines it. A v3 tree gets its canonical names from the classic word arrays. The conversion is lossless in both
directions:

| Classic v3 JSON | Canonical string | Path segment or stem |
| --- | --- | --- |
| `[["morphir"], ["s", "d", "k"]]` (package) | `morphir/SDK` | `morphir/_sdk` |
| `[["my", "org"], ["my", "project"]]` (package) | `my-org/my-project` | `my-org/my-project` |
| `[["domain"]]` (module) | `domain` | `domain` |
| `["value", "in", "u", "s", "d"]` (name) | `value-in-USD` | `value-in-_usd` |

The `deps/` version segment is a bare `@`, because a v3 distribution carries no package version. The path budget,
truncation and the `fileNames` map follow the v4 rules in
[Write-time truncation and its failure](../v4/document-tree-files.md#write-time-truncation-and-its-failure). A
reader MUST read modules in sorted logical-path order.

## File Types

Every file of a v3 JSON or YAML tree MUST carry `"formatVersion": "3.1.0"`, as a string. The integer `3` and the
string `"3.0.0"` are not valid in such a file, because `3.0.0` has no JSON or YAML document tree. The draft Ion tree
follows its own [Ion draft](../../../../design/draft/ir/ion.md#document-tree), where a v3 `library` tree says
`"3.0.0"`.

Envelope members hold canonical strings: the manifest's `package` and `dependencies`, a module's `path`, the names in
its `types` and `values`, a node file's `name`, and the keys of `fileNames`. A payload under `def` or `spec` is classic
v3 JSON. It keeps classic names, paths and fully qualified names as word arrays, exactly as a single-file v3 document
writes them.

### 1. Distribution Manifest (`manifest.json`)

**Location**: the tree root.

| Member | Required | Value |
| --- | --- | --- |
| `formatVersion` | Yes | `"3.1.0"` |
| `distribution` | Yes | `"Library"` or `"Specs"` |
| `package` | Yes | The distribution's package, as a canonical string |
| `pathBudget` | Yes | An integer of at least 64: the most characters a physical path may use, from the tree root |
| `dependencies` | No | The packages under `deps/`, as canonical strings, in the distribution's dependency order |

A v3 manifest has no other members. A reader MUST refuse any other member with `unknown_member`. That includes
`entryPoints`, `version`, `created` and `layout`, which a v4 manifest may carry. A writer omits `dependencies` when the
distribution has none. A dependency MUST NOT name the distribution's own package, and a package MUST NOT be listed
twice.

**Example (Library with a dependency)**:

```json
{
  "formatVersion": "3.1.0",
  "distribution": "Library",
  "package": "my-org/my-project",
  "pathBudget": 4000,
  "dependencies": ["morphir/SDK"]
}
```

**Example (Specs)**:

```json
{ "formatVersion": "3.1.0", "distribution": "Specs", "package": "my/pkg", "pathBudget": 4000 }
```

### 2. Module Manifest (`module.json`)

**Location**: `pkg/<package path>/<module path>/module.json` and `deps/<package path>/@/<module path>/module.json`.

| Member | Required | Value |
| --- | --- | --- |
| `formatVersion` | Yes | `"3.1.0"` |
| `path` | Yes | The module path, as a canonical string |
| `access` | No | `"Public"` or `"Private"`; writers emit it only when `"Private"`; only in a module definition (see below) |
| `doc` | No | Module documentation: a string, or an array of strings joined with a line break |
| `types` | No | The module's type names, or inline entries (see below) |
| `values` | No | The module's value names, or inline entries (see below) |
| `fileNames` | No | Canonical name to truncated stem, for each name whose stem was cut for the path budget |

Only a module under `pkg/` of a `Library` is a module definition. Every other module is a module specification: the
modules under `pkg/` of a `Specs` tree, and every module under `deps/`. A module definition is public unless it says
`"access": "Private"`, and a writer emits `access` only for a private module. A module specification has no access:
a reader MUST refuse `access` there with `unknown_member`. A v3 module manifest does not accept the v4 alias `module`
for `path`.

A missing `types` or `values` is empty. When `types` or `values` is an array, it lists canonical names, and each name
has its own node file. When it is an object, it holds inline entries: each key is a canonical name and each value is
the payload a node file would hold under `def` or `spec`.

```json
{ "formatVersion": "3.1.0", "path": "domain", "access": "Private", "doc": "Domain.", "types": ["value-in-USD"], "values": [] }
```

### 3. Type Definition File (`*.type.json`)

**Location**: the module's directory, named `<stem>.type.json`, where the stem is the escape of the name or the cut
stem that `fileNames` records.

| Member | Required | Value |
| --- | --- | --- |
| `formatVersion` | Yes | `"3.1.0"` |
| `name` | Yes | The type's canonical name |
| `def` | One of `def` and `spec` | The classic access-controlled, documented type definition |
| `spec` | One of `def` and `spec` | The classic documented type specification |

The role of the module decides which member a node file holds. A file MUST hold exactly one of them:

| Distribution | Under `pkg/` | Under `deps/` |
| --- | --- | --- |
| `Library` | `def` | `spec` |
| `Specs` | `spec` | `spec` |

A `def` payload is `{ "access", "value": { "doc", "value" } }`: the classic entry of a module definition's `types`
list, without its name. A `spec` payload is `{ "doc", "value" }`: the classic entry of a module specification's
`types` list, without its name. Neither wrapper has other members.

**Example (definition)**:

```json
{
  "formatVersion": "3.1.0",
  "name": "user",
  "def": {
    "access": "Public",
    "value": {
      "doc": "",
      "value": ["TypeAliasDefinition", [], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []]]
    }
  }
}
```

**Example (specification)**:

```json
{ "formatVersion": "3.1.0", "name": "int", "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] } }
```

### 4. Value Definition File (`*.value.json`)

**Location**: the module's directory, named `<stem>.value.json`.

The members and the role table are those of a type file. A `def` payload is the classic access-controlled,
documented value definition, `{ "access", "value": { "doc", "value": { "inputTypes", "outputType", "body" } } }`. It
keeps every attribute slot of the classic JSON, including the inferred types that morphir-elm writes on expressions. A
`spec` payload is `{ "doc", "value": { "inputs", "output" } }`.

**Example (definition)**:

```json
{
  "formatVersion": "3.1.0",
  "name": "one",
  "def": {
    "access": "Public",
    "value": {
      "doc": "",
      "value": {
        "inputTypes": [],
        "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []],
        "body": ["Literal", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["WholeNumberLiteral", 1]]
      }
    }
  }
}
```

**Example (specification)**:

```json
{
  "formatVersion": "3.1.0",
  "name": "add",
  "spec": {
    "doc": "",
    "value": {
      "inputs": [[["a"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]]],
      "output": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]
    }
  }
}
```

## Complete example

A `Library` with one private module and one dependency, in the YAML profile:

```
manifest.yaml
pkg/my-org/my-project/domain/module.yaml
pkg/my-org/my-project/domain/value-in-_usd.type.yaml
deps/morphir/_sdk/@/basics/module.yaml
deps/morphir/_sdk/@/basics/int.type.yaml
deps/morphir/_sdk/@/basics/add.value.yaml
```

```yaml
# manifest.yaml
formatVersion: 3.1.0
distribution: Library
package: my-org/my-project
pathBudget: 4000
dependencies: [morphir/SDK]
```

```yaml
# pkg/my-org/my-project/domain/module.yaml
formatVersion: 3.1.0
path: domain
access: Private
doc: Domain.
types: [value-in-USD]
values: []
```

```yaml
# pkg/my-org/my-project/domain/value-in-_usd.type.yaml
formatVersion: 3.1.0
name: value-in-USD
def:
  access: Public
  value:
    doc: ""
    value:
      - TypeAliasDefinition
      - []
      - - Reference
        - {}
        - [[[morphir], [s, d, k]], [[basics]], [int]]
        - []
```

```yaml
# deps/morphir/_sdk/@/basics/int.type.yaml
formatVersion: 3.1.0
name: int
spec:
  doc: ""
  value: [OpaqueTypeSpecification, []]
```

Read back, this tree is the single-file `Library` with `"formatVersion": 3`, because a single-file `Library` needs
nothing newer than `3.0.0` (see [What's New](./whats-new.md#version-310)).

## Validation Rules

A reader MUST refuse a tree that breaks one of these rules. The cursor names the logical path and, after `#`, the
member inside that file.

| Rule | Diagnostic | Cursor |
| --- | --- | --- |
| A file's `formatVersion` is `"3.1.0"`, the same as the manifest's | `version_mismatch` | `<file>#/formatVersion` |
| Every file has `formatVersion` | `missing_format_version` | `<file>#/` |
| A file has only the members listed for its kind | `unknown_member` | `<file>#/<member>` |
| The manifest has `distribution`, `package` and `pathBudget`; a module has `path`; a node file has `name` | `missing_member` | `<file>#/` |
| `distribution` is `Library` or `Specs` | `invalid_distribution_shape` | `manifest#/distribution` |
| `pathBudget` is an integer of at least 64 | `invalid_type` | `manifest#/pathBudget` |
| No dependency names the distribution's own package | `invalid_distribution_shape` | `manifest#/dependencies/<index>` |
| No dependency is listed twice | `duplicate_member` | `manifest#/dependencies/<index>` |
| A node file holds exactly one of `def` and `spec`, the one its role calls for | `invalid_distribution_shape` | `<file>` |
| A `spec` payload has no `access` | `invalid_distribution_shape` | `<file>#/spec` |
| A module specification has no `access`; a module definition's `access` is `Public` or `Private` | `unknown_member`, `invalid_access` | `<file>#/access` |
| Every listed name has its node file | `missing_member` | the missing file's path |
| A payload decodes as the classic v3 JSON of its kind | `invalid_type` | `<file>#/def` or `<file>#/spec` |

A top-level `$meta` member in any tree file is reserved, as in a v4 tree (decision 0014). A reader MUST ignore it and
MUST NOT report it as unknown. A writer MUST NOT emit it. The file-naming, stem and truncation rules are those of the
[v4 tree](../v4/document-tree-files.md#validation-rules).

## Related Documentation

- [What's New in Version 3](./whats-new.md): the `3.1.0` revision and the `Specs` distribution.
- [Document tree files, version 4](../v4/document-tree-files.md): the shared layout.
- [Format version](../../format-version.md): the `formatVersion` contract and support tables.
- [Naming](../../../draft/names.md): canonical names and the file-stem escape.

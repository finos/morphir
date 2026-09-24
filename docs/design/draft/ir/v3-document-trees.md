---
title: IR 3.1.0 and v3 document trees
sidebar_label: v3 trees and 3.1.0
sidebar_position: 13
status: draft
tracking:
  github_issues: [970, 946]
  beads: [morphir-f22s]
---

# IR 3.1.0 and v3 document trees

This draft adds a minor revision of the classic IR, `3.1.0`. The revision adds two things. A v3 distribution may be a `Specs` distribution, and a v3 distribution may be stored as a JSON or YAML document tree. Before this revision, only the Ion tree held v3 ([issue 970](https://github.com/finos/morphir/issues/970)).

A `3.0.0` document stays valid and keeps its meaning. A writer emits the lowest version that expresses its content. A reader that implements this draft accepts `[3.0.0,3.2.0)`.

## Version rules

| Content | `formatVersion` a writer emits |
| --- | --- |
| Single-file v3 `Library` | `3` (the `3.0.0` release), unchanged |
| Single-file v3 `Specs` | `"3.1.0"` |
| Any v3 document tree | `"3.1.0"` in every tree file |

A reader accepts the integer `3` and the release strings `"3.0.0"` and `"3.1.0"`. `3.2.0` and later fail with `unsupported_format_version_minor`, as [format-version support](https://github.com/finos/morphir/blob/main/kb/bundles/morphir/morphir-ir/format-version-support.md) describes. The reference support table becomes `[3.0.0,3.2.0),[4.0.0,4.1.0)`.

A binding that stays on `[3.0.0,3.1.0)` still reads every `3.0.0` document. It refuses a Specs distribution and every v3 tree with the minor-version diagnostic, which is the behaviour decision 0016 requires.

## The Specs distribution

A v3 `Specs` distribution publishes a package's specification without its definitions. It mirrors `Library`:

```json
{
  "formatVersion": "3.1.0",
  "distribution": [
    "Specs",
    [["my"], ["pkg"]],
    [ [ [["morphir"], ["s", "d", "k"]], { "modules": [ … ] } ] ],
    { "modules": [ [ [["basics"]], { "types": [ … ], "values": [ … ], "doc": null } ] ] }
  ]
}
```

The third element lists dependency specifications, as `Library` does. The fourth element is a package specification: its modules are module specifications, spelled as a dependency's modules are.

The Ion spelling uses `kind: specs` in the `morphir::` header and writes the distribution's own modules as `module::spec` values, as the v4 Ion spelling does.

## Document tree files

A v3 tree uses the v4 tree's logical paths, profiles, escaping, truncation and `fileNames` rules without change ([document-tree files](../../../spec/ir/schemas/v4/document-tree-files.md)). Only the file contents differ. Every file carries `"formatVersion": "3.1.0"`. A file whose version differs from the manifest's is rejected at that file.

Envelope members hold canonical strings, the same as the v4 envelope: `package`, `path`, `name`, `dependencies`, and the keys of `fileNames`. A canonical string comes from the classic word arrays, so `[["morphir"], ["s", "d", "k"]]` is `morphir/SDK`. A `def` or `spec` payload is the classic v3 JSON for that entry, exactly as a single-file document writes it.

### Distribution manifest

```json
{ "formatVersion": "3.1.0", "distribution": "Library", "package": "my/pkg", "pathBudget": 4000, "dependencies": ["morphir/SDK"] }
```

`distribution` is `Library` or `Specs`. A v3 tree has no `entryPoints`. `dependencies` lists the `deps/` packages in order and is omitted when empty. `pathBudget` is required, with the v4 floor of 64.

### Module manifest

```json
{ "formatVersion": "3.1.0", "path": "domain/user", "doc": "User records.", "types": ["user"], "values": ["find"] }
```

Under `pkg/` in a `Library`, `access` is written only when it is `Private`. A `Specs` tree under `pkg/`, and every tree under `deps/`, holds module specifications, which have no `access`. `types` and `values` list names. A reader also accepts inline entries keyed by canonical name, whose values are node payloads, as the v4 reader does. `fileNames` records cut stems, as in v4.

### Type and value files

```json
{ "formatVersion": "3.1.0", "name": "user", "def": { "access": "Public", "value": { "doc": "", "value": ["TypeAliasDefinition", [], <Type>] } } }
{ "formatVersion": "3.1.0", "name": "int", "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] } }
{ "formatVersion": "3.1.0", "name": "find", "def": { "access": "Public", "value": { "doc": "", "value": { "inputTypes": [ … ], "outputType": <Type>, "body": <Value> } } } }
{ "formatVersion": "3.1.0", "name": "add", "spec": { "doc": "", "value": { "inputs": [ … ], "output": <Type> } } }
```

A `Library` tree holds `def` files under `pkg/` and `spec` files under `deps/`. A `Specs` tree holds `spec` files in both. A `def` payload keeps v3's attribute slots, including a value's inferred types.

## Implementation in morphir-rust

The kit's layout keeps one implementation of the rules the compatibility kit pins, over a generic payload:

- `TreeParts<P>` holds the manifest envelope and each module's root, package, path, access, doc, and `(name, payload)` for its types and values. A `Payload` trait lets the layout read `formatVersion`, `name` and listings from a file of type `P`, and build one. `serde_json::Value` implements it for the JSON and YAML profiles.
- A `TreeModel` trait turns `TreeParts` into a distribution and back. The v4 model keeps today's decoders. The v3 model decodes and encodes the classic types.
- `read_tree` and `write_tree` stay v4. `read_tree_v3`, `write_tree_v3` and the per-module streaming writers are new. `read_any_tree` dispatches on the manifest's `formatVersion`.
- The document-tree transport accepts v3 for every profile, streams v3 modules through the kit's writers, and reads a tree at the version its manifest names. A manifest whose version differs from the selected one is `version_mismatch`.
- `morphir ir migrate` writes v3 JSON and YAML trees, and version detection reads any manifest. `ir_storage::read_value` reads any v3 tree. Compile output stays v4.

The Ion tree keeps its own layout code for now. A follow-up moves it onto `TreeParts<ion_rs::Element>`, so that the path, stem, budget and stray-file rules exist once for all three profiles.

## Compatibility kit

New cases, each marked `version=3`:

- `document-tree`: a v3 manifest; a `Library` module with `def` files; `deps/` with `spec` files; a `Specs` tree; a cut stem recorded in `fileNames`; the YAML profile of one tree; a v4 file inside a v3 tree, rejected.
- `versions`: `3.1.0` accepted, `3.2.0` rejected.
- `distributions`: a single-file v3 `Specs` distribution.

The Rust adapter declares these cases. The TypeScript binding runs them as pending until its follow-up lands.

## Delivery

1. The kit refactor lands alone and changes no behaviour. Every existing layout, kit, transport and Ion tree test passes unchanged.
2. `3.1.0` in the classic model: `Specs`, the version strings, the semantic header, the JSON, YAML and Ion single-file codecs, and the support table with its conformance corpus.
3. v3 JSON and YAML trees in the kit and the transport.
4. The CLI, this draft's normative pages (`docs/spec/ir/schemas/v3/document-tree-files.md` and the 3.1.0 `whats-new`), the v3 schema's `Specs`, the compatibility-kit cases, a kb Decision Record, and the changelog.

## Out of scope

- TypeScript v3 trees and `3.1.0`, and the `3.1.0` support-table raises in morphir-elm, morphir-scala and morphir-python, are follow-up issues.
- Compile output stays v4. `write_v3` keeps writing single files.
- An application distribution has no v3 form.

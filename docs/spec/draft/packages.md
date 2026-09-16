---
title: "Packages"
description: "Specification for Packages in IR v4"
---

# Packages

A **Package** groups Morphir modules as a definition or public specification. A Distribution supplies its IR Package name and dependency context.

The [Morphir Compatibility Kit (MCK)](https://github.com/finos/morphir/blob/main/spec/mck/README.md) supplies executable compatibility cases.
The existing MCK IR suite covers the IR representation. The planned MCK package suite at `spec/package/mck/`
will cover release identity, manifests, locks, resolution, and integrity as part of [the package-system design](https://github.com/finos/morphir/issues/800).

## Package Identity

The current IR identifies a package by a canonical **Package name**, such as `morphir/SDK`.
Its `PackageDefinition` and `PackageSpecification` contain modules, with no release-version field.
The IR document's `formatVersion` identifies the serialization contract.

The proposed package system adds a **Package release ID** consisting of an authority-bearing `PackagePath`
and exact SemVer, such as `finos.org/morphir/finance/loan-rules@2.1.3`. The package release manifest records this
identity. An adapter must relate it explicitly to the embedded IR Package name; it must not infer authority
or a release version from an existing name. These package-layer rules remain Stage 0 specification work.

The package design keeps core definitions and references release-version-free. Its initial workflow uses one implicit
binding per dependency IR Package name within each consumer. Resolution selects exact releases and records them in a lock;
ordinary locked builds do not select newer versions. Explicit direct multi-binding and graph-aware coexistence are later
capabilities. Their reference encoding does not block the initial packaging workflow or change the current v4 payload.

## Package Structure

### Classic Mode
A package is part of the monolithic `morphir-ir.json` structure, containing a map of module paths to module definitions.

**PackageDefinition** and **PackageSpecification** both have an optional `modules` field:

```json
// Full form
{ "modules": { "domain/users": { ... }, "domain/orders": { ... } } }

// Compact form (empty modules omitted)
{}
```

### Document Tree Mode
A package maps to a directory structure within the `.morphir-dist` root:

- **Local Packages**: Located in `pkg/{escaped-package-path}/`.
    - Example: `pkg/my-org/my-project/`
- **Dependencies**: Located in `deps/{escaped-package-path}/@{version}/`. The segment beginning with `@` ends the
  package path; it is a bare `@` while the v4 model carries no package version (decision 0015).
    - Current example: `deps/morphir/_sdk/@/`

The [document-tree specification](../ir/schemas/v4/document-tree-files.md#dependencies) and
[morphir-typescript PR #9](https://github.com/finos/morphir-typescript/pull/9) implement decision 0015.
Current readers reject a populated version slot such as `@1.2.0` and a dependency path missing the slot.
The bare `@` marks the package/module boundary; it does not supply a release version or enable multiple releases.
Populating the reserved slot requires a future distribution/layout contract, not versions in core definitions or FQNames.
Versioned dependency graphs remain future package-system work. The tree manifest and package release manifest have separate roles.

## Namespace Mapping

IR names use the canonical word and initialism encoding in [Naming](./names.md).
Filesystem paths apply its escape rules, including `_sdk` for the canonical `SDK` segment.
Package exports use logical Module paths, so filesystem escapes and truncation do not become public export names.

A `ModuleName` is relative to its package, such as `domain/user`. A `QualifiedModuleName` combines the IR Package name
and Module name as `package:module`, such as `my-org/my-project:domain/user`. Joining both with `/` loses their boundary.
Dependency slots and export paths in the package system must preserve this distinction.

- **Package Path**: `MyOrg.MyProject` -> `my-org/my-project`
- **Module Path**: `Domain.User` -> `domain/user`

This ensures a predictable and navigational structure for shell tools and developers.

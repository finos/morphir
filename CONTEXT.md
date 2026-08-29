# Morphir

Morphir represents business logic as a language-neutral model and provides tools that read, transform, and generate that model.

## Language

**Configuration model**:
The nested set of Morphir settings after parsing, independent of the file syntax used to write them.
_Avoid_: TOML model, YAML model

**Configuration serialization**:
A file syntax that represents the configuration model, such as TOML or YAML.
_Avoid_: Configuration model

**Effective configuration**:
The configuration model produced after Morphir merges defaults and configured sources in precedence order.
_Avoid_: Final file, merged file

**Global user configuration**:
Configuration that applies to every Morphir workspace for one operating-system user.
_Avoid_: User override, project configuration

**Morphir Home**:
The per-user coordination boundary shared by Morphir components for configuration, durable state, installed artifacts, caches, and logs.
_Avoid_: Cache directory, configuration directory, user profile

**User override**:
Personal configuration stored beside one Morphir project, workspace, or workspace-member configuration and loaded above its shared settings.
_Avoid_: Global user configuration

**Secret reference**:
An inert configuration value that names an external source for a secret without containing the resolved secret.
_Avoid_: Secret, credential value

**Secret resolver**:
An explicitly invoked capability that turns one secret reference into a protected secret value.
_Avoid_: Configuration loader, automatic resolution

**Protected secret**:
A resolved secret value that redacts formatting, has no ordinary serialization path, and requires an explicit operation to expose its contents.
_Avoid_: Plain string, secret reference

## Extensions

**Morphir Extension Protocol**:
The versioned contract between a Morphir host and an extension.
_Avoid_: CLI protocol, backend protocol

**Extension**:
An independently packaged provider of one or more Morphir capabilities.
_Avoid_: Plugin, backend when referring to every extension type

**Extension host**:
The Morphir component that discovers, starts, negotiates with, and calls extensions.
_Avoid_: Extension server, backend manager

**Frontend**:
An extension capability that compiles source documents into Morphir IR.
_Avoid_: Compiler extension

**Backend**:
An extension capability that converts Morphir IR into generated artifacts.
_Avoid_: Extension when referring to any capability provider

**Capability**:
A named family of operations that an extension can provide.
_Avoid_: Feature flag, extension type

**Extension distribution**:
A versioned package that describes an extension and provides one or more artifacts that can implement it.
_Avoid_: Morphir package, loaded extension

**Extension artifact**:
A runnable payload for one extension runtime and, when applicable, one operating-system and architecture target.
_Avoid_: Extension, source package

**Installed extension catalog**:
The host's local record of verified extension distributions available for selection and activation.
_Avoid_: Package registry, loaded-extension registry

## Tools

**Tool**:
An independently packaged Morphir executable or application launched by a person.
_Avoid_: Extension, component

**Desktop**:
The graphical Morphir tool with the canonical tool identity `desktop`.
_Avoid_: Desktop extension, UI component

**Tool distribution**:
A versioned package that describes a tool and provides one or more platform-specific artifacts.
_Avoid_: Extension distribution, Morphir package, installed tool

**Installed tool catalog**:
The local record of verified tool distributions and the exact release active for each tool.
_Avoid_: Tool registry, release index, download cache

**Installed selection**:
The persistent update intent for an installed tool or extension, expressed as a release channel or an exact version.
_Avoid_: Active version, latest version

## Packages

**Morphir package**:
A versioned collection of modules that define reusable logic and types and are distributed together.
_Avoid_: Extension distribution, generated artifact

**Package requirement**:
A request for a package identity with either an exact version or a version range.
_Avoid_: Download URL, source location

**Resolved package**:
An exact package identity selected for a requirement, together with its dependency metadata, integrity, and source provenance.
_Avoid_: Package requirement, materialized package

**Source descriptor**:
A typed description of where package content can be acquired, such as a verified registry archive, immutable Git commit, workspace snapshot, or vendored tree.
_Avoid_: Package identity, package requirement

**Materialized package**:
A verified local package tree prepared from a resolved package for compilation or inspection.
_Avoid_: Package archive, compiler cache

**Registry index**:
A distributable metadata view that maps package identities and versions to dependency, integrity, and source information.
_Avoid_: Git repository, artifact store, installed extension catalog

**Release channel**:
A named, mutable policy that selects eligible package, tool, or extension versions for updates.
_Avoid_: Package identity, exact version, registry index

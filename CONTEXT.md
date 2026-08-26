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

**User override**:
Personal configuration for one Morphir project, stored inside that project's `.morphir` directory.
_Avoid_: Global user configuration

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

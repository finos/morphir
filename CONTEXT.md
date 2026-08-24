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

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

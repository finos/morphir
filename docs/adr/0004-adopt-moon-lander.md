# Use Moon-Lander for application services

Morphir's CLI and Workbench need the same configuration, diagnostic logging,
lifecycle and message dispatch. We use the published Moon-Lander modules at one
exact release version, initially `0.6.0`, rather than maintaining parallel
implementations or depending on an unreleased checkout. Renovate groups the
framework and notebook dependencies into one version update.

The current adoption pins these dependencies to Mooncakes `0.9.0`. Its eleven
public archive hashes match the actual publication checksum artifact, and the
required modules resolve independently outside this checkout. The optional
Moonx module belongs only to the portable launcher's isolated process runtime.
The actors module is not a dependency of this adoption.

The engine stays synchronous and consumes configuration values, a diagnostic
logger and synchronous mediator senders. Its packages may import the pure core,
logging, configuration, conventions, mediator and notebook packages. Configuration
file access, hosting, console drivers, asynchronous logging and asynchronous
mediator dispatch belong to apps and host adapters. `lint:engine-boundaries`
checks every engine package import, including test imports, against that boundary.

For example, a workspace can retain project identity in `morphir.json`, shared
settings in `morphir.yaml` and compiler settings in `morphir.toml`. Configuration merges
JSON/JSON5, then YAML, then TOML, preserving the origin of each value. An explicitly
selected file overrides those primary layers. Commands continue to write TOML
through the existing format-preserving editor. This supersedes ADR 0002's YAML
refusal while retaining its synchronous engine and host adapter boundary.

Diagnostic logs describe the application run; typed execution telemetry retains
its own contracts. Lifecycle and mediator integration retain the command and
worker wire formats. Worksheet notebook conversion stays in the pure engine so
the CLI and Workbench share one mapping. Jupyter can retain evaluated outputs;
DIB preserves source only, and evaluated DIB export is refused before effects.

The [adoption design](../../openspec/changes/archive/2026-10-30-adopt-moon-lander/design.html) records
the migration and qualification requirements. The dependency boundary is an
accepted design; each migration group supplies the tests for its implemented
behavior before the old implementation is removed.

The framework release selects Ion `0.6.0`. Morphir explicitly supplies the
previous 128-level reader budget and maps fuel exhaustion to the existing
resource-limit diagnostics. These dependency API adaptations preserve encoded
values, MEP framing and Workbench worker payloads; existing codec and boundary
tests qualify their compatibility. New deprecation warnings use the supported
Ion constructors without changing field order or annotations.

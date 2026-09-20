---
type: Decision Record
title: The command line is a configuration layer
state: Accepted
decided: 2026-09-20
tags: [cli, configuration, layering, precedence, provenance, starbase]
status: stable
description: Command-line flags become an ordinary layer in the existing configuration stack, above the environment, rather than precedence logic written again at each call site.
---

# The command line is a configuration layer

Morphir resolves configuration through an ordered stack of layers. The command line joins that
stack as one more layer, at precedence 700, above the environment at 600. Flags stop being
special.

The existing loader stays. Morphir does not adopt an external configuration library.

## Summary

The Morphir CLI already had a capable loader. `morphir-config` and the devkit loader merge seven
ordered layers, track where each value came from, resolve secret references and map legacy
aliases:

```
Defaults 0 → System 100 → Global 200 → Project 300 → WorkspaceMember 350 → UserOverride 400 → Environment 600
```

The command line was not one of them. Every flag was wired by hand where it was used, so each
setting restated precedence in its own way. `frontend_extension::resolve` took a flag and a
config section. `elm_modes::Mode::resolve` took the same pair, because it was copied from the
first. `selected_ir_version` took a flag and a project section. `OutOverrides` carried a flag and
an environment variable it read itself.

Some code skipped the stack entirely. `logging.rs` read `MORPHIR_LOGGING__LEVEL` as a string
literal, which restates the environment layer's own key mapping by hand. The CLI held roughly
fourteen direct `std::env::var` calls.

| Option | Outcome | Why |
| --- | --- | --- |
| Command line as a layer in the existing stack | Chosen | Precedence becomes a number, not a rule each setting repeats |
| Adopt `schematic` | Rejected | Costs provenance, secrets and legacy aliases, and still has no command-line layer |
| Keep hand-wiring, document the pattern | Rejected | Documentation does not stop the next call site from forgetting a layer |

## Why

**A forgotten layer caused a real defect.** In GH #887 a standalone single-file compile ignored
`MORPHIR_FRONTEND__ELM__DOC_COMMENTS` and `MORPHIR_FRONTEND__ELM__ORDERING`. The flag worked, so
the failure was quiet. The cause was structural. Loading configuration and resolving a setting
were separate steps, so one code path reached the resolver with no configuration loaded at all. A
missing configuration was an ordinary `None`, which is indistinguishable from a configuration that
says nothing about the key.

Adding the layer removes the category. Precedence stops being something a developer writes and
becomes a consequence of the number. Provenance reporting, the `morphir config` source listing and
the merge engine all pick the new layer up without change, because each already walks
`ConfigSourceKind`.

**A flag still has to name its key.** No rule derives `frontend.elm.ordering` from
`--elm-ordering`. That binding is declared on the clap argument, next to the flag it belongs to:

```rust
#[arg(long)]
#[config_key = "frontend.elm.ordering"]
elm_ordering: Option<String>,
```

A derive turns those annotations into the layer. Putting the binding anywhere else leaves a second
place to update, so a new flag could still be added without one. A flag with no annotation is not
a configuration setting, which keeps the annotation meaningful.

**Provenance improves the errors.** A stack that knows which layer supplied a value can say so. A
malformed mode used to report only `morphir.toml`, even when the value came from the environment.
One message now names the key and the surface that set it.

## Why not schematic

`starbase`, already a dependency, is an application framework and provides no configuration
layering. Its sibling `schematic`, by the same author, is a layered serde configuration and schema
library. It reads files, URLs and environment variables, and it generates JSON schemas.

Adopting it would cost provenance tracking, secret references, legacy aliases and the seven-layer
model unless each were rebuilt on top. It would buy a merge engine Morphir already has. The
deciding fact is that `schematic` does not treat command-line arguments as a layer either, so the
gap that prompted this decision would survive the migration.

.NET's Generic Host reaches the same shape from the other direction. It treats `AddCommandLine` as
an ordinary configuration provider, which is independent support for the choice rather than a
reason for it.

## Consequences

`ConfigSourceKind` gains a `CommandLine` variant. A derive produces the layer from annotated clap
arguments, which requires commands to use argument structs rather than inline enum variants.

Settings are read through one resolver instead of per-key precedence code. The rule that a flag
excuses a malformed configured value, reporting a warning instead of failing the run, becomes one
policy rather than something each key implements.

Direct `std::env::var("MORPHIR_*")` calls outside the configuration crate become a defect. A test
enforces their absence, so the bypass cannot return quietly.

`schematic` stays worth revisiting if JSON-schema generation becomes valuable on its own terms.

## Revisit when

Revisit when a setting registry becomes worthwhile, meaning one declaration generating the clap
argument, the typed model, the documentation table and the JSON schema. The per-setting types this
decision introduces are the data such a registry would consume.

See [The session owns the application lifecycle](/decisions/0002-the-session-owns-the-application-lifecycle.md)
for where the loaded configuration lives, and
[Configuration and lifecycle](/configuration-and-lifecycle.md) for the model as a whole.

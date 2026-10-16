# Elm source provider

`finos/morphir-engine/elm` registers the Elm frontend of [`finos/morphir-elm`](../../morphir-elm/README.md) with the
engine: language `elm`, extension `.elm`, provider `finos/morphir-elm`, profile `library`. The profile is a
`PerProject` compiler: it compiles every Elm module of a project to one unit, with types on every value and pattern.

    let engine = @engine.Engine::new()
      ..register_source_provider(@elm_adapter.provider())

The one-line form is `engine |> @elm_adapter.register()`.

The provider offers a second profile, `library-origins`, selected per project with
`frontend.profile = "library-origins"` in `morphir.toml`. It is the same compiler, and each of its units also
carries one metadata entry per value declaration of the output, `value:<fqname>`, with a `declaration` record (the
Elm name, the source path relative to the workspace as the engine reports it, `coordinate_profile`
`elm-syntax-position-v1` and the range of the name: rows and columns from 1, the end just after the last character)
and a `parameters` list for the lifted arguments, plus one provenance record annotated `morphir_elm_frontend` with
the language, profile, parser and parser version. The Scheme backend turns the declaration record into a source
comment and keeps every entry in its sidecar; an Ion checkpoint keeps them too. `library` stays the default
because a Morphir JSON checkpoint, the default output of a `morphir.json` project, cannot carry unit metadata and
the engine refuses the lossy export rather than dropping it.

A project sets `frontend.language = "elm"`, `project.name` (the dotted package name, for example `My.Pkg`) and
`project.exposed_modules` (relative to the package, for example `["Api"]`), with a checkpoint or generator backend.
The output keeps every module that it names (`OutputModules::Referenced`), so the `elm` and `moonbit` generators
give code that builds. Each Elm problem is a diagnostic at its file, with its code and range. The unit limits are
16 MiB, depth 128 and 100000 values: the depth and value budgets are the identity limits that the engine applies to
every unit (`morphir-ukvn.5.22.3.24`), so an `if` with 54 branches is refused. The engine core does
not register this provider. The `morphir` CLI registers it by default; workbench wiring is Plan B of
`morphir-ukvn.5.22.4`. A `morphir.json` project selects the provider with no `morphir.toml`.

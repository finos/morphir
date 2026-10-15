# Elm source provider

`finos/morphir-engine/elm` registers the Elm frontend of [`finos/morphir-elm`](../../morphir-elm/README.md) with the
engine: language `elm`, extension `.elm`, provider `finos/morphir-elm`, profile `library`. The profile is a
`PerProject` compiler: it compiles every Elm module of a project to one unit, with types on every value and pattern.

    let engine = @engine.Engine::new()
    @elm_adapter.register(engine)

A project sets `frontend.language = "elm"`, `project.name` (the dotted package name, for example `My.Pkg`) and
`project.exposed_modules` (relative to the package, for example `["Api"]`), with a checkpoint or generator backend.
The output keeps every module that it names (`OutputModules::Referenced`), so the `elm` and `moonbit` generators
give code that builds. Each Elm problem is a diagnostic at its file, with its code and range. The unit limits are
16 MiB, depth 128 and 100000 values: the depth and value budgets are the identity limits that the engine applies to
every unit (`morphir-ukvn.5.22.3.24`), so an `if` with 54 branches is refused. The engine core does
not register this provider; CLI and workbench wiring is `morphir-ukvn.5.22.4`.

# Classic multi-file Elm project

This on-disk project retains its classic `morphir.json`, `elm.json` and two
modules, `ElmCompat.Main` and `ElmCompat.Api`. Main defines product/order types
and business functions; Api defines request/response types and operations.

The consolidated CLI discovers its name, source directory and exposed modules.
The released reference Elm extension 0.3.1 accepts exactly one source document,
so it cannot compile this whole project yet. The executable
[scenario](scenarios.md) checks that specific rejection and the absence of an
installed IR file. This is known-limitation coverage, not successful compilation.
Beads `morphir-o6vm.15` tracks multi-source support and classic language inference.

Prepare the release using the [catalog instructions](../README.md#prepare-the-reference-elm-scenarios), then run:

```sh
mise run test:examples -- --filter morphir-elm-compat
```

The scenario registers and installs the prepared extension, inspects configuration,
and exercises the currently failing command:

```sh
morphir compile --language elm --extension morphir-elm --ir-version 3 --output installed --json
```

For a passing classic JSON project, see [the one-module example](../elm/classic-json/scenarios.md).
`test.yaml` is historical material and is not executed by `morphir itest`.

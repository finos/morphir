# Compile types from a single Elm file

[The notebook](scenario.ipynb) contains CLI commands and Rego assertions for
the adjacent [Example.elm](Example.elm). The Elm file defines a public `Amount` record and `Kind` custom
type. The native frontend is selected explicitly and currently compiles types
only. The embedded assertion provider needs no external OPA installation.

From this directory:

```sh
morphir itest . --keep-temp
```

From the repository root:

```sh
mise run test:examples -- --filter elm/single-file
```

The driver copies this directory into a fresh workspace, runs compilation,
and verifies the public types in classic v3 IR. The second command installs a
copy in `installed/morphir-ir.json` while preserving the canonical artifact.
The retained workspace can also be used to run the notebook's commands by hand.
The notebook excludes `installed/` from input copying, so outputs from a manual
run do not become inputs to the next test. `.morphir/out/` is excluded by default.

This proves compilation and installation of types, not native Elm function
lowering or native Morphir IR evaluation. Rego evaluates the assertions against
captured CLI observations. Single-file Elm does not accept an IR v4 request.

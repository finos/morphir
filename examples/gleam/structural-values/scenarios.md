---
version: 1
title: Gleam structural values
description: Preserve local bindings, tuple destructuring, list tails and list patterns in v4 IR and generated Gleam, with exact scalar spelling.
tags: [language:gleam, frontend:gleam, backend:gleam, area:compile, area:generate, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# Gleam structural values

These functions exercise local bindings, tuple destructuring, list construction
with a tail, empty and nonempty list patterns, escaped strings and whole-valued
floats. The golden compares the entire generated module. The extension tests
also inspect the IR nodes and check representative output with the Gleam compiler;
this CLI scenario does not execute the generated functions.

## Compile and generate

```yaml morphir:command
id: compile
name: Compile structural values
timeout_seconds: 60
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
```

```sh
morphir compile --ir-version 4 --json
```

```yaml morphir:assertion
id: ir
command: compile
entrypoints: [data.ir.passes]
```

```rego
package ir
import rego.v1

passes if {
  input.exitCode == 0
  ir := input.artifacts.ir.value
  ir.formatVersion == 4
  count(ir.distribution.Library.def.modules.main.Public.values) == 5
}
```

```yaml morphir:command
id: generate
name: Generate structural values
timeout_seconds: 60
```

```sh
morphir generate --target gleam --json
```

```yaml morphir:golden
id: generated-module
command: generate
actual: .morphir/out/generate/gleam.dest/main.gleam
expected_file: golden/main.gleam
line_endings: lf
```

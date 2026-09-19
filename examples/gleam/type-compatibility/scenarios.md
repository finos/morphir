---
version: 1
title: Gleam type compatibility
description: Compile labelled records, discriminated unions, aliases, opaque types and imported generic references to IR v3 and v4, then generate Gleam source.
tags: [language:gleam, frontend:gleam, backend:gleam, area:compile, area:generate, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# Gleam type compatibility

The native Gleam extension supports type declarations in both IR versions.
Records use labelled ADT constructors. These scenarios inspect the real CLI's
IR and compare both generated modules against checked-in golden files. The same
expectations apply to v3 and v4; LF normalization permits CRLF checkouts.
Incremental cache behavior is covered by CLI tests.
Sum types preserve each constructor's discriminant and payload fields.
Function bodies remain available in v4; v3 reports them as skipped.

## Compile and generate v4

```yaml morphir:command
id: compile
name: Compile Gleam types
timeout_seconds: 60
stdout_json: true
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
  modules := ir.distribution.Library.def.modules
  count(modules) == 2
  modules.model.Public.types.customer.Public
  modules.api.Public.types.customer.Public
  modules.model.Public.types.secret.Public
  contains(json.marshal(modules), "morphir/SDK:basics#int")
  contains(json.marshal(modules), "examples/gleam-types:model#customer")
}
```

```yaml morphir:command
id: generate
name: Generate Gleam types
timeout_seconds: 60
```

```sh
morphir generate --target gleam --json
```

```yaml morphir:golden
id: generated-model
command: generate
actual: .morphir/out/generate/gleam.dest/model.gleam
expected_file: golden/model.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-api
command: generate
actual: .morphir/out/generate/gleam.dest/api.gleam
expected_file: golden/api.gleam
line_endings: lf
```

## Compile and generate v3

```yaml morphir:command
id: compile
name: Compile Gleam types
timeout_seconds: 60
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
```

```sh
morphir compile --ir-version 3 --json
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
  ir.formatVersion == 3
  ir.distribution[0] == "Library"
  count(ir.distribution[3].modules) == 2
  contains(json.marshal(ir), "TypeAliasDefinition")
  contains(json.marshal(ir), "CustomTypeDefinition")
}
```

```yaml morphir:command
id: generate
name: Generate Gleam types
timeout_seconds: 60
```

```sh
morphir generate --target gleam --json
```

```yaml morphir:golden
id: generated-model
command: generate
actual: .morphir/out/generate/gleam.dest/model.gleam
expected_file: golden/model.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-api
command: generate
actual: .morphir/out/generate/gleam.dest/api.gleam
expected_file: golden/api.gleam
line_endings: lf
```

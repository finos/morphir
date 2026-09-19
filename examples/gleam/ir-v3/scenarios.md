---
version: 1
title: Morphir V3 defined in Gleam
description: Compile the complete V3 data model into V3 IR and regenerate all twelve modules against fixed golden files.
tags: [language:gleam, frontend:gleam, backend:gleam, area:compile, area:generate, ir:v3, kind:positive, suite:offline, workspace:directory]
provider: rego
workspace:
  kind: directory
  path: .
  exclude: [build]
---

# Morphir describing Morphir

This is a type-level model of Morphir V3, including operations that the Gleam
extension cannot yet execute. See [the representation notes](README.md) for
source provenance, completeness, and the character, decimal and record mappings.
The companion Rust test checks the type inventory, structural roundtrip and,
when explicitly enabled, real Gleam compiler acceptance of both source and output.

## Compile and regenerate the V3 model {#dogfood}

```yaml morphir:command
id: compile
name: Compile the V3 model
timeout_seconds: 60
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
```

```sh
morphir compile --ir-version 3 --json
```

```yaml morphir:assertion
id: complete-model
command: compile
entrypoints: [data.model.passes]
```

```rego
package model
import rego.v1

passes if {
  input.exitCode == 0
  ir := input.artifacts.ir.value
  ir.formatVersion == 3
  ir.distribution[0] == "Library"
  ir.distribution[1] == [["morphir"], ["ir", "model"]]
  modules := ir.distribution[3].modules
  count(modules) == 12
  sum([count(entry[1].value.types) | some entry in modules]) == 30
  every entry in modules {
    entry[1].access == "Public"
    count(entry[1].value.values) == 0
  }
}
```

```yaml morphir:command
id: generate
name: Regenerate the V3 model in Gleam
timeout_seconds: 60
```

```sh
morphir generate --target gleam --json
```

```yaml morphir:golden
id: generated-access-controlled
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/access_controlled.gleam
expected_file: golden/morphir/ir/access_controlled.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-distribution
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/distribution.gleam
expected_file: golden/morphir/ir/distribution.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-documented
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/documented.gleam
expected_file: golden/morphir/ir/documented.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-fqname
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/fqname.gleam
expected_file: golden/morphir/ir/fqname.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-literal
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/literal.gleam
expected_file: golden/morphir/ir/literal.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-module
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/module.gleam
expected_file: golden/morphir/ir/module.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-name
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/name.gleam
expected_file: golden/morphir/ir/name.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-package
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/package.gleam
expected_file: golden/morphir/ir/package.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-path
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/path.gleam
expected_file: golden/morphir/ir/path.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-qname
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/qname.gleam
expected_file: golden/morphir/ir/qname.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-type
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/type_.gleam
expected_file: golden/morphir/ir/type_.gleam
line_endings: lf
```

```yaml morphir:golden
id: generated-value
command: generate
actual: .morphir/out/generate/gleam.dest/morphir/ir/value.gleam
expected_file: golden/morphir/ir/value.gleam
line_endings: lf
```

---
version: 1
title: Single-file Elm functions
description: Compile an annotated arithmetic function without project configuration using the reference Elm frontend.
tags: [language:elm, frontend:morphir-elm, config:none, area:compile, ir:v3, kind:positive, suite:elm-reference, workspace:directory]
provider: rego
workspace: {kind: directory, path: '.', exclude: [installed]}
---

# Single-file Elm functions

Prepare extension 0.3.0 with `mise run examples:prepare-elm -- /path/to/morphir-elm-extension` first. The driver installs the prepared artifact into a fresh Morphir home. Missing prerequisites fail; the scenario does not download them. Compilation checks IR structure, not function evaluation.

## Compile functions

### Register the prepared local extension repository

```yaml morphir:command
id: repository
name: Register the prepared local extension repository
timeout_seconds: 60
```

```sh
morphir extension repository add fixture --directory .itest/elm
```

```yaml morphir:assertion
id: repository-check
command: repository
entrypoints: [data.repository.passes]
```

```rego
package repository
import rego.v1

passes if {
    input.exitCode == 0
}
```

### Install reference Elm 0.3.0

```yaml morphir:command
id: install
name: Install reference Elm 0.3.0
timeout_seconds: 60
```

```sh
morphir extension install morphir-elm --repository fixture --version 0.3.0
```

```yaml morphir:assertion
id: install-check
command: install
entrypoints: [data.install.passes]
```

```rego
package install
import rego.v1

passes if {
    input.exitCode == 0
    contains(input.stdout, "morphir-elm")
}
```

### Compile an arithmetic function

```yaml morphir:command
id: compile
name: Compile an arithmetic function
timeout_seconds: 60
stdout_json: true
captures:
  - {name: ir, path: installed/morphir-ir.json, format: json}
```

```sh
morphir compile --input Example.elm --extension morphir-elm --package-name examples/functions --output installed --json
```

```yaml morphir:assertion
id: compile-check
command: compile
entrypoints: [data.compile.passes]
```

```rego
package compile
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    ir.formatVersion == 3
    ir.distribution[1] == [["examples"], ["functions"]]
    modules := ir.distribution[3].modules
    count(modules) == 1
    values := modules[0][1].value.values
    count(values) == 1
    values[0][0] == ["add"]
    definition := values[0][1].value.value
    count(definition.inputTypes) == 2
    definition.inputTypes[0][0] == ["left"]
    definition.inputTypes[1][0] == ["right"]
    definition.body[0] == "Apply"
    definition.body[2][0] == "Apply"
    definition.body[2][2][0] == "Reference"
    definition.body[2][2][2] == [[["morphir"], ["s", "d", "k"]], [["basics"]], ["add"]]
    definition.body[2][3][0] == "Variable"
    definition.body[2][3][2] == ["left"]
    definition.body[3][0] == "Variable"
    definition.body[3][2] == ["right"]
}
```

---
version: 1
title: TOML Elm project
description: Discover a TOML project and compile two public modules with the native Elm types-only frontend. This does not test function lowering.
tags: [language:elm, frontend:elm-native, config:toml, area:compile, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# TOML Elm project

Discover a TOML project and compile two public modules with the native Elm types-only frontend. This does not test function lowering.

## Compile types

### Discover project configuration

```yaml morphir:command
id: configuration
name: Discover project configuration
timeout_seconds: 60
stdout_json: true
```

```sh
morphir config show --json
```

```yaml morphir:assertion
id: configuration-check
command: configuration
entrypoints: [data.configuration.passes]
```

```rego
package configuration
import rego.v1

passes if {
    input.exitCode == 0
    endswith(input.stdoutJson.project_config, "morphir.toml")
    input.stdoutJson.config.project.name == "SimpleProject"
    input.stdoutJson.config.frontend.language == "elm"
}
```

### Compile public types

```yaml morphir:command
id: compile
name: Compile public types
timeout_seconds: 60
stdout_json: true
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/compile.json, format: json}
```

```sh
morphir compile --extension morphir-elm-native --json
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
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "simple-project"
    modules := ir.distribution.Library.def.modules
    count(modules) == 2
    amount := modules["core"].Public.types["amount"].Public.TypeAliasDefinition
    amount.typeParams == []
    object.keys(amount.typeExp.Record.fields) == {"value"}
    amount.typeExp.Record.fields.value.Reference.fqname == "morphir/SDK:basics#int"
    kind := modules.utils.Public.types.kind.Public.CustomTypeDefinition
    kind.constructors == {"simple": [], "detailed": []}
    input.artifacts.result.value.task == "compile"
    input.artifacts.result.value.ir.version == "v4"
}
```

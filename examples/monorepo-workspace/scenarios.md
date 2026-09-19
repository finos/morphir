---
version: 1
title: Multi-project Elm workspace
description: Select each declared member by path and name, compile its types, and keep package identity and task outputs separate. This does not test cross-package dependency resolution.
tags: [language:elm, frontend:elm-native, config:toml, area:workspace, area:compile, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
workspace: {kind: directory, path: ".", exclude: [installed]}
---

# Multi-project Elm workspace

Select each declared member by path and name, compile its types, and keep package identity and task outputs separate. This does not test cross-package dependency resolution.

## Compile core by path

### Select core by path

```yaml morphir:command
id: path
name: Select core by path
timeout_seconds: 60
stdout_json: true
captures:
  - {name: installed, path: installed/morphir-ir.json, format: json}
  - {name: ir, path: .morphir/out/packages/core/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/packages/core/compile.json, format: json}
  - {name: other, path: .morphir/out/packages/utils/compile.json, format: exists}
```

```sh
morphir compile --project packages/core --extension morphir-elm-native --output installed --json
```

```yaml morphir:assertion
id: path-check
command: path
entrypoints: [data.path.passes]
```

```rego
package path
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    input.artifacts.installed.value == ir
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "core"
    object.keys(ir.distribution.Library.def.modules) == {"types", "functions"}
    input.artifacts.result.value.module == "packages/core"
    input.artifacts.other.kind == "missing"
}
```

## Compile core by name

### Select core by name

```yaml morphir:command
id: name
name: Select core by name
timeout_seconds: 60
stdout_json: true
captures:
  - {name: installed, path: installed/morphir-ir.json, format: json}
  - {name: ir, path: .morphir/out/packages/core/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/packages/core/compile.json, format: json}
  - {name: other, path: .morphir/out/packages/utils/compile.json, format: exists}
```

```sh
morphir compile --project Core --extension morphir-elm-native --output installed --json
```

```yaml morphir:assertion
id: name-check
command: name
entrypoints: [data.name.passes]
```

```rego
package name
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    input.artifacts.installed.value == ir
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "core"
    object.keys(ir.distribution.Library.def.modules) == {"types", "functions"}
    input.artifacts.result.value.module == "packages/core"
    input.artifacts.other.kind == "missing"
}
```

## Compile utils by path

### Select utils by path

```yaml morphir:command
id: path
name: Select utils by path
timeout_seconds: 60
stdout_json: true
captures:
  - {name: installed, path: installed/morphir-ir.json, format: json}
  - {name: ir, path: .morphir/out/packages/utils/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/packages/utils/compile.json, format: json}
  - {name: other, path: .morphir/out/packages/core/compile.json, format: exists}
```

```sh
morphir compile --project packages/utils --extension morphir-elm-native --output installed --json
```

```yaml morphir:assertion
id: path-check
command: path
entrypoints: [data.path.passes]
```

```rego
package path
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    input.artifacts.installed.value == ir
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "utils"
    object.keys(ir.distribution.Library.def.modules) == {"helpers"}
    input.artifacts.result.value.module == "packages/utils"
    input.artifacts.other.kind == "missing"
}
```

## Compile utils by name

### Select utils by name

```yaml morphir:command
id: name
name: Select utils by name
timeout_seconds: 60
stdout_json: true
captures:
  - {name: installed, path: installed/morphir-ir.json, format: json}
  - {name: ir, path: .morphir/out/packages/utils/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/packages/utils/compile.json, format: json}
  - {name: other, path: .morphir/out/packages/core/compile.json, format: exists}
```

```sh
morphir compile --project Utils --extension morphir-elm-native --output installed --json
```

```yaml morphir:assertion
id: name-check
command: name
entrypoints: [data.name.passes]
```

```rego
package name
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    input.artifacts.installed.value == ir
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "utils"
    object.keys(ir.distribution.Library.def.modules) == {"helpers"}
    input.artifacts.result.value.module == "packages/utils"
    input.artifacts.other.kind == "missing"
}
```

## Compile default member

### Select the default core member

```yaml morphir:command
id: path
name: Select the default core member
timeout_seconds: 60
stdout_json: true
captures:
  - {name: installed, path: installed/morphir-ir.json, format: json}
  - {name: ir, path: .morphir/out/packages/core/compile.dest/morphir-ir.json, format: json}
  - {name: result, path: .morphir/out/packages/core/compile.json, format: json}
  - {name: other, path: .morphir/out/packages/utils/compile.json, format: exists}
```

```sh
morphir compile --extension morphir-elm-native --output installed --json
```

```yaml morphir:assertion
id: path-check
command: path
entrypoints: [data.path.passes]
```

```rego
package path
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    ir := input.artifacts.ir.value
    input.artifacts.installed.value == ir
    ir.formatVersion == 4
    ir.distribution.Library.packageName == "core"
    object.keys(ir.distribution.Library.def.modules) == {"types", "functions"}
    input.artifacts.result.value.module == "packages/core"
    input.artifacts.other.kind == "missing"
}
```

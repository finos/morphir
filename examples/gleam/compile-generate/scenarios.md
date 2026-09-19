---
version: 1
title: Gleam compilation and generation
description: Compile a public Gleam function to Morphir IR and generate Gleam source with the built-in backend. The scenario checks generated text and task provenance; it does not execute the generated program.
tags: [language:gleam, frontend:gleam, backend:gleam, config:toml, area:compile, area:generate, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# Gleam compilation and generation

Compile a public Gleam function to Morphir IR and generate Gleam source with the built-in backend. The scenario checks generated text and task provenance; it does not execute the generated program.

## Compile and generate

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
    input.stdoutJson.config.project.name == "examples/hello"
    input.stdoutJson.config.frontend.language == "gleam"
}
```

### Compile a public function

```yaml morphir:command
id: compile
name: Compile a public function
timeout_seconds: 60
stdout_json: true
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
```

```sh
morphir compile --json
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
    ir.distribution.Library.packageName == "examples/hello"
    ir.distribution.Library.def.modules.main.Public.values.hello.Public
}
```

### Generate Gleam from the compile task

```yaml morphir:command
id: generate
name: Generate Gleam from the compile task
timeout_seconds: 60
stdout_json: true
captures:
  - {name: result, path: .morphir/out/generate/gleam.json, format: json}
  - {name: source, path: .morphir/out/generate/gleam.dest/main.gleam, format: text}
```

```sh
morphir generate --target gleam --json
```

```yaml morphir:assertion
id: generate-check
command: generate
entrypoints: [data.generate.passes]
```

```rego
package generate
import rego.v1

passes if {
    input.exitCode == 0
    input.artifacts.result.value.task == "generate/gleam"
    input.artifacts.result.value.inputs == ["compile"]
    contains(input.artifacts.source.value, "pub fn hello")
    contains(input.artifacts.source.value, "world")
}
```

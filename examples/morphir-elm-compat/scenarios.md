---
version: 1
title: Classic morphir.json project
description: Discover a classic project and expose the released reference frontend limitation on multiple source files.
tags: [language:elm, frontend:morphir-elm, config:json, area:compile, ir:v3, kind:negative, coverage:known-limitation, suite:elm-reference, workspace:directory]
provider: rego
workspace: {kind: directory, path: '.', exclude: [installed]}
---

# Classic morphir.json project

Prepare extension 0.3.1 with `mise run examples:prepare-elm -- /path/to/morphir-elm-extension` first. The driver installs the prepared artifact into a fresh Morphir home. Missing prerequisites fail; the scenario does not download them. Compilation checks IR structure, not function evaluation.

The released extension accepts exactly one source document. This scenario records the current rejection, not successful project compilation. The full project remains on disk for follow-up `morphir-o6vm.15`.

## Multi-source limitation

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

### Install reference Elm 0.3.1

```yaml morphir:command
id: install
name: Install reference Elm 0.3.1
timeout_seconds: 60
```

```sh
morphir extension install morphir-elm --repository fixture --version 0.3.1
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

### Discover classic project configuration

```yaml morphir:command
id: configuration
name: Discover classic project configuration
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
    endswith(input.stdoutJson.project_config, "morphir.json")
    input.stdoutJson.config.project.name == "ElmCompat"
    input.stdoutJson.config.project.source_directory == "src"
    input.stdoutJson.config.project.exposed_modules == ["Main", "Api"]
}
```

### Report unsupported multi-source compilation

```yaml morphir:command
id: compile
name: Report unsupported multi-source compilation
timeout_seconds: 60
captures:
  - {name: installed, path: installed/morphir-ir.json, format: exists}
```

```sh
morphir compile --language elm --extension morphir-elm --ir-version 3 --output installed --json
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
    input.exitCode == 1
    input.artifacts.installed.kind == "missing"
    contains(input.stderr, "requires exactly one source document")
}
```

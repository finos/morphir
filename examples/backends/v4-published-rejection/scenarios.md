---
version: 1
title: Published backends reject canonical v4 IR
description: Record the pinned Avro and OpenAPI releases rejecting canonical v4 access wrappers. Passing proves the rejection, not successful v4 generation.
tags: [language:elm, frontend:elm-native, config:toml, area:compile, area:generate, area:extension, ir:v4, kind:negative, coverage:known-limitation, suite:wasm-backends, workspace:directory]
provider: rego
workspace: {kind: directory, path: '.', exclude: [installed, repository]}
---

# Published backends reject canonical v4 IR

Prepare bundles with `mise run ci:fetch-published-bundles` then
`mise run examples:prepare-backends`. Each heading starts with a fresh workspace.
Avro 0.1.1 and OpenAPI 0.1.0 advertise v4 support but their readers require the old
`access` field. Native Elm now emits canonical `Public` wrappers. These cases
record the rejection for Avro, JSON Schema and OpenAPI generation.

Beads `morphir-o6vm.16` tracks new backend releases and pin updates. Replace these
negative expectations with fixed schema assertions when the releases support
canonical v4. The adjacent Avro/OpenAPI examples use explicit v3 compilation
and cover successful generation.

## Avro rejects canonical v4 {#avro}

### Create a local repository

```yaml morphir:command
id: initialize
name: Create a local repository
timeout_seconds: 180
```

```sh
morphir extension repository init repository
```

```yaml morphir:assertion
id: initialize-check
command: initialize
entrypoints: [data.initialize.passes]
```

```rego
package initialize
import rego.v1

passes if {
    input.exitCode == 0

}
```

### Register the repository

```yaml morphir:command
id: register
name: Register the repository
timeout_seconds: 180
```

```sh
morphir extension repository add fixture --directory repository
```

```yaml morphir:assertion
id: register-check
command: register
entrypoints: [data.register.passes]
```

```rego
package register
import rego.v1

passes if {
    input.exitCode == 0

}
```

### Publish the prepared bundle

```yaml morphir:command
id: publish
name: Publish the prepared bundle
timeout_seconds: 180
```

```sh
morphir extension repository publish fixture --bundle .itest/avro
```

```yaml morphir:assertion
id: publish-check
command: publish
entrypoints: [data.publish.passes]
```

```rego
package publish
import rego.v1

passes if {
    input.exitCode == 0
    contains(input.stdout, "morphir-avro")
}
```

### Install the pinned provider 0.1.1

```yaml morphir:command
id: install
name: Install the pinned provider 0.1.1
timeout_seconds: 180
```

```sh
morphir extension install morphir-avro --repository fixture --version 0.1.1
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
    contains(input.stdout, "morphir-avro")
}
```

### Compile the on-disk customer record

```yaml morphir:command
id: compile
name: Compile the on-disk customer record
timeout_seconds: 180
stdout_json: true
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
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
    ir.distribution.Library.packageName == "examples/published"
    record := ir.distribution.Library.def.modules.domain.Public.types.customer.Public.TypeAliasDefinition.typeExp.Record
    record.fields.age.Reference.fqname == "morphir/SDK:basics#int"
    record.fields.name.Reference.fqname == "morphir/SDK:string#string"
}
```

### Observe rejection from avro schemas from the compile task

```yaml morphir:command
id: generate_avro
name: Generate avro schemas from the compile task
timeout_seconds: 180
stdout_json: true
```

```sh
morphir generate --target avro --option representation=json --option projection=schemas --output installed/avro --json
```

```yaml morphir:assertion
id: generate_avro-check
command: generate_avro
entrypoints: [data.generate_avro.passes]
```

```rego
package generate_avro
import rego.v1

passes if {
    input.exitCode == 1
    input.stdoutJson.success == false
    input.stdoutJson.artifacts == []
    some diagnostic in input.stdoutJson.diagnostics
    diagnostic.level == "error"
    diagnostic.code == "invalid_ir"
    contains(diagnostic.message, "missing field `access`")
}
```

## OpenAPI and JSON Schema reject canonical v4 {#openapi}

### Create a local repository

```yaml morphir:command
id: initialize
name: Create a local repository
timeout_seconds: 180
```

```sh
morphir extension repository init repository
```

```yaml morphir:assertion
id: initialize-check
command: initialize
entrypoints: [data.initialize.passes]
```

```rego
package initialize
import rego.v1

passes if {
    input.exitCode == 0

}
```

### Register the repository

```yaml morphir:command
id: register
name: Register the repository
timeout_seconds: 180
```

```sh
morphir extension repository add fixture --directory repository
```

```yaml morphir:assertion
id: register-check
command: register
entrypoints: [data.register.passes]
```

```rego
package register
import rego.v1

passes if {
    input.exitCode == 0

}
```

### Publish the prepared bundle

```yaml morphir:command
id: publish
name: Publish the prepared bundle
timeout_seconds: 180
```

```sh
morphir extension repository publish fixture --bundle .itest/openapi
```

```yaml morphir:assertion
id: publish-check
command: publish
entrypoints: [data.publish.passes]
```

```rego
package publish
import rego.v1

passes if {
    input.exitCode == 0
    contains(input.stdout, "morphir-openapi")
}
```

### Install the pinned provider 0.1.0

```yaml morphir:command
id: install
name: Install the pinned provider 0.1.0
timeout_seconds: 180
```

```sh
morphir extension install morphir-openapi --repository fixture --version 0.1.0
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
    contains(input.stdout, "morphir-openapi")
}
```

### Compile the on-disk customer record

```yaml morphir:command
id: compile
name: Compile the on-disk customer record
timeout_seconds: 180
stdout_json: true
captures:
  - {name: ir, path: .morphir/out/compile.dest/morphir-ir.json, format: json}
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
    ir.distribution.Library.packageName == "examples/published"
    record := ir.distribution.Library.def.modules.domain.Public.types.customer.Public.TypeAliasDefinition.typeExp.Record
    record.fields.age.Reference.fqname == "morphir/SDK:basics#int"
    record.fields.name.Reference.fqname == "morphir/SDK:string#string"
}
```

### Observe rejection from json-schema schemas from the compile task

```yaml morphir:command
id: generate_json_schema
name: Generate json-schema schemas from the compile task
timeout_seconds: 180
stdout_json: true
```

```sh
morphir generate --target json-schema --output installed/json-schema --json
```

```yaml morphir:assertion
id: generate_json_schema-check
command: generate_json_schema
entrypoints: [data.generate_json_schema.passes]
```

```rego
package generate_json_schema
import rego.v1

passes if {
    input.exitCode == 1
    input.stdoutJson.success == false
    input.stdoutJson.artifacts == []
    some diagnostic in input.stdoutJson.diagnostics
    diagnostic.level == "error"
    diagnostic.code == "invalid_ir"
    contains(diagnostic.message, "missing field `access`")
}
```

### Observe rejection from openapi schemas from the compile task

```yaml morphir:command
id: generate_openapi
name: Generate openapi schemas from the compile task
timeout_seconds: 180
stdout_json: true
```

```sh
morphir generate --target openapi --output installed/openapi --json
```

```yaml morphir:assertion
id: generate_openapi-check
command: generate_openapi
entrypoints: [data.generate_openapi.passes]
```

```rego
package generate_openapi
import rego.v1

passes if {
    input.exitCode == 1
    input.stdoutJson.success == false
    input.stdoutJson.artifacts == []
    some diagnostic in input.stdoutJson.diagnostics
    diagnostic.level == "error"
    diagnostic.code == "invalid_ir"
    contains(diagnostic.message, "missing field `access`")
}
```

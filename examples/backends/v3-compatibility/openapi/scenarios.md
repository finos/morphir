---
version: 1
title: Installed OpenAPI and JSON Schema backend retains v3 compatibility
description: Publish and install the pinned OpenAPI and JSON Schema backend, compile a customer record as v3 IR, and assert generated schemas and task provenance.
tags: [language:elm, frontend:elm-native, backend:openapi, backend:json-schema, config:toml, area:compile, area:generate, area:extension, ir:v3, kind:positive, suite:wasm-backends, workspace:directory]
provider: rego
workspace: {kind: directory, path: '.', exclude: [installed, repository]}
---

# Installed OpenAPI and JSON Schema backend retains v3 compatibility

Prepare the pinned bundles with `mise run ci:fetch-published-bundles` and
`mise run examples:prepare-backends`. Each heading starts with a fresh workspace
and Morphir home. These cases retain explicit v3 support alongside the default
v4 workflows in the adjacent Avro and OpenAPI examples. They check type schemas,
not function evaluation or inferred API operations.

## OpenAPI and JSON Schema from v3 IR {#openapi}

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
morphir extension repository publish fixture --bundle .itest/bundle
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

### Install the pinned provider 0.1.1

```yaml morphir:command
id: install
name: Install the pinned provider 0.1.1
timeout_seconds: 180
```

```sh
morphir extension install morphir-openapi --repository fixture --version 0.1.1
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
morphir compile --extension morphir-elm-native --ir-version 3 --json
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
    ir.distribution[0] == "Library"
    ir.distribution[1] == [["examples"], ["compatibility"]]
    modules := ir.distribution[3].modules
    count(modules) == 1
    modules[0][0] == [["domain"]]
    modules[0][1].access == "Public"
    types := modules[0][1].value.types
    count(types) == 1
    types[0][0] == ["customer"]
    types[0][1].access == "Public"
    alias := types[0][1].value.value
    alias[0] == "TypeAliasDefinition"
    alias[2][0] == "Record"
    count(alias[2][2]) == 2
}
```

### Generate json-schema schemas from the compile task

```yaml morphir:command
id: generate_json_schema
name: Generate json-schema schemas from the compile task
timeout_seconds: 180
stdout_json: true
captures:
  - {name: result, path: .morphir/out/generate/json-schema.json, format: json}
  - {name: schema, path: .morphir/out/generate/json-schema.dest/domain.Customer.schema.json, format: json}
  - {name: installed, path: installed/json-schema/domain.Customer.schema.json, format: json}
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
    input.exitCode == 0
    input.stdoutJson.success == true
    input.artifacts.result.value.task == "generate/json-schema"
    input.artifacts.result.value.inputs == ["compile"]
    schema := input.artifacts.schema.value
    schema == input.artifacts.installed.value
    schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    schema.title == "Customer"
    customer := schema
    customer.type == "object"
    customer.properties.age.type == "integer"
    customer.properties.name.type == "string"
    count(customer.properties) == 2
    sort(customer.required) == ["age", "name"]
}
```

### Generate openapi schemas from the compile task

```yaml morphir:command
id: generate_openapi
name: Generate openapi schemas from the compile task
timeout_seconds: 180
stdout_json: true
captures:
  - {name: result, path: .morphir/out/generate/openapi.json, format: json}
  - {name: schema, path: .morphir/out/generate/openapi.dest/openapi.json, format: json}
  - {name: installed, path: installed/openapi/openapi.json, format: json}
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
    input.exitCode == 0
    input.stdoutJson.success == true
    input.artifacts.result.value.task == "generate/openapi"
    input.artifacts.result.value.inputs == ["compile"]
    schema := input.artifacts.schema.value
    schema == input.artifacts.installed.value
    schema.openapi == "3.1.0"
    schema.paths == {}
    customer := schema.components.schemas.Customer
    customer.type == "object"
    customer.properties.age.type == "integer"
    customer.properties.name.type == "string"
    count(customer.properties) == 2
    sort(customer.required) == ["age", "name"]
}
```

---
version: 1
title: Installed Avro backend
description: Publish and install a pinned WASM backend, compile an on-disk Elm record, and verify generated schemas and task provenance through real CLI commands.
tags: [language:elm, frontend:elm-native, backend:avro, config:toml, area:compile, area:generate, area:extension, ir:v4, kind:positive, suite:wasm-backends, workspace:directory]
provider: rego
workspace: {kind: directory, path: '.', exclude: [installed, repository]}
---

# Installed Avro backend

Prepare the pinned bundles with `mise run ci:fetch-published-bundles` and
`mise run examples:prepare-backends`. Missing prerequisites fail. The driver
copies this on-disk project into a temporary workspace with a fresh Morphir home.
The commands below publish and install morphir-avro 0.1.2; they do not download it.
Native Elm supplies types only. These assertions cover schemas, not function
evaluation.

## Compile and generate {#compile-generate}

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
    contains(input.stdout, "morphir-avro")
}
```

### Install the pinned provider 0.1.2

```yaml morphir:command
id: install
name: Install the pinned provider 0.1.2
timeout_seconds: 180
```

```sh
morphir extension install morphir-avro --repository fixture --version 0.1.2
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
    ir.distribution.Library.packageName == "examples/avro"
    record := ir.distribution.Library.def.modules.domain.Public.types.customer.Public.TypeAliasDefinition.typeExp.Record
    record.fields.age.Reference.fqname == "morphir/SDK:basics#int"
    record.fields.name.Reference.fqname == "morphir/SDK:string#string"
}
```

### Generate avro schemas from the compile task

```yaml morphir:command
id: generate_avro
name: Generate avro schemas from the compile task
timeout_seconds: 180
stdout_json: true
captures:
  - {name: result, path: .morphir/out/generate/avro.json, format: json}
  - {name: schema, path: .morphir/out/generate/avro.dest/examples/avro/domain/Customer.avsc, format: json}
  - {name: installed, path: installed/avro/examples/avro/domain/Customer.avsc, format: json}
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
    input.exitCode == 0
    input.stdoutJson.success == true
    input.artifacts.result.value.task == "generate/avro"
    input.artifacts.result.value.inputs == ["compile"]
    schema := input.artifacts.schema.value
    schema == input.artifacts.installed.value
    schema.type == "record"
    schema.name == "Customer"
    schema.namespace == "examples.avro.domain"
    count(schema.fields) == 2
    fields := {field.name: field.type | some field in schema.fields}
    fields == {"age": "long", "name": "string"}
}
```

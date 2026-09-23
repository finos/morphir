---
version: 1
title: Publish and consume a local Library
description: Compile a Gleam model, create and sign a classic V4 Library, publish it into an absent local registry, then independently resolve, restore, generate and compile it in a consumer project.
tags: [area:package, area:compile, area:generate, language:gleam, ir:v4, kind:positive, suite:macos-publisher, workspace:directory]
provider: rego
---

# Publish and consume a local Library

This scenario runs on macOS, the first qualified local publication platform.
It uses deliberately public **test-only** signing seeds in `fixture/keys` and
starts with an absent registry. The consumer directory contains no signing key.
The signed bootstrap root and its pinned policy are separate, frozen inputs.

## Publish and consume from source {#publish-and-consume}

### Compile the author's model

```yaml morphir:command
id: compile-author
name: Compile the author project's Gleam source to classic V4 IR
timeout_seconds: 90
stdout_json: true
captures:
  - {name: ir, path: compiled/morphir-ir.json, format: json}
```

```sh
morphir compile --ir-version 4 --output compiled --json
```

```yaml morphir:assertion
id: compiled-author-ir
command: compile-author
entrypoints: [data.author_compiled.passes]
```

```rego
package author_compiled
import rego.v1

passes if {
    input.exitCode == 0
    input.artifacts.ir.value.formatVersion == 4
    input.artifacts.ir.value.distribution.Library.packageName == "examples/hello"
    input.artifacts.ir.value.distribution.Library.def.modules.main.Public.values.hello.Public
}
```

### Create and sign the Library

```yaml morphir:command
id: create
name: Create a verified Library bundle
timeout_seconds: 60
stdout_json: true
captures:
  - {name: manifest, path: bundle/manifest.json, format: json}
```

```sh
morphir package create --ir compiled/morphir-ir.json --manifest-input authoring.json --output bundle --json
```

```yaml morphir:assertion
id: created-bundle
command: create
entrypoints: [data.bundle_created.passes]
```

```rego
package bundle_created
import rego.v1

passes if {
    input.exitCode == 0
    manifest := input.artifacts.manifest.value
    manifest.kind == "Library"
    manifest.packagePath == "example.com/finance/hello"
    manifest.version == "1.0.0"
    manifest.dependencies == {}
    manifest.ir.packageName == "examples/hello"
    startswith(manifest.content["ir.json"], "sha256:")
}
```

```yaml morphir:command
id: sign
name: Sign the release with the explicit test publisher key
timeout_seconds: 60
stdout_json: true
captures:
  - {name: envelope, path: release/envelope.json, format: json}
```

```sh
morphir package sign --bundle bundle --key-file fixture/keys/publisher.key --output release --json
```

```yaml morphir:assertion
id: signed-release
command: sign
entrypoints: [data.release_signed.passes]
```

```rego
package release_signed
import rego.v1

passes if {
    input.exitCode == 0
    count(input.artifacts.envelope.value.signatures) == 1
}
```

### Initialize, prepare, sign and publish the registry view

```yaml morphir:command
id: initialize-registry
name: Initialize absent registry with a pinned signed root
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package registry init --root fixture/root.json --policy fixture/policy.json --registry registry --publisher-state publisher-state --json
```

```yaml morphir:assertion
id: initialized-registry
command: initialize-registry
entrypoints: [data.registry_initialized.passes]
```

```rego
package registry_initialized
import rego.v1

passes if { input.exitCode == 0 }
```

```yaml morphir:command
id: prepare
name: Prepare an exact successor without committing it
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package registry prepare --bundle bundle --release release --policy fixture/policy.json --registry registry --publisher-state publisher-state --expires 2098-01-01T00:00:00Z --output draft --json
```

```yaml morphir:assertion
id: prepared-successor
command: prepare
entrypoints: [data.successor_prepared.passes]
```

```rego
package successor_prepared
import rego.v1

passes if { input.exitCode == 0 }
```

```yaml morphir:command
id: sign-proposal
name: Sign successor metadata with distinct registry-role keys
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package registry sign-proposal --draft draft/draft.json --targets-key-file fixture/keys/targets.key --snapshot-key-file fixture/keys/snapshot.key --timestamp-key-file fixture/keys/timestamp.key --output proposal.json --json
```

```yaml morphir:assertion
id: signed-proposal
command: sign-proposal
entrypoints: [data.proposal_signed.passes]
```

```rego
package proposal_signed
import rego.v1

passes if { input.exitCode == 0 }
```

```yaml morphir:command
id: publish
name: Commit the caller-signed successor transaction
timeout_seconds: 90
stdout_json: true
captures:
  - {name: timestamp, path: registry/metadata/timestamp.json, format: json}
```

```sh
morphir package publish --bundle bundle --release release --predecessor draft/predecessor.json --proposal proposal.json --policy fixture/policy.json --registry registry --publisher-state publisher-state --json
```

```yaml morphir:assertion
id: committed-publication
command: publish
entrypoints: [data.publication_committed.passes]
```

```rego
package publication_committed
import rego.v1

passes if {
    input.exitCode == 0
    input.artifacts.timestamp.value.signed.version == 1
}
```

### Consume from a separate project

The consumer receives the public policy and bootstrap root by path. It never
receives a signing seed. Resolution writes a new full lock, and restore checks
the published bytes before exposing the IR.

```yaml morphir:command
id: initialize-consumer
name: Provision the consumer's independent trust state
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package trust init --root fixture/root.json --policy fixture/policy.json --state consumer/trust-state --json
```

```yaml morphir:assertion
id: initialized-consumer
command: initialize-consumer
entrypoints: [data.consumer_initialized.passes]
```

```rego
package consumer_initialized
import rego.v1

passes if { input.exitCode == 0 }
```

```yaml morphir:command
id: resolve
name: Resolve the published release into a verified lock
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package resolve --root example.com/finance/hello@1.0.0 --policy fixture/policy.json --registry registry --state consumer/trust-state --output consumer/morphir.lock --assurance portable --json
```

```yaml morphir:assertion
id: resolved-library
command: resolve
entrypoints: [data.library_resolved.passes]
```

```rego
package library_resolved
import rego.v1

passes if { input.exitCode == 0 }
```

```yaml morphir:command
id: restore
name: Restore the exact locked Library
timeout_seconds: 60
stdout_json: true
captures:
  - {name: restored, path: consumer/libraries/example.com/finance/hello/1.0.0/ir.json, format: json}
```

```sh
morphir package restore --policy fixture/policy.json --lock consumer/morphir.lock --registry registry --state consumer/trust-state --output consumer/libraries --assurance portable --json
```

```yaml morphir:assertion
id: restored-author-ir
command: restore
entrypoints: [data.consumer_restored.passes]
```

```rego
package consumer_restored
import rego.v1

passes if {
    input.exitCode == 0
    input.artifacts.restored.value.formatVersion == 4
    input.artifacts.restored.value.distribution.Library.packageName == "examples/hello"
}
```

```yaml morphir:command
id: generate
name: Generate Gleam source from the restored Library
timeout_seconds: 60
```

```sh
morphir gleam generate --config consumer/morphir.toml --input consumer/libraries/example.com/finance/hello/1.0.0/ir.json --output consumer/generated
```

```yaml morphir:golden
id: generated-main
command: generate
actual: consumer/generated/main.gleam
expected_file: golden/main.gleam
line_endings: lf
```

```yaml morphir:command
id: compile-consumer
name: Compile the generated source in the consumer project
timeout_seconds: 90
captures:
  - {name: ir, path: consumer/compiled/morphir-ir.json, format: json}
```

```sh
morphir gleam compile --config consumer/morphir.toml --input consumer/generated --output consumer/compiled
```

```yaml morphir:assertion
id: consumed-library
command: compile-consumer
entrypoints: [data.consumer_compiled.passes]
```

```rego
package consumer_compiled
import rego.v1

passes if {
    input.exitCode == 0
    input.artifacts.ir.value.formatVersion == 4
    input.artifacts.ir.value.distribution.Library.packageName == "examples/library-consumer"
}
```

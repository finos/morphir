---
version: 1
title: Restore and consume signed local Libraries
description: Provision explicit package trust, restore a complete locked graph from a local registry, and generate and compile a restored Library in a consumer project.
tags: [area:package, area:generate, language:gleam, backend:gleam, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# Restore and consume signed local Libraries

This self-contained example uses a signed local registry and a full package lock.
The trust policy and bootstrap root are explicit inputs. The signing keys are
public test keys; use independently trusted keys for your own registry.

The MVP supports a single caller-controlled local registry and requires fresh
signed metadata for every restore. It refuses uncertain trust state and existing
destinations. Automatic recovery and use of expired historical metadata belong
to the separate production-grade milestone.

## Restore into a consumer project {#restore-and-consume}

### Provision package trust

Initialization creates a new state directory. It never replaces established
state or silently resets rollback protection.

```yaml morphir:command
id: initialize
name: Provision explicit package trust
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package trust init --policy fixture/trust-policy.json --root fixture/registry/metadata/1.root.json --state trust-state --json
```

```yaml morphir:assertion
id: initialize-check
command: initialize
entrypoints: [data.initialized.passes]
```

```rego
package initialized
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.profile == "local-library-mvp"
    input.stdoutJson.profileVersion == "0.1.0-draft.1"
}
```

### Restore the exact locked graph

The restore verifies metadata, publisher authorization and all package bytes
before exposing the complete graph under the consumer's Library directory.
Explicit portable consent requires caller-controlled local roots.

```yaml morphir:command
id: restore
name: Restore both verified Libraries
timeout_seconds: 60
stdout_json: true
captures:
  - {name: provider, path: consumer/libraries/example.com/finance/eligibility/1.2.0/ir.json, format: json}
```

```sh
morphir package restore --policy fixture/trust-policy.json --lock fixture/morphir.lock --registry fixture/registry --state trust-state --output consumer/libraries --assurance portable --json
```

```yaml morphir:assertion
id: restore-check
command: restore
entrypoints: [data.restored.passes]
```

```rego
package restored
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.profile == "local-library-mvp"
    count(input.stdoutJson.packages) == 2
    input.artifacts.provider.value.distribution.Library.packageName == "example/eligibility"
}
```

### Consume the restored provider

Generate Gleam code from the restored eligibility Library using the consumer's
configuration. The built-in backend needs no downloaded executable or network.
This demonstrates provider consumption; it does not claim cross-package linking
or execution of the generated program.

```yaml morphir:command
id: generate
name: Generate source from the restored Library
timeout_seconds: 60
stdout_json: true
```

```sh
morphir gleam --json generate --config consumer/morphir.toml --input consumer/libraries/example.com/finance/eligibility/1.2.0/ir.json --output consumer/generated
```

```yaml morphir:golden
id: generated-source
command: generate
actual: consumer/generated/decision.gleam
expected_file: golden/decision.gleam
line_endings: lf
```

### Compile in the consumer project

The generated provider contains a concrete Decision type and constructor function.
Compile it under the consumer's package identity to prove it is usable source.

```yaml morphir:command
id: compile
name: Compile the consumed Library source
timeout_seconds: 60
stdout_json: true
```

```sh
morphir gleam --json compile --config consumer/morphir.toml --input consumer/generated --output consumer/compiled
```

```yaml morphir:assertion
id: compile-check
command: compile
entrypoints: [data.consumed.passes]
```

```rego
package consumed
import rego.v1

passes if {
    input.exitCode == 0
    input.stdoutJson.success == true
    input.stdoutJson.ir.distribution.Library.packageName == "examples/library-consumer"
    input.stdoutJson.ir.distribution.Library.def.modules.decision.Public.types.decision
    input.stdoutJson.ir.distribution.Library.def.modules.decision.Public.values["default-decision"]
}
```

### Replay without changing the lock

A second invocation freshly authenticates the same graph into a new destination.
Replay neither re-resolves the graph nor rewrites the lock.

```yaml morphir:command
id: replay
name: Freshly authorize exact replay
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package restore --policy fixture/trust-policy.json --lock fixture/morphir.lock --registry fixture/registry --state trust-state --output consumer/replayed --assurance portable --json
```

```yaml morphir:assertion
id: replay-check
command: replay
entrypoints: [data.replayed.passes]
```

```rego
package replayed
import rego.v1

passes if {
    input.exitCode == 0
    count(input.stdoutJson.packages) == 2
}
```

```yaml morphir:golden
id: lock-preserved
command: replay
actual: fixture/morphir.lock
expected_file: fixture/morphir.lock
```

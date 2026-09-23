---
version: 1
title: Update and consume signed local Libraries
description: Update an explicit dependency closure against fresh signed metadata, preserve outside pins and the previous lock, then restore and consume the updated provider.
tags: [area:package, area:generate, language:gleam, backend:gleam, ir:v4, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# Update and consume signed local Libraries

This example uses an independently signed registry and a previous full lock.
The keys are public test keys. Configure independently trusted keys for your own
registry. The current registry metadata is fresh; the old lock's metadata is
historical input, not authority to use packages.

Update verifies current metadata and every selected Library before writing a
new full lock. Exact restore then uses that lock's current pins. The MVP requires
one caller-controlled local registry, explicit trust state and fresh authorization.
It refuses uncertain state and occupied destinations. Automatic recovery and
historical continued-use grants remain outside this profile.

## Update a provider and consume it {#update-and-consume}

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

### Update an explicit dependency target

The previous lock fixes loan-rules at 1.0.0, eligibility at 1.2.0, its child at
1.0.0 and an outside sibling at 1.0.0. The registry has advanced since that lock.
Update authenticates the current view and validates the old immutable package
pins. It selects eligibility 1.3.0 and child 1.1.0 while keeping the sibling at
1.0.0 even though sibling 1.1.0 is available.

Use a new output file. Update preserves the old lock and refuses existing
output files. Repeat --target to request several dependencies; append an exact
stable version, such as --target example.com/finance/eligibility@1.3.0, to pin
one target. The root release remains fixed.

```yaml morphir:command
id: update
name: Update eligibility and its old dependency closure
timeout_seconds: 60
stdout_json: true
```

```sh
morphir package update --lock fixture/morphir.lock --target example.com/finance/eligibility --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --output consumer/morphir.lock --assurance portable --json
```

```yaml morphir:golden
id: updated-lock
command: update
actual: consumer/morphir.lock
expected_file: golden/update.lock.json
```

```yaml morphir:golden
id: previous-lock-preserved
command: update
actual: fixture/morphir.lock
expected_file: fixture/morphir.lock
```

### Restore the exact locked graph

The restore verifies metadata, publisher authorization and all package bytes
before exposing the complete graph under the consumer's Library directory.
Explicit portable consent requires caller-controlled local roots.

```yaml morphir:command
id: restore
name: Restore all four verified Libraries
timeout_seconds: 60
stdout_json: true
captures:
  - {name: provider, path: consumer/libraries/example.com/finance/eligibility/1.3.0/ir.json, format: json}
```

```sh
morphir package restore --policy fixture/trust-policy.json --lock consumer/morphir.lock --registry fixture/registry --state trust-state --output consumer/libraries --assurance portable --json
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
    count(input.stdoutJson.packages) == 4
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
morphir gleam --json generate --config consumer/morphir.toml --input consumer/libraries/example.com/finance/eligibility/1.3.0/ir.json --output consumer/generated
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
morphir package restore --policy fixture/trust-policy.json --lock consumer/morphir.lock --registry fixture/registry --state trust-state --output consumer/replayed --assurance portable --json
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
    count(input.stdoutJson.packages) == 4
}
```

```yaml morphir:golden
id: lock-preserved
command: replay
actual: consumer/morphir.lock
expected_file: golden/update.lock.json
```

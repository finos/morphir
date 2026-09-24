---
version: 1
title: CLI migration
description: Convert a Classic Library into canonical V4 YAML using the public CLI.
tags: [area:cli, feature:migrate, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# CLI migration

The input is a small Classic V3 Library with one public module. The fixed
expected output checks its V4 wrapper, package path, module name, and YAML text.

## Convert Classic JSON to V4 YAML {#classic-to-v4}

```yaml morphir:command
id: migrate
name: Migrate a Classic Library
timeout_seconds: 30
captures:
  - {name: ir, path: output.yaml, format: text}
```

```sh
morphir migrate classic-library.json --output output.yaml --target-version v4
```

```yaml morphir:assertion
id: result
command: migrate
entrypoints: [data.migration_test.writes_output]
```

```rego
package migration_test
import rego.v1

writes_output if {
    input.exitCode == 0
    contains(input.stderr, "Migration complete")
    input.artifacts.ir.kind == "text"
}
```

```yaml morphir:golden
id: canonical-yaml
command: migrate
actual: output.yaml
expected_file: golden/library.v4.yaml
```

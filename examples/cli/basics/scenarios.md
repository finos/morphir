---
version: 1
title: CLI basics
description: Verify the public CLI reports its version and documents its commands.
tags: [area:cli, kind:positive, suite:offline, workspace:directory]
provider: rego
---

# CLI basics

Each second-level heading is an independent scenario. These checks use the same
Morphir executable that runs `itest` and need no installed extensions.

## Report version {#version}

The version command must succeed and identify the executable.

```yaml morphir:command
id: run
name: Report CLI version
timeout_seconds: 10
```

```sh
morphir --version
```

```yaml morphir:assertion
id: check
command: run
entrypoints: [data.version_test.reports_version]
```

```rego
package version_test
import rego.v1

reports_version if {
    input.exitCode == 0
    some line in split(input.stdout, "\n")
    startswith(line, "morphir ")
}
```

## Command help

### Public commands

The help text must include the compile and integration-test commands.

```yaml morphir:command
id: run
name: Show CLI help
timeout_seconds: 10
```

```sh
morphir --help
```

```yaml morphir:assertion
id: check
command: run
entrypoints: [data.help_test.lists_commands]
```

```rego
package help_test
import rego.v1

lists_commands if {
    input.exitCode == 0
    contains(input.stdout, "compile")
    contains(input.stdout, "itest")
}
```

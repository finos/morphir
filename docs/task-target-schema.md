---
id: task-target-schema
title: Morphir Task and Target Schema (Draft)
---

# Morphir Task and Target Schema (Draft)

This document defines a draft schema for tasks and targets in `morphir.toml`.
Targets are conventional task names/aliases (e.g., `build`, `test`, `clean`).

## Goals

- Configure tasks and targets in `morphir.toml`.
- Support dependencies, inputs/outputs, parameters, and env vars.
- Support intrinsic actions and external commands.
- Ensure outputs are JSON-serializable.
- Run external commands sandboxed by default (explicit RW mounts).

## Top-Level Structure (Draft)

```toml
[tasks]

[tasks.build]
depends_on = ["compile", "analyze"]
pre = ["setup"]
post = ["summarize"]

[tasks.compile]
kind = "intrinsic"
action = "morphir.pipeline.compile"
inputs = ["workspace:/src/**/*.elm"]
outputs = ["workspace:/build/**"]
params = { profile = "dev" }
env = { GOFLAGS = "-mod=mod" }
mounts = { workspace = "rw", config = "ro", env = "ro" }

[tasks.analyze]
kind = "intrinsic"
action = "morphir.analyzer.run"
inputs = ["workspace:/build/**"]
outputs = ["workspace:/reports/analyzer.json"]

[tasks.codegen]
kind = "command"
cmd = ["morphir", "gen", "--target", "Scala"]
inputs = ["workspace:/morphir-ir.json"]
outputs = ["workspace:/dist/**"]
mounts = { workspace = "rw", config = "ro", env = "ro" }

[tasks.setup]
kind = "command"
cmd = ["./scripts/setup.sh"]
mounts = { workspace = "rw", env = "ro" }

[tasks.summarize]
kind = "intrinsic"
action = "morphir.report.summary"
inputs = ["workspace:/reports/**"]
outputs = ["workspace:/reports/summary.json"]
```

## Task Fields

- `kind`: `intrinsic` or `command`.
- `action`: intrinsic action identifier (for `kind = "intrinsic"`).
- `cmd`: external command (for `kind = "command"`), array form.
- `depends_on`: list of task names to run before this task.
- `pre`: list of task names to run immediately before this task.
- `post`: list of task names to run immediately after this task.
- `inputs`: list of VPath globs used for caching and incremental builds.
- `outputs`: list of VPath globs produced by the task.
- `params`: task parameters (key/value).
- `env`: environment variables for the task.
- `mounts`: mount permissions (`ro` or `rw`).

## Task Output

Tasks should emit JSON-serializable output data (stdout for structured results).
Diagnostics and progress logs should go to stderr.

## Sandbox Defaults

External commands run sandboxed by default:

- Only mounts explicitly marked `rw` are writable.
- Read-only mounts are visible but not writable.
- Opt-in to broader access should be explicit.

## Open Questions

- Should we allow task-level timeouts and retries?
- Do we need composite task definitions beyond pre/post hooks?

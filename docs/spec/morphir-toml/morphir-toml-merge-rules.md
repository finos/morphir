---
id: morphir-toml-merge-rules
title: "Morphir TOML Configuration Merge Rules"
sidebar_position: 3
description: "How Morphir merges morphir.toml configuration sources into an effective configuration"
---

## Purpose

Morphir configuration is **layered**: multiple configuration sources are loaded and merged to produce one **effective configuration**.

This document specifies:

- **Which sources are considered**
- **Their precedence order**
- **The deterministic merge algorithm** used to combine them

## Configuration sources and precedence

Sources are loaded from **lowest precedence** to **highest precedence**:

| Priority | Source | Typical path |
|----------|--------|--------------|
| 1 (lowest) | Built-in defaults | (compiled in) |
| 2 | System config | `/etc/morphir/morphir.toml` |
| 3 | Global user config | `~/.config/morphir/morphir.toml` |
| 4 | Project config | `morphir.toml` |
| 5 | User override | `.morphir/morphir.user.toml` |
| 6 (highest) | Environment variables | `MORPHIR_*` |

If the same setting is present in multiple sources, **the value from the highest-precedence source wins**, subject to the merge algorithm described below.

> Note: A “hidden project config” variant (`.morphir/morphir.toml`) may also be used by some commands/workflows. The merge semantics are identical.

## Merge algorithm (normative)

Let each configuration source be represented as a nested object \(map\) `map[string]any` produced from TOML or environment variables.

The effective configuration is computed by applying `DeepMerge` from low precedence to high precedence:

```
effective = DeepMerge(
  DeepMerge(
    DeepMerge(defaults, system),
    global
  ),
  project
)
... then merged with user overrides and env vars (if present)
```

More generally: **later maps take precedence over earlier maps**.

### DeepMerge rules

Given two maps: `base` and `overlay`, `DeepMerge(base, overlay)` produces a new map `result` and follows these rules:

- **Rule 1 — Overlay wins**: for a key present in both maps, the overlay value takes precedence.
- **Rule 2 — Maps merge recursively**: if both values for the same key are maps, those maps are recursively deep-merged.
- **Rule 3 — Arrays/slices replace**: if values are arrays/slices, the overlay replaces the base entirely (no concatenation).
- **Rule 4 — `nil` overlay is ignored**: if an overlay value is `nil`, it does **not** override the base value.
- **Rule 5 — No mutation**: the merge result is independent; inputs are not modified.

These rules are implemented by `pkg/config/internal/configloader.DeepMerge` and `MergeAll`.

## Environment variable mapping (informative)

Environment variables are treated as the highest precedence source. Variables starting with the configured prefix (default `MORPHIR_`) are converted into config keys.

Key mapping:

- **Double underscore** (`__`) indicates nested object boundaries:
  - `MORPHIR_CODEGEN__GO__PACKAGE=foo` → `codegen.go.package = "foo"`
- Single underscores are not split into nested keys by the loader; they remain part of the key name at that level:
  - `MORPHIR_IR_FORMAT_VERSION=3` → `ir_format_version = 3` (as a single key in the env-derived map)

> The env mapping behavior is intentionally mechanical; it does not attempt to “guess” dotted paths. The final effective configuration still follows the same DeepMerge rules.

## Related docs

- `docs/configuration.md` (user-facing configuration guide)
- `docs/spec/morphir-toml-specification.md` (format/structure specification)


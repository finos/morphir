---
id: morphir-toml-merge-rules
title: "Morphir configuration merge rules"
sidebar_position: 3
description: "How Morphir merges configuration sources into an effective configuration"
---

## Purpose

Morphir configuration is **layered**: multiple configuration sources are loaded and merged to produce one **effective configuration**. The algorithm operates on parsed configuration values and is independent of whether a source uses TOML or YAML.

This document specifies:

- **Which sources are considered**
- **Their precedence order**
- **The deterministic merge algorithm** used to combine them

## Configuration sources and precedence

Sources are loaded from **lowest precedence** to **highest precedence**:

| Priority | Source | Typical path |
|----------|--------|--------------|
| 0 (lowest) | Built-in defaults | (compiled in) |
| 100 | System config | `/etc/morphir/morphir.toml`, or `%PROGRAMDATA%\morphir\morphir.toml` on Windows |
| 200 | Global user config | Platform config directory or user-home `.morphir` directory |
| 300 | Project or workspace primary | One of the three standard primary layouts |
| 350 | Selected workspace-member primary | One of the three standard primary layouts in the member |
| 400 | User override | Adjacent to the selected project, workspace, or member primary |
| 600 (highest) | Environment variables | `MORPHIR_*` |

If the same setting is present in multiple sources, **the value from the highest-precedence source wins**, subject to the merge algorithm described below.

Each file source accepts a `morphir.yaml` serialization at the corresponding location (`morphir.user.yaml` for the user override). A loader MUST accept at most one serialization per location and MUST report an ambiguity error that names both files when a TOML and a YAML file coexist. See the [YAML specification](../morphir-yaml/morphir-yaml-specification/) for discovery details.

On Windows, `%PROGRAMDATA%` resolves through the `PROGRAMDATA` environment variable and falls back to `C:\ProgramData` when it is unset.

### Project layouts and adjacent user overrides

Project, workspace, and workspace-member primaries use one of these layout pairs:

| Primary configuration | Adjacent user override candidates |
| --- | --- |
| `morphir.toml` or `morphir.yaml` | `morphir.user.toml` or `morphir.user.yaml` |
| `.morphir/morphir.toml` or `.morphir/morphir.yaml` | `.morphir/morphir.user.toml` or `.morphir/morphir.user.yaml` |
| `.config/morphir/config.toml` or `.config/morphir/config.yaml` | `.config/morphir/config.user.toml` or `.config/morphir/config.user.yaml` |

The primary paths are six alternatives at one discovery location. A loader MUST reject all coexisting primary candidates as ambiguous and name every path. For a selected standard primary, its two adjacent override serializations are alternatives. A loader MUST reject both override files as ambiguous. An explicitly selected primary outside these three layouts has no implicitly discovered adjacent override.

When a workspace selects a member, the loader merges the workspace primary, the member primary, the workspace's adjacent override, then the member's adjacent override. The member override wins over the workspace override. A primary or override from a member is not discovered until that member is selected.

### Global user path resolution

A loader MUST resolve the platform config directory as follows:

| Platform | Config directory |
| --- | --- |
| Linux and other XDG systems | `$XDG_CONFIG_HOME` when it is set to a non-empty absolute path; otherwise `$HOME/.config` |
| macOS | `$XDG_CONFIG_HOME` when it is set to a non-empty absolute path; otherwise `$HOME/Library/Application Support` |
| Windows | `FOLDERID_RoamingAppData`, typically `%APPDATA%` |

This follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/) and the Windows [Known Folder API](https://learn.microsoft.com/windows/win32/shell/known-folders). On an XDG system, a relative `XDG_CONFIG_HOME` value is invalid and MUST be ignored. The loader then uses the platform default. `XDG_CONFIG_DIRS` does not define the global user location.

Examples:

| Environment | Resolved YAML candidate |
| --- | --- |
| Linux with `XDG_CONFIG_HOME=/srv/alice/config` | `/srv/alice/config/morphir/morphir.yaml` |
| Linux with `XDG_CONFIG_HOME` unset, empty, or relative | `/home/alice/.config/morphir/morphir.yaml` |
| macOS without `XDG_CONFIG_HOME` | `/Users/Alice/Library/Application Support/morphir/morphir.yaml` |
| Windows with Roaming AppData at `D:\Profiles\Alice\Roaming` | `D:\Profiles\Alice\Roaming\morphir\morphir.yaml` |

The standard global user candidates are:

- `<config-directory>/morphir/morphir.toml`
- `<config-directory>/morphir/morphir.yaml`

The user-home alternatives are:

- `$HOME/.morphir/morphir.toml` and `$HOME/.morphir/morphir.yaml` on Unix-like systems
- `%USERPROFILE%\.morphir\morphir.toml` and `%USERPROFILE%\.morphir\morphir.yaml` on Windows, where the implementation resolves the profile through `FOLDERID_Profile`

These paths are alternate locations at the same precedence. A loader accepts at most one global user configuration across all candidates. If it finds more than one, it reports an ambiguity error that names every candidate. It MUST NOT merge the files or choose one by path or extension.

## Merge algorithm (normative)

Let each configuration source be represented as a nested object \(map\) `map[string]any` produced from TOML, YAML, or environment variables.

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
- **Rule 6 — Secret values are leaves**: if the base value, the overlay value, or both are a secret reference (`{ env = ... }`, `{ file = ... }`, `{ command = [...] }`, or `{ keyring = { service = ..., account = ... } }`) or a secret string, the overlay value replaces the base value entirely. The two are never deep-merged as maps, even when both look like ordinary tables. This rule takes precedence over Rule 2 because a merged table can stop being a valid secret reference.

These rules are implemented by `deep_merge` and `merge_all` in the `morphir_common::config::merge` module of morphir-rust. The layered loader in `morphir_devkit::config` (`load_effective_config`) applies them across the sources above and records which sources were consulted; `morphir config path` and `morphir config show` expose that result.

## Provenance

The loader records, for every winning leaf value and every array, the source kind and, for file sources, the declaring path. Provenance follows the winning value through `DeepMerge`: an overlay value that replaces or adds a value brings its own provenance. A table does not carry provenance separate from its children.

The internal provenance data lets the secret resolver anchor a relative file reference or command working directory to the file that supplied the winning leaf. `morphir config show --provenance` is not implemented. Tooling may later expose provenance for explanations or validation diagnostics; that flag's output shape is not finalized.

## Environment variable mapping (informative)

Environment variables are treated as the highest precedence source. Variables starting with the configured prefix (default `MORPHIR_`) are converted into config keys.

Key mapping:

- **Double underscore** (`__`) indicates nested object boundaries:
  - `MORPHIR_CODEGEN__GO__PACKAGE=foo` → `codegen.go.package = "foo"`
- Single underscores are not split into nested keys by the loader; they remain part of the key name at that level:
  - `MORPHIR_IR_FORMAT_VERSION=3` → `ir_format_version = 3` (as a single key in the env-derived map)
- Key segments are lower-cased. Underscores immediately after the prefix are ignored, so `MORPHIR__IR__STRICT_MODE` and `MORPHIR_IR__STRICT_MODE` map to the same key.

Value mapping:

- `true` and `false` (any case) become booleans.
- Integers become numbers.
- A value that starts with `[` or `{` and parses as JSON becomes an array or object.
- Anything else stays a string.

When a scalar and a nested key conflict (`MORPHIR_IR=x` together with `MORPHIR_IR__STRICT_MODE=true`), the shorter path wins and the nested variable is dropped, regardless of environment iteration order.

> The env mapping behavior is intentionally mechanical; it does not attempt to “guess” dotted paths. The final effective configuration still follows the same DeepMerge rules.

## Related docs

- `docs/configuration.md` (user-facing configuration guide)
- `docs/spec/morphir-toml/morphir-toml-specification.md` (format/structure specification)
- `docs/spec/morphir-yaml/morphir-yaml-specification.md` (YAML serialization)

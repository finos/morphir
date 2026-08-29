---
title: "JSON Serialization Profile"
description: "Normative JSON storage profile for Morphir IR version 4"
---

# V4 JSON Serialization Profile

## Status and scope

This page defines the JSON serialization of the [v4 semantic IR model](semantic-model.md). JSON remains a fully supported native IR storage format.

Version 4 inherits the shared [`formatVersion` contract](../../format-version.md). Integer `4` aliases exactly `4.0.0`; the exact baseline string `"4.0.0"` is valid input; and later v4 revisions use strict release strings such as `"4.0.1"`. Canonical writers emit integer `4` for the baseline and an exact string for a nonzero minor or patch revision.

## JSON Schema bootstrap

The checked-in `morphir-ir-v4` JSON Schema is the machine-readable bootstrap definition of this JSON profile. JSON Schema was selected because it provided a practical way to define and validate the initial v4 representation. It does not restrict Morphir IR storage to JSON and is not, by itself, the serialization-neutral semantic model.

A later specification may express this model in Morphir IR and generate serialization profiles from that definition. Such a change does not alter the semantic equality rule.

## Encoding

A JSON artifact MUST:

- be UTF-8;
- contain exactly one JSON value;
- contain an object at the root;
- conform to the v4 JSON Schema and the semantic invariants;
- preserve integers and finite decimal values without coercion;
- reject duplicate object member names.

Writers SHOULD emit the compact canonical v4 vocabulary unless expanded output is explicitly selected. Readers MUST accept every spelling the v4 JSON Schema marks as valid.

JSON object member order is not semantic. Readers MUST accept `formatVersion` before or after `distribution`. Canonical writers MUST emit `formatVersion` first and `distribution` second. A linter SHOULD report `format_version_not_first` for the reverse order, but a reader MUST NOT reject an otherwise valid artifact for that reason.

## File names

A single-file JSON artifact conventionally uses `.json`. In a JSON document tree, the physical names are `manifest.json`, `module.json`, `*.type.json`, and `*.value.json`.

JSON syntax is also valid YAML syntax. When content detection is necessary, a reader tests JSON first so profile selection is deterministic.

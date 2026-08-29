---
title: "IR Format Version Contract"
linkTitle: "Format Version"
weight: 2
description: "Normative spelling, compatibility, diagnostics, and canonical ordering rules for Morphir IR formatVersion"
---

# Morphir IR format version contract

## Status and scope

This page defines the normative `formatVersion` contract shared by Morphir IR serialization profiles. The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY state requirements for conforming implementations.

Versions 1 and 2 are historical integer-only formats. Version 1 MUST be written as the integer `1`, and version 2 MUST be written as the integer `2`. The strings `"1.0.0"` and `"2.0.0"` are not valid aliases.

Version 3 is the first format family governed by the permanent contract below. Every format family with major version `N >= 3`, including future families, inherits the same contract. A future family MUST NOT revert to integer-only version spelling.

## Accepted scalar forms

For every major family `N >= 3`, `formatVersion` has exactly two accepted scalar forms:

- The integer `N` denotes exactly release `N.0.0`.
- The string `"N.minor.patch"` denotes that exact release.

`N`, `minor`, and `patch` are unsigned base-10 integers in the range `0` through `4294967295`, inclusive. A component MUST use only ASCII digits and MUST NOT contain a leading zero unless the component is exactly `0`.

The integer `0` is not a format family and is invalid. Integers `1` and `2` are recognized only as the historical spellings defined above. Release strings are valid only for a major family `N >= 3`, so `"0.0.0"`, `"1.0.0"`, and `"2.0.0"` are invalid.

The release string contains exactly three components separated by two ASCII full stops. Signs, leading or trailing whitespace, embedded whitespace, fractions, missing or extra components, prerelease suffixes, and build metadata are invalid. A reader MUST reject every other scalar or collection type, including booleans, null, arrays, and objects.

This grammar is deliberately narrower than Semantic Versioning. In particular, `3.1.0-alpha`, `4.0.0+build`, `+3.0.0`, and ` 4.0.0` are not valid `formatVersion` values.

## Normalization and canonical spelling

A reader MUST normalize either accepted spelling to an exact three-component release before checking compatibility. Thus integer `3` and string `"3.0.0"` both normalize to `3.0.0`; integer `4` and string `"4.0.0"` both normalize to `4.0.0`.

A canonical writer MUST emit the integer `N` for the baseline release `N.0.0`. It MUST emit the exact release string for any release whose minor or patch component is nonzero. For example, the canonical spellings are `3`, `"3.1.0"`, `4`, and `"4.0.2"`. A baseline release string is valid input but is not canonical output.

## Recognition and compatibility

Recognition and support are separate decisions. Recognition checks the scalar type, release grammar, component range, and major-family spelling. Syntax recognition never implies support for the normalized release.

Each implementation MUST declare an explicit support table of exact normalized releases. The permanent support-table contract starts with v3 and applies to every later major family. The reference table used by this specification and its conformance corpus is:

- `3.0.0`
- `4.0.0`

An implementation MAY declare a different table when its actual decoder or migration capabilities differ. It MUST NOT claim support for an exact release that it cannot process according to that release's specification.

This page defines the conformance target. A reader or writer does not conform merely because its repository publishes this specification. Implementations adopt the contract when their normalization, compatibility checks, diagnostics, ordering behavior, and replay strategy satisfy these requirements.

After successful recognition and normalization, an implementation MUST distinguish these compatibility results:

- `supported` means the exact normalized release is in its support list.
- `unsupported_format_version_major` means the normalized major has no supported release.
- `unsupported_format_version_revision` means the implementation supports the major family but not that exact minor and patch release.

For the current reference table, `"3.1.0"` is a recognized v3 release spelling but produces `unsupported_format_version_revision`. `"5.0.0"` follows the permanent grammar but produces `unsupported_format_version_major` because the table contains no v5 release.

`unsupported_format_version_major` applies only after the reader recognizes either the historical integer `1` or `2`, or a family `N >= 3`, and normalizes that spelling as appropriate. Integer `0` and the forbidden release strings for majors 0, 1, and 2 fail with `invalid_format_version_syntax` before compatibility checking.

A reader MUST complete format-version recognition and compatibility checking before it invokes distribution decoders, semantic validators, migrations, or other version-specific callbacks. Unsupported input must therefore fail with a format-version compatibility diagnostic rather than an incidental error from the selected semantic model.

## Schema and semantic validation boundary

The v3-and-later schemas enforce the permitted scalar types, lexical grammar, and the schema's own major family. Schema validation is only a bootstrap check. It does not establish component bounds or implementation support.

Semantic normalization MUST enforce the unsigned 32-bit range for every component. This is why a lexically valid string such as `"3.4294967296.0"` can match the v3 schema but must fail normalization with `format_version_out_of_range`. Exact-release compatibility is also a semantic check against the implementation's support list.

## Root member order

Root member order is not semantic in JSON objects or YAML mappings. Readers MUST accept `formatVersion` before or after `distribution`, subject to the duplicate-member rules of the selected serialization profile.

Canonical JSON and YAML writers MUST emit `formatVersion` first and `distribution` second. A linter SHOULD report the stable warning `format_version_not_first` when a valid root mapping places another member first. This condition MUST NOT make the document invalid or prevent decoding.

When a reader measures replay cost, the warning SHOULD include the byte offset of `formatVersion`, the total bytes scanned before semantic decoding, and whether replay used memory, seek or reopen, temporary storage, or an equivalent replay kind. An implementation that does not measure replay cost MAY omit these fields. Either form remains a lint result, never a rejection.

## Stable diagnostics

Readers and linters MUST use stable diagnostic categories so callers do not need to parse prose:

| Code | Condition |
| --- | --- |
| `missing_format_version` | The root has no `formatVersion` member. |
| `duplicate_format_version` | The root contains more than one `formatVersion` member. |
| `invalid_format_version_type` | The value is not a string or unsigned integer, including negative and fractional numbers, or has a collection type. |
| `invalid_format_version_syntax` | A string does not match the exact release grammar or names a major below 3, or the value is integer `0`. |
| `format_version_out_of_range` | An integer or release component exceeds the unsigned 32-bit range. |
| `unsupported_format_version_major` | No release from the recognized major family is supported. |
| `unsupported_format_version_revision` | The major family is supported, but the exact normalized release is not. |
| `format_version_not_first` | A valid root mapping uses noncanonical member order. This is a warning only. |

Diagnostics SHOULD also identify their processing stage, semantic cursor, and physical source location when known. The code remains stable even when explanatory text or recovery guidance changes.

## Conformance data

The [format-version conformance corpus](fixtures/format-version-conformance.json) records scalar normalization, compatibility, schema-family expectations, and canonical and noncanonical JSON and YAML header order. The [v3 schema](schemas/v3/index.md) is the first family-specific profile governed by this contract. The [v4 semantic model](schemas/v4/semantic-model.md), [JSON profile](schemas/v4/json-profile.md), and [YAML profile](schemas/v4/yaml-profile.md) inherit it unchanged.

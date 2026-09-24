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

This page defines the conformance target. A reader or writer does not conform merely because its repository publishes this specification. Implementations adopt the contract when their normalization, compatibility checks, diagnostics, ordering behavior, and replay strategy satisfy these requirements.

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

A canonical writer MUST emit the integer `N` for the baseline release `N.0.0`. It MUST emit the exact release string for any release whose minor or patch component is nonzero. For example, the canonical spellings are `3`, `"3.2.0"`, `4`, and `"4.0.2"`. A baseline release string is valid input but is not canonical output.

## Revisions

For every major family `N >= 3`, the three components of a release make three promises:

| Revision | May change |
| --- | --- |
| Patch (`N.m.p` to `N.m.(p+1)`) | Nothing a reader can observe. Prose clarifications, corrected examples, and kit cases that pin behaviour the contract already required. No new node kinds, members or accepted spellings; nothing previously accepted becomes rejected; nothing a writer emits changes. |
| Minor (`N.m.*` to `N.(m+1).0`) | What a reader accepts or emits. New vocabulary, new accepted spellings, and the closing of an acceptance window are all minor revisions. |
| Major | Anything, including the reading of older documents. |

A reader that understands `N.m.0` can therefore process every `N.m.p`, including patches specified after the reader was built. A revision exists when the Morphir Compatibility Kit carries cases for it; nothing else mints one.

## Recognition and compatibility

Recognition and support are separate decisions. Recognition checks the scalar type, release grammar, component range, and major-family spelling. Syntax recognition never implies support for the normalized release.

Each implementation MUST declare an explicit support table. A support table is a union of intervals over the release grammar above, written in the interval notation shared by Maven, NuGet and OSGi:

```
table    = interval *( "," interval )
interval = "[" release "]" / open [release] "," [release] close
open     = "[" / "("
close    = "]" / ")"
```

`[` and `]` are inclusive; `(` and `)` are exclusive. `[a]` means exactly `a`. A missing lower bound means no lower bound; a missing upper bound means no upper bound; at least one bound is required. Whitespace after a comma and around a bound is permitted on input and dropped on normalization. A bound MUST be a release string; the integer alias is not permitted inside a table. An interval whose lower bound is above its upper bound, or which contains no release, is invalid: the smallest release its lower bound admits (the bound itself when inclusive, otherwise the next release after it) must satisfy the upper bound. The release grammar starts at major 3, so an absent lower bound admits releases from `3.0.0`; a table such as `(,3.0.0)` contains no release and is invalid. The next release after a bound carries into the minor, and then into the major, when a component is at its maximum. This is deliberately not the `next()` of canonicalization below, which never carries: a bound that cannot be advanced keeps its bracket rather than moving to another minor.

Every interval requires at least one bound, and a table MUST have one canonical spelling that parses back to the same table. A table whose intervals merge into an interval with no bound on either side has no such spelling, so that table is invalid.

A release is supported when it lies inside any interval of the table.

A table has one canonical spelling, which writers, adapters and reports MUST emit:

1. Every interval is rewritten as a half-open `[a,b)` interval wherever a finite bound can be advanced: an inclusive upper `b]` becomes `next(b))`, an exclusive lower `(a` becomes `[next(a)`, and `[a]` becomes `[a,next(a))`, where `next(x.y.z)` is `x.y.(z+1)`. A patch component at `4294967295` cannot be advanced and keeps its original bracket; `next()` never carries into the minor, unlike the successor the emptiness rule above uses. The exact form `[a]` is never a canonical spelling, so an `[a]` whose patch is at the maximum becomes `[a,a]` rather than staying `[a]`. An absent bound takes a round bracket.
2. Intervals are sorted by lower bound, an absent lower bound first.
3. Overlapping or adjacent intervals are merged. Two intervals are adjacent when the second's lower bound is the next release after the first's upper bound, using the carrying successor defined for the emptiness rule, so `[4.0.0,4.0.4294967295],[4.1.0,4.2.0)` merges to `[4.0.0,4.2.0)`.
4. No whitespace.

The reference table used by this specification and its conformance corpus is:

```
[3.0.0,3.2.0),[4.0.0,4.1.0)
```

Its ceilings sit on minor boundaries because of the patch promise above: a `4.0.0` reader accepts every `4.0.x`, and the V3 interval includes the `3.1.x` Specs distribution. An implementation MAY declare any table the grammar allows when its decoder or migration capabilities differ. A conforming reader SHOULD declare ceilings on minor boundaries: under the revision promise a later patch changes nothing a reader can observe, so a ceiling inside a minor records what the implementation has verified rather than a difference in the format. The compatibility result names the minor because that is the component that differs for the reference table and for every table whose ceilings sit on minor boundaries. It MUST NOT claim support for a release it cannot process according to that release's specification.

A binding driven through the Morphir Compatibility Kit publishes its table in the `formatVersions` member of its adapter's capabilities reply; the driver validates that it is canonical and carries it into the run report. A binding not driven through the kit publishes the same canonical string in its README.

A table may be shown to people in three other styles, none of which is accepted as input:

| Style | `[3.0.0,3.2.0),[4.0.0,4.1.0)` reads as |
| --- | --- |
| Cargo comparator sets | `>=3.0.0, <3.2.0` and `>=4.0.0, <4.1.0` |
| Elm constraints | `3.0.0 <= v < 3.2.0` and `4.0.0 <= v < 4.1.0` |
| Prose | `3.0.0 up to but not including 3.2.0, or 4.0.0 up to but not including 4.1.0` |

After successful recognition and normalization, an implementation MUST distinguish these compatibility results:

- `supported` means the normalized release lies inside the table.
- `unsupported_format_version_major` means no interval of the table contains any release of the normalized release's major family.
- `unsupported_format_version_minor` means some interval contains a release of that major family, but none contains the normalized release. For the reference table, and for any table whose ceilings sit on minor boundaries, the mismatching component is the minor.

For the reference table, `"4.0.1"` is supported, `"4.1.0"` produces `unsupported_format_version_minor`, and `"5.0.0"` produces `unsupported_format_version_major`.

`unsupported_format_version_major` applies only after the reader recognizes either the historical integer `1` or `2`, or a family `N >= 3`, and normalizes that spelling as appropriate. Integer `0` and the forbidden release strings for majors 0, 1, and 2 fail with `invalid_format_version_syntax` before compatibility checking.

A reader MUST complete format-version recognition and compatibility checking before it invokes distribution decoders, semantic validators, migrations, or other version-specific callbacks. Unsupported input must therefore fail with a format-version compatibility diagnostic rather than an incidental error from the selected semantic model.

## Schema and semantic validation boundary

The v3-and-later schemas enforce the permitted scalar types, lexical grammar, and the schema's own major family. Schema validation is only a bootstrap check. It does not establish component bounds or implementation support.

Semantic normalization MUST enforce the unsigned 32-bit range for every component. This is why a lexically valid string such as `"3.4294967296.0"` can match the v3 schema but must fail normalization with `format_version_out_of_range`. Support-table membership is also a semantic check, made after normalization.

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
| `unsupported_format_version_minor` | The major family is supported, but the normalized release lies outside the table. |
| `format_version_not_first` | A valid root mapping uses noncanonical member order. This is a warning only. |

Diagnostics SHOULD also identify their processing stage, semantic cursor, and physical source location when known. The code remains stable even when explanatory text or recovery guidance changes.

## Conformance data

The [format-version conformance corpus](fixtures/format-version-conformance.json) records scalar normalization, compatibility against the reference `supportTable`, support-table parsing, canonical spelling, membership and rendering (`supportTableCases`), schema-family expectations, and canonical and noncanonical JSON and YAML header order. The [v3 schema](schemas/v3/index.md) is the first family-specific profile governed by this contract. The [v4 semantic model](schemas/v4/semantic-model.md), [JSON profile](schemas/v4/json-profile.md), and [YAML profile](schemas/v4/yaml-profile.md) inherit it unchanged.

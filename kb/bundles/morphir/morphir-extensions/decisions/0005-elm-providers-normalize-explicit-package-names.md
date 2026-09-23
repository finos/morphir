---
type: Decision Record
title: Elm providers normalize explicit package names
state: Accepted
decided: 2026-09-23
tags: [extensions, elm, workspace, discovery, package-name]
status: stable
description: Every Elm workspace provider reads an explicit package name with both `.` and `/` as segment separators and reports one normal form, lowercase words joined by `-` and segments joined by `/`, which keeps the Morphir IR package path unchanged.
sources:
  - id: single-file-spec
    resource: https://github.com/finos/morphir/discussions/917
    title: "finos/morphir#917: a single file is a synthesized project (spec)"
  - id: single-file-thread
    resource: https://github.com/finos/morphir/discussions/915
    title: "finos/morphir#915: a single file is a synthesized project (working thread)"
---

# Elm providers normalize explicit package names

When a selection of files carries an explicit package name, every Elm workspace provider reads the
name with both `.` and `/` as segment separators, splits each segment into Morphir-name words, and
reports one normal form as the project name. The providers are the built-in Rust binding, the
TypeScript extension in finos/morphir-elm and `morphir-scala-elm`. The name comes from
`--package-name`, or from the manifest a selection borrows with `--config` or `--project`
(source `single-file-spec`).

## Summary

Before this decision the three Elm providers disagreed. The Rust binding accepted any name with a
package path segment and reported it as written. The TypeScript and Scala extensions accepted only
names already in a slash-and-dash canonical form, and that form treated a `.` as a word boundary
inside one segment. So `--package-name My.Package`, or a selection borrowing a manifest named
`Documentation.Decoration`, worked with one Elm provider and failed with the other two.

The rule:

1. Split the name on `/` and `.`, trim each piece, and drop empty pieces.
2. Split each piece into words as morphir-elm `Name.fromString` does: every match of
   `[a-zA-Z][a-z]*|[0-9]+`, lowercased.
3. Refuse with `workspace.project-name.invalid` when no piece is left, or when a piece has no words.
4. Report the normal form: each piece's words joined by `-`, pieces joined by `/`.

| Explicit name | Normal form |
| --- | --- |
| `acme/widgets` | `acme/widgets` |
| `My.Package` | `my/package` |
| `Morphir.Reference.Model` | `morphir/reference/model` |
| `acme/my_widgets` | `acme/my-widgets` |
| `MyPackage` | `my-package` |
| `/./` | refused |

| Option | Outcome | Why |
| --- | --- | --- |
| Accept both separators and report a normal form | Chosen | Classic Elm names keep working, all providers agree, and the IR does not change |
| Accept both separators and report the name as written | Rejected | Providers agree on acceptance, but one package has several spellings in records and output |
| Accept only the slash-and-dash canonical form | Rejected | Dotted names, common in classic morphir-elm projects, stop working for selections |

## Why

A `.` in a Morphir package name separates path segments. Classic morphir-elm treats
`Morphir.Reference.Model` as a three-segment package path, and the Rust binding's module-prefix
stripping compares segments in their Morphir-name spelling. The normal form keeps that reading, so it
names the same package. With the built-in Rust provider, `My.Package`, `my/package` and `My/Package`
compile one module to byte-identical IR with package path `[[my],[package]]`, and `My.Package.Foo`
becomes module `Foo`. `my-package` is a different package with one segment, `[[my,package]]`, and
nothing is stripped. A canonical form that turns `My.Package` into `my-package` therefore names a
different package. The TypeScript and Scala rules made that mistake.

Reporting one normal form, instead of the spelling the user typed, gives one package one name in the
task record, the snapshot and every later step. The normal form is idempotent, and every synthesized
name (`local/<module lowercased, dots as dashes>`) is already in normal form.

## Consequences

- The Rust `SourceIdentity` hook returns the normalized name instead of only checking it, and the
  snapshot carries the normal form.
- The TypeScript and Scala extensions change their explicit-name rule, and release new versions.
  The finos/morphir pins move to them.
- Each provider tests the same table of cases. When the unified guest SDK (beads `morphir-opua`)
  exists, the rule and its cases move there, and the providers stop carrying their own copies.
- Only the explicit name in a selection changes. A project compile still takes its name from the
  manifest unchanged.

## Revisit when

Revisit when the unified guest SDK takes over the rule, or if a non-Elm provider needs a different
reading of `.` in package names.

---
type: Decision Record
title: "IR 3.1.0 adds a Specs distribution and v3 document trees"
description: "IR format 3.1.0 is a minor revision of the classic IR that adds a v3 Specs distribution and JSON and YAML document trees for v3; writers emit the lowest version that fits, so a single-file Library stays 3, and the reference support table becomes [3.0.0,3.2.0),[4.0.0,4.1.0)."
state: Accepted
decided: 2026-09-24
tags: [ir, ir-v3, versioning, format-version, document-tree]
status: draft
---

# IR 3.1.0 adds a Specs distribution and v3 document trees

IR format `3.1.0` was minted as a minor revision of the classic IR. It added two things: a v3 `Specs` distribution,
and JSON and YAML document trees that hold v3. A writer emits the lowest version that expresses its content. A
single-file `Library` therefore stays `3`, while a single-file `Specs` and every file of a v3 tree say `"3.1.0"`. The v3
tree reuses the v4 tree's layout without change and holds the classic v3 JSON of each entry. The reference support
table became `[3.0.0,3.2.0),[4.0.0,4.1.0)`.

## Summary

Before this revision, v3 had one distribution kind and one storage layout. A package could publish only a `Library`,
which carries every definition. A tool that wanted a package's public face had to ship the definitions too. And only
the draft Ion tree could hold v3 as a directory of files
([issue 970](https://github.com/finos/morphir/issues/970)). The JSON and YAML trees, which the rest of the toolchain
reads, were defined for v4 only.

Both additions change what a reader accepts. Under
[decision 0016](/decisions/0016-support-tables-are-intervals-and-a-patch-changes-nothing-observable.md) a change of
that kind is a minor revision, so this is `3.1.0` and not a patch of `3.0.0`.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Writers emit the lowest version that fits | Chosen | Every existing `3.0.0` reader keeps reading every `Library` a new writer produces |
| Writers always emit `3.1.0` | Rejected | Every new `Library` file would be refused by every `3.0.0` reader, for no change in content |
| Tree files hold classic fragments verbatim, envelope included | Rejected | The layout's paths, stems and `fileNames` all work on canonical strings |
| v3 trees use the v4 payload spelling at version 3 | Rejected | That is a migration to v4, and it loses the v3 attribute slots |
| One Ion `Element` model under all three tree profiles | Deferred | It would tie the JSON and YAML trees to a draft codec |

## Why

### Lowest-version writers

A reader that stays on `[3.0.0,3.1.0)` refuses a `3.1.0` document with `unsupported_format_version_minor`, as decision
0016 requires. If every writer moved to `"3.1.0"`, every new `Library` file would hit that refusal in morphir-elm,
morphir-scala, morphir-python and morphir-ui, although the file holds nothing `3.0.0` cannot say. Emitting the lowest
version that fits confines the refusal to content that is new: a `Specs` distribution and a v3 tree. The rule is
proven by the Rust codec and the kit: kit case document-tree-0011 reads a v3 tree back as a single-file `Library` with
`"formatVersion": 3`, and distributions-0011 pins a single-file `Specs` at `"3.1.0"`.

The same rule explains the refusal of a `Specs` declared below `3.1.0`. A `3.0.0` reader has no `Specs` case, so a file
that says `3` and holds a `Specs` would be read by some readers and refused by others with an unrelated error. Every
reader that knows `Specs` refuses it with `specs_before_3_1`, in JSON, YAML and Ion alike.

### Reusing the v4 tree

The v4 tree already settled the hard parts of a file-per-definition layout: the logical paths, the escape of names into
file stems, the path budget, truncation with a hash suffix, the `fileNames` map, the `@` version segment under `deps/`,
and the refusal of stray files. Each of those rules has kit cases. A second layout for v3 would repeat every one of
those decisions and every one of those cases, and the two would drift. Reusing the layout means a v3 tree differs from
a v4 tree only in what a file says. The kit's v3 cases (document-tree-0010 to 0017) are the v4 cases with v3 contents,
which is the evidence that nothing in the layout needed to change.

Classic names convert to canonical strings and back without loss, so the envelope can use the canonical spelling the
layout needs. The payload under `def` or `spec` stays classic v3 JSON, so a v3 tree keeps every attribute slot a
single-file v3 document has, including the inferred types morphir-elm writes on expressions.

### A generic layout in the kit

The Rust kit already held the tree rules once, for v4. The implementation made that code generic over the file model
(`TreeModel` in `morphir_core::ir::layout`) and added a v3 model beside the v4 one. A reader chooses the model from the
manifest's `formatVersion`. The v4 reader refuses a manifest of major 3 with `version_mismatch` at
`manifest#/formatVersion`, so a v3 tree never fails later on the first payload that is not v4. This is a judgement about
maintenance, not a measured result: one implementation of the rules is less to keep in step than two.

## Alternatives rejected

### Writers always emit 3.1.0

This is the simplest writer rule, and it matches what a writer does for v4 revisions. It was rejected because it
breaks readers for no gain. A `Library` needs nothing from `3.1.0`, and every other binding that reads v3 still
declares a `3.0` ceiling. Those readers would refuse every file a new CLI wrote, including files they read today.

### Classic fragments verbatim in tree files

A tree file could hold exactly what a single-file v3 document holds at that position, envelope included: word arrays
for the package, the module path and the name. It was rejected because the layout does not work on word arrays. The
file stem is an escape of the canonical name, `fileNames` is keyed by canonical name, and the manifest's `dependencies`
must match directory paths. Keeping classic arrays in the envelope would need a second set of those rules or a
conversion at every step. The payloads, where the attribute slots live, do stay verbatim.

### The v4 spelling at version 3

A v3 tree could have used v4 payloads and kept the version at `3`. It was rejected because a v4 payload cannot hold a
v3 distribution without loss. The v4 attribute model differs from the v3 one, so the result would be a migration to v4
labelled as v3. A tool that wants v4 already has `morphir migrate`.

### One Ion Element model for every tree profile

Ion's data model is a superset of JSON's, so an Ion `Element` could be the one in-memory model under the JSON, YAML and
Ion trees. That idea was deferred, not adopted. The Ion spelling is still `ionVersion` `0.1.0-draft.1`, and making it
the model of the JSON and YAML trees would tie released formats to a draft. The Ion tree keeps its own layout code for
now. The generic layout leaves room to move it onto the same rules later (`TreeParts<ion_rs::Element>` in the design
draft).

## Consequences

1. The v3 JSON Schema accepts a `Specs` distribution beside `Library`, and requires `"3.1.0"` or later for it.
2. `docs/spec/ir/schemas/v3/document-tree-files.md` specifies the v3 tree, and the v3 `whats-new.md` records `3.1.0`.
3. The reference support table and the morphir-rust table became `[3.0.0,3.2.0),[4.0.0,4.1.0)`. Each other binding
   raises its own table when it implements `3.1.0`. The TypeScript binding, morphir-elm, morphir-scala and
   morphir-python have follow-up issues.
4. morphir-ui keeps `[3.0.0,3.1.0),[4.0.0,4.1.0)` until it adopts `3.1.0`. It reads every `3.0.0` document and refuses
   a `3.1.0` document with the minor-version diagnostic.
5. `morphir migrate --target-version v3 --output-layout vfs` writes v3 trees in the JSON, YAML and Ion profiles, and the
   manifest of each decides the version on read. A migrated v3 `Specs` becomes a v4 `Specs` with `"formatVersion": 4`.
6. Compile output stays v4, and an `Application` distribution has no v3 form.

## Revisit when

- A `3.2.0` is proposed. It would be the first time a v3 minor needs the lowest-version rule to choose between two
  new releases.
- A binding other than morphir-rust implements v3 trees and finds a rule the v4 layout does not express for v3.
- The Ion spelling leaves draft, which reopens the choice of one in-memory model for all three tree profiles.
- The classic IR gains package versions, which would fill the `@` segment under `deps/` for v3 as for v4.

---
type: Decision Record
title: "Dependency directories nest the package path and mark the version segment with @"
description: "A document tree lays a dependency out as deps/<package path>/@<version>/<module path>/, where the segment beginning with @ ends the package path and carries the version, empty until the model has one; pkg/ keeps no segment because it holds exactly one package."
state: Accepted
decided: 2026-09-15
tags: [ir, ir-v4, document-tree, packages, naming, mck]
status: draft
---

# Dependency directories nest the package path and mark the version segment with @

A document tree lays a dependency out under `deps/` with the package path and the module path both nested as
directories, and one segment between them that begins with `@`:

```text
deps/<package path>/@<version>/<module path>/module.yaml
deps/morphir/_sdk/@/list/map.value.yaml              # today: the model carries no package version
deps/morphir/_sdk/@3.0.0/list/map.value.yaml         # once it does
```

The segment beginning with `@` ends the package path. Whatever follows the `@` is the package version, and it is
empty until the v4 model carries one. A reader never guesses where a package path stops, and a writer never has to
check whether one listed package path is a prefix of another. `pkg/` keeps no such segment, because a tree holds
exactly one own package and the distribution manifest names it. A `morphir://` URI mirrors the directory path, so
the same rule reads both.

## Summary

The dependency layout ruled during the YAML profile work put a module path directly after a package path. Both
are multi-segment, so a tree holding packages `a` and `a/b` writes module `b/c` of `a` and module `c` of `a/b`
to the same directory. The draft packages page had avoided this with a version directory between the two; that
segment was dropped because the model has no version to put in it. This record restores the slot and makes it
self-marking, so it works with an empty version now and takes a real one later without moving a file. Four
layouts were compared. Flattening a path into one `.`-joined directory name also removes the ambiguity, but it
adds a second serialization of `Path`, and the mixed forms need two rules for no gain.

| Option | Outcome | Why |
| ------ | ------- | --- |
| Nested package and module, `@<version>` segment between them | Chosen | One `Path` serialization, Elm and Go shape, versions land in the slot with no file moving |
| Nested package and module, version as a bare directory | Rejected | A bare SemVer works only once every dependency has a version; an empty slot needs a marker anyway |
| Nested package and module, `@<version>` suffix on the final package segment | Rejected | One level shorter, but `_sdk@` reads badly while the version is empty, and Go's cache uses the segment form |
| Flat package, nested module (`deps/morphir._sdk/list/`) | Rejected | Two serializations of `Path`; the tree changes shape when versions arrive |
| Nested package, flat module (`deps/morphir/_sdk/list/`, `domain.orders.shipping/`) | Rejected | Two serializations of `Path`; submodules leave their parent's directory; no precedent |
| Flat package and flat module | Rejected | Simplest reader and one `.` rule, but loses the organisation directory and still changes shape when versions arrive |
| Reject prefix-overlapping dependency names | Rejected | Makes a valid distribution unrepresentable instead of representing it |
| Mark a package root with a manifest file | Rejected | A marker cannot separate `a` with module `b/c` from `a/b` with module `c`; only position can |
| Replace the `_` initialism escape with Go's `!` | Rejected | `!` is the YAML tag indicator and a shell history character; decision 0001's escape has no permissive parsing to conflict with |

## Why

### The string forms already delimit; the directory did not

The naming draft gives every identity a canonical string. A fully qualified name is `package:module#name`, so
`morphir/SDK:list#map` puts a colon between the package path and the module path. The resource scheme then maps
that onto the tree as `morphir://deps/<package>/<module>/<stem>.type.yaml`, and the colon disappears. The
directory needs its own delimiter because a colon is not a legal path character on Windows.

The escape layer cannot supply one. Package segments and module segments go through the same escape, and the file
stem grammar from [decision 0012](/decisions/0012-one-legacy-name-grammar-and-one-file-stem-definition.md) is
`^_?[a-z0-9]+(-_?[a-z0-9]+)*(__[0-9a-f]{8})?_?$`. Both `_` and `-` are inside that alphabet and `__` marks
truncation, so no spelling of a stem can mark a boundary. The delimiter has to be a character a stem never
contains. `@` is legal on every filesystem and in a URL path segment, and the package-system design already implies
it through its PURL mapping, `pkg:morphir/<namespace>/<name>@<version>`.

### Other package managers split on name depth

Systems whose names have a fixed depth use a bare version directory. Elm, Morphir's ancestor, stores
`packages/<author>/<project>/<version>/` and needs no marker because a package name is exactly two segments.
NuGet stores `packages/<id>/<version>/` with the dotted id kept as one segment. Maven expands the group id into
directories and relies on `maven-metadata.xml` and the jar's `<artifact>-<version>` name; it never solved the
overlap between `a.b:c` and `a:b`, and lives with it.

Systems whose names have variable depth reach for `@`. Go module paths nest, so `github.com/x/y` and
`github.com/x/y/z` can both be modules, which is exactly this problem. Go's download cache uses a directory named
`@v` after the module path, and its extracted source uses `github.com/x/y@v1.2.3/`. Go chose `@` because it can
never appear in a module path. pnpm stores `.pnpm/<name>@<version>/`, and PURL, jsr and npm specifiers all put
`@` before the version. Morphir package paths are variable depth, so Morphir is in this group.

### The slot has to be self-marking

Keeping the draft's version directory as a bare SemVer only works once every dependency has a version. Until the
model carries one, an empty slot needs a spelling, and a fake version such as `0.0.0` would lie about identity. A
segment that begins with `@` is recognisable whether or not a version follows, so the grammar is one rule now and
the same rule later. The segment form, `_sdk/@3.0.0/`, was preferred over the suffix form, `_sdk@3.0.0/`, because
the empty case reads as a slot rather than a typo and because it matches Go's cache layout and the Elm directory
shape.

### Flat directories were considered and rejected

Collapsing a path into one directory name joined with `.` also removes the ambiguity, since the package is then
always the first segment under the root. It would give the reader a fixed-depth tree and match the NuGet cache.
It costs a second serialization of `Path`: the naming spec joins with `/`, the fully qualified name builds on that,
and every tool mapping names to files would learn a `.` rule for directories on top. It loses the organisation
directory that Elm, Maven and Go all offer. And it still changes the tree's shape when versions arrive, because a
bare version directory appears between package and module. The two mixed forms, flat package with nested modules
and nested package with flat modules, each remove the ambiguity by fixing one side's depth, but each needs two
serialization rules and carries the same shape change. If flattening were chosen, flattening both sides would be
the consistent version of it.

### `!` is not a better initialism marker

Go's `!` came up because Go escapes uppercase letters with it. Go's escape is a per-letter case flag over module
paths that may legitimately contain uppercase and underscores, so `_` was unavailable there. Morphir names are
word lists over `[a-z0-9]` with a per-word initialism flag, and a word can never contain `_`, which is why
[decision 0001](/decisions/0001-name-canonicalization-and-initialism-encoding.md) found the escape reversible.
That record rejected `_` only for the canonical parsed form, where `snake_case` is a permissive input; the escape
layer has no permissive parsing. `!` would fail three tests decision 0001 already applied to `~` and `%`: it is
the YAML tag indicator, so a stem such as `!sdk` cannot begin a plain scalar and the YAML profile's writer would
have to quote it; interactive bash and zsh expand it as history; and it is a URI sub-delimiter that some encoders
turn into `%21`. The `_` escape stays.

## Consequences

1. The document-tree specification page spells the dependency layout as `deps/<package path>/@<version>/…`, with
   the empty-version form shown, and states why `pkg/` carries no segment.
2. The naming draft's URI examples under `deps/` gain the segment. The `ModuleName` string form, which joins package
   and module with `/` and is ambiguous for the same reason, is tracked separately.
3. The reference layout in finos/morphir-typescript classifies a `deps/` path by the `@` segment, drops the
   longest-prefix search, and writes the segment; the kit case for a dependency and the kit README follow.
4. Package versioning, when it lands in the v4 model, fills the segment. No other path changes.

## Revisit when

- The v4 model gains a package version and the distribution manifest's `dependencies` entries need to carry it.
- A tree must hold two revisions of the same dependency, which the empty slot cannot express.

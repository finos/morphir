# Packages

A substrate package is a directory of markdown files (and any accompanying
alternative-format artifacts) that declares its identity and dependencies
in a manifest. The package system exists so that cross-repository markdown
links resolve reliably without extending markdown itself: dependencies are
vendored into a conventional directory, and authors write ordinary relative
links through that directory.

No custom link protocol is introduced. No build step rewrites author-written
markdown. Tooling provides installation, version resolution, and link
validation; everything else is plain markdown.

## Package Kinds

Every package declares one of three kinds:

- **Library** — a package intended to be depended on by other packages.
  It contributes types, concepts, operations, or any other reusable
  specification material. The substrate language specification itself
  is distributed as a library.
- **Corpus** — a leaf package that assembles libraries into an
  authoritative body of specification for a specific domain — an
  organization's regulatory model, a particular product's rule set, a
  demonstrative example. A corpus is not itself depended on; it is the
  consumer at the bottom of the dependency tree.
- **Horizontal** — a package whose documents run in parallel with a
  corpus and annotate it from a particular cross-cutting perspective:
  examples, regulatory citations, test scenarios, glossary entries,
  change history, training notes. A horizontal does not contribute to
  the corpus's primary specification chain; it sits alongside it and
  links *into* corpus sections. See [Horizontals](#horizontals) for
  semantics.

All three kinds use the same manifest, directory layout, and link
conventions. They differ in their expectations and in how the tooling
treats them during context assembly:

- A corpus must contain a `README.md` at its root that serves as the
  entry point — the first document a reader opens. It orients the
  reader to the corpus's scope, reading order, and conventions, and
  links to everything else. Libraries are encouraged to follow the
  same convention but are not required to; a library's natural entry
  point is often the specification file a consumer links to directly.
- A corpus typically omits `version` from its manifest, because a
  corpus is generally not published for others to depend on. A library
  must declare `version` to be installable.
- A horizontal must declare `version` if it is to be installed by other
  packages, and follows the same publishing rules as a library.

## Horizontals

A horizontal is an independent package whose documents reference
sections of a corpus (or of libraries the corpus depends on) by
ordinary markdown links. Conceptually, the corpus is the spine and
each horizontal is a parallel column annotating it from one angle.
There can be any number of horizontals attached to a single corpus,
and a horizontal may target multiple corpora.

Horizontals exist because some material genuinely belongs alongside a
corpus rather than inside it. Worked examples bloat a normative
specification; regulatory citations rot when interleaved with
definitions; test scenarios have a different audience than the rules
they exercise. Keeping these in separate packages preserves the
corpus's cohesion while still allowing the material to travel with it
when a reader needs it.

### Reverse-link semantics

The defining property of a horizontal is that its links into the
corpus are followed *backwards* during context assembly. A normal
forward link from file F to section S means "to understand F, you
also need S". A horizontal's link from H to S means "if you are
reading S, the annotation in H is relevant — pull it in too".

Reverse traversal applies only to links *originating in a horizontal*
and pointing at a non-horizontal target. Forward traversal is
universal: every outgoing link from an already-included section is
followed, regardless of which package the linking section or the
target lives in. So a horizontal section pulled in via reverse
traversal can in turn pull in further corpus sections, library
sections, or sections of another horizontal — the same way any
included section would.

Links between horizontals are therefore handled forward, not in
reverse. If horizontal H1 is selected and a section of H1 is
included, any horizontal it links to (H2, H3, …) gets that targeted
section pulled in, even if H2 was not itself passed via
`--horizontal`. The opt-in flag controls only which horizontals are
*scanned for reverse links into the corpus*; it does not gate forward
reachability. This keeps the rule symmetric with how a corpus reaches
into its library dependencies without each library needing to be
separately opted in.

### Selection

A horizontal is *scanned for reverse links* only when the user opts
it in for that invocation via `--horizontal`. There is no automatic
reverse-scan activation based on manifest presence: a corpus may have
ten horizontals available and a given `substrate context` call may
want zero, one, or all of them reverse-scanned depending on the
audience. The `--horizontal` flag on
[`substrate context`](#substrate-context-filemdsection-filemdsection-)
selects which horizontals are in scope for reverse traversal.

Forward reachability is independent of `--horizontal`. Once any
horizontal section is in the included set — whether reached by reverse
traversal from an opted-in horizontal, by forward traversal from
another included section, or supplied directly as a command-line
argument — its outgoing links are followed normally, and any
horizontal it transitively points at is pulled in along with it.

## Package Identity

A package's declared name is a forward-slash-separated path such as
`myorg/fr2052a-lcr` or `concepts/core`. It may have any number of segments
and does not need to match the hosting repository's name or owner. The name
is used as the install path under `substrate/` and as the stable identifier
that consumers write in their cross-package links.

Dependency keys in `substrate.json` are the GitHub repository paths used
to locate and clone the package (e.g. `finos/morphir`).
A single repository may contain multiple `substrate.json` files and thus
publish multiple packages under different names.

A package version is a git tag on the source repository, interpreted as
[semver](https://semver.org). A tag `v0.1.3` satisfies a manifest entry
of `^0.1.0`. Tags without a leading `v` are accepted. A branch name (e.g.
`main`) may be used in place of a semver range, in which case the latest
commit on that branch is installed and the lockfile records the resolved
commit hash.

## Directory Layout

A corpus that depends on one or more packages has the following layout:

```text
├── substrate.json               # manifest
├── substrate/
│   └── <package-name>/          # vendored package contents (mirrors declared name)
└── <corpus's own content>
```

The `substrate/` directory contains the full contents of each installed
package mirroring its declared name as a path. For example a package named
`myorg/concepts` is vendored at `substrate/myorg/concepts/`.

Both artifacts — `substrate.json` and the entire `substrate/` tree —
are committed. GitHub renders cross-package links natively because the
target files are present at the expected paths. Updating a dependency is
an explicit commit with a reviewable diff.

## Manifest

The manifest is `substrate.json` at the corpus root:

```json
{
  "package": {
    "name": "MyOrg/fr2052a-lcr",
    "kind": "corpus"
  },
  "dependencies": {
    "AttilaMihaly/morphir-substrate": "^0.1.0"
  }
}
```

The `package` object declares this package's own identity. The `kind`
field is required and takes one of the values defined in
[Package Kinds](#package-kinds): `"library"`, `"corpus"`, or
`"horizontal"`. A library and a horizontal additionally declare
`version`; a corpus typically omits it.

An optional `subdir` field under `package` specifies a sub-directory
within the repository where the substrate documents reside. When `subdir`
is set, `substrate install` extracts only that sub-directory's contents
into the vendored location rather than the whole repository:

```json
{
  "package": {
    "name": "MyOrg/shared-concepts",
    "kind": "library",
    "version": "1.0.0",
    "subdir": "specs"
  }
}
```

The `dependencies` object lists each required package and a version
constraint. Keys are GitHub repository paths (`org/repo`); values are either:

- A semver range following standard operators (`^`, `~`, `>=`, exact), or
- A branch name (e.g. `main`), which pins to the latest commit on that
  branch at install time.

## Authoring Cross-Package Links

Authors write ordinary markdown links — inline or reference-style —
using relative paths through `substrate/`. The existing
[link reference conventions](../../language.md#link-references) apply
unchanged:

```markdown
Retail Outflow Rate uses a [Decision Table][dt] over [records][rec].

[dt]: /substrate/core/concepts/decision-table.md
[rec]: /substrate/core/concepts/record.md
```

Link paths use the package's declared name (from its own `substrate.json`),
not the repository path. Reference-style definitions keep the verbose paths
out of the prose.

## Exports

Every markdown file within an installed package is addressable from
depending corpora. Packages do not declare an explicit exports list;
any file a consumer chooses to link to is part of the public surface.
Package authors who wish to signal a narrower intended surface should
do so through package documentation rather than enforcement.

## Commands

### `substrate init`

Interactively scaffolds a new package in the current directory. Prompts
for the minimum information needed to produce a valid `substrate.json`,
then writes the file and creates the `substrate/` vendor directory.

| Prompt | Default | Notes |
| --- | --- | --- |
| Package name | `<git-remote-org>/<directory-name>` | Any path with no leading/trailing slashes or `..` |
| Kind | `corpus` | `library`, `corpus`, or `horizontal` |
| Version | `0.1.0` | Libraries and horizontals; omitted for corpora |

After the prompts, `substrate init` writes `substrate.json` with the
supplied values and creates an empty `substrate/` directory. It does not
add any dependencies; use `substrate install` after editing
`substrate.json` to add them.

The command aborts without writing anything if `substrate.json` already
exists. Pass `--yes` to accept all defaults without prompting.

### `substrate install`

Reads `substrate.json` and populates `substrate/` so that every declared
dependency is present at its expected path.

For each dependency the command:

1. Resolves the version constraint — a semver range is matched against the
   repository's git tags; a branch name is resolved to the current HEAD
   commit of that branch.
2. Clones the repository at the resolved ref.
3. Reads the cloned package's own `substrate.json` to determine its
   declared `name` and, if present, its `subdir`.
4. Copies the relevant content (the full clone, or just the `subdir`
   subdirectory when specified) into `substrate/<declared-name>/`.

The command is idempotent: running it repeatedly with an unchanged
manifest yields no changes.

### `substrate update [<package>]`

Bumps the resolved version of the named package (or of every
dependency, when no package is named) to the latest git tag that
satisfies the manifest's semver range, or to the current HEAD commit for
branch-pinned dependencies. Updates the vendored contents under
`substrate/` and leaves the working tree staged for review and commit.

### `substrate validate`

Walks every markdown file in the corpus and verifies that every link
target exists on disk. Applies to both inline links and reference-style
definitions. Reports unresolved links and exits with code `1` if any
are found.

The scan root is determined by locating the nearest `substrate.json`
from the current working directory (walking up the directory tree).
If the manifest's `package.subdir` field is set, the scan starts at
that sub-directory within the package root; otherwise it starts at the
directory containing `substrate.json`.

Validation is the safety net for manually authored reference
definitions: any typo or stale path after an update surfaces here.
Validation checks link resolution only; it does not verify semver
constraints at this stage.

### `substrate publish`

Prepares a library or horizontal for release. Aborts if the package's
`kind` is `corpus`, since corpora are not published for others to
depend on.

1. Confirms `substrate.json` is committed and the working tree is clean.
2. Runs `substrate validate` and aborts on any failure.
3. Creates a git tag matching the `package.version` field and pushes
   it to the origin remote.

Publishing does not interact with any central registry. Consumers
depend on the tagged commit directly via their own manifest.

### `substrate context <file.md[#section]> [<file.md[#section]> ...]`

Takes one or more markdown files (or sub-sections of files) and emits a
single self-contained markdown document on standard out, suitable for
feeding to an LLM as compact context. Cross-file references are
rewritten as in-document anchors so the result has no external
dependencies. The command is intended to be invoked by AI agents that
need a focused slice of the corpus without pulling in unrelated
material.

Each argument is either a file path (`spec.md`) or a file with a
section anchor (`spec.md#decision-table`). The anchor matches the
GFM-slugified heading of the section.

| Option              | Default | Description                                                                      |
| ------------------- | ------- | -------------------------------------------------------------------------------- |
| `--no-tree-shaking` | off     | Include every referenced file in full instead of tree-shaking to sections only. Links are still rewritten as in-document anchors. |
| `--no-inline`       | off     | Skip link traversal entirely. Only the explicitly-specified files or sections are included; no cross-file dependencies are followed. Links whose targets were not included are left unchanged. |
| `--horizontal <path>` | none  | Include the named horizontal package in the assembly. The path points at a directory containing a `substrate.json` whose `package.kind` is `horizontal`. Repeatable: `--horizontal a --horizontal b` activates both. Documents in the named horizontal are scanned for links targeting included corpus sections; matching horizontal sections are pulled in via reverse traversal. See [Tree-shaking algorithm](#tree-shaking-algorithm). |

#### Tree-shaking algorithm

The command tree-shakes the corpus at section granularity, so only the
content reachable from the supplied roots ends up in the output.

1. **Seed the work queue** with each command-line argument as an
   *inclusion job*. A job is either *whole-file* (no anchor) or
   *section* (with anchor).
2. **Process jobs.** For each job, parse its file once and build a
   section tree (a heading + its descendants, recursively). Mark the
   requested unit as included. A *whole-file* job that targets a file
   containing a section with the slug `summary` is silently rewritten
   to a section job for that summary — the section exists precisely to
   give consumers a compact synopsis instead of the entire document.
   Files without a summary are pulled in whole. A *section* job marks
   the named section's full subtree plus the *framing context* of each
   ancestor — the ancestor's heading line and any prose between that
   heading and its first child subheading. Sibling subsections that
   physically precede the target are **not** pulled in unless
   something separately links to them.
3. **Walk links transitively.** For every link found in the included
   content (inline or reference-style), enqueue a new job:
   - External URLs (`http`, `https`, `mailto`) are ignored.
   - Same-file `#anchor` links resolve within the same file.
   - Cross-file `path[#anchor]` links resolve relative to the linking
     file and become a new inclusion job.
   Jobs are deduplicated by `(file, anchor|whole)` so cycles and
   diamonds terminate.
3a. **Reverse-link from horizontals.** For each horizontal supplied
    via `--horizontal`, build (once, lazily) an index mapping every
    target it links to — `(file, anchor|whole)` — to the set of
    horizontal sections that contain a link to that target. A
    horizontal section is the smallest enclosing heading subtree
    around the link; if the link sits at the top of the file before
    any heading, the whole file is the unit. Whenever step 2 marks a
    non-horizontal section S as included, consult the index: for each
    horizontal section H that links to S (or to an ancestor of S
    whose subtree contains S, when the link is whole-file), enqueue H
    as an inclusion job. The newly-included horizontal section then
    re-enters step 3 and its outgoing links are followed forward
    normally — including links to other horizontals, which pull in
    their targeted sections without requiring those horizontals to be
    separately passed via `--horizontal`. Reverse traversal applies
    only to links whose source is in a horizontal package opted in via
    `--horizontal` and whose target is not in any horizontal; links
    from one horizontal to another, or within the same horizontal,
    are not followed in reverse.
4. **Build the file dependency graph.** Each forward link from file F
   to file G adds an edge F → G. Reverse links from horizontals do not
   add edges; horizontal sections are placed alongside the corpus
   section they annotate, immediately after it in render order.
   Topologically sort files with dependencies first (sinks before
   sources). Cycles, if any, are broken by condensing each strongly-
   connected component and ordering members by file path.
5. **Render in topo order.** For each file, emit the included nodes in
   their original document order. For whole-file inclusions, that's
   the entire file. For partial inclusions, walk the file's top-level
   nodes and keep, for each marked section, its full subtree, plus
   each ancestor's heading and intro prose. Skipped sibling sections
   leave gaps; no ellipsis marker is inserted.
6. **Rewrite cross-references.** Build a global anchor table mapping
   every emitted section to a unique anchor: start from the section's
   GFM slug and append `-2`, `-3`, … on collision. A bare `file.md`
   link rewrites to the file's primary section anchor (its h1, or
   first heading). A `file.md#anchor` link rewrites to the matching
   section's unique anchor. Links whose target was not included are
   left unchanged so the user can see what was pruned.

The output is a single markdown document with possibly multiple `#`
headings (one per included file). No frontmatter or boilerplate is
added. The command exits 0 on success; missing files or unresolvable
section anchors in the supplied arguments cause exit 1.

### `substrate stats [<file>]`

Prints statistics about a markdown file to standard out. When no file
argument is supplied, reads from standard in.

```
Words:                1,234
Lines:                  567
Tokens (est.):        2,345

Links:
  External:              12
  Local:                  8
  Anchors:               34

Sections:               56
Max heading depth:        3
Avg heading depth:      2.1
```

| Statistic          | Description                                                                         |
| ------------------ | ----------------------------------------------------------------------------------- |
| Words              | Non-code prose words (code blocks and inline code are excluded).                    |
| Lines              | Raw line count of the source file.                                                  |
| Tokens (est.)      | Rough token estimate: `ceil(character_count / 4)`.                                  |
| Links — External   | Links whose URL starts with `http://`, `https://`, or `mailto:`.                    |
| Links — Local      | Links to other files (relative paths without a leading `#`).                        |
| Links — Anchors    | Same-file fragment links (URL starts with `#`).                                     |
| Sections           | Total number of headings at any depth.                                              |
| Max heading depth  | Deepest heading level present (`1`–`6`).                                            |
| Avg heading depth  | Mean heading level across all sections, rounded to one decimal place.               |

Both inline links and reference-style link definitions are counted.
The command exits 0 on success and 1 if the file cannot be read.
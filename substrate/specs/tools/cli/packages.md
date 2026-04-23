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

Every package declares one of two kinds, mirroring the distinction Elm
and Cargo draw between reusable code and end deliverables:

- **Library** — a package intended to be depended on by other packages.
  It contributes types, concepts, operations, or any other reusable
  specification material. The substrate language specification itself
  is distributed as a library.
- **Corpus** — a leaf package that assembles libraries into an
  authoritative body of specification for a specific domain — an
  organization's regulatory model, a particular product's rule set, a
  demonstrative example. A corpus is not itself depended on; it is the
  consumer at the bottom of the dependency tree.

Both kinds use the same manifest, directory layout, and link
conventions. They differ only in two expectations:

- A corpus must contain a `README.md` at its root that serves as the
  entry point — the first document a reader opens. It orients the
  reader to the corpus's scope, reading order, and conventions, and
  links to everything else. Libraries are encouraged to follow the
  same convention but are not required to; a library's natural entry
  point is often the specification file a consumer links to directly.
- A corpus typically omits `version` from its manifest, because a
  corpus is generally not published for others to depend on. A library
  must declare `version` to be installable.

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
field is required and takes one of the two values defined in
[Package Kinds](#package-kinds): `"library"` or `"corpus"`. A library
additionally declares `version`; a corpus typically omits it.

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
| Kind | `corpus` | `library` or `corpus` |
| Version | `0.1.0` | Libraries only; omitted for corpora |

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

Validation is the safety net for manually authored reference
definitions: any typo or stale path after an update surfaces here.
Validation checks link resolution only; it does not verify semver
constraints at this stage.

### `substrate publish`

Prepares a library for release. Aborts if the package's `kind` is
`corpus`, since corpora are not published for others to depend on.

1. Confirms `substrate.json` is committed and the working tree is clean.
2. Runs `substrate validate` and aborts on any failure.
3. Creates a git tag matching the `package.version` field and pushes
   it to the origin remote.

Publishing does not interact with any central registry. Consumers
depend on the tagged commit directly via their own manifest.

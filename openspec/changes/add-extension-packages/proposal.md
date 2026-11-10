# Proposal

## Why

The Native AOT `morphir` host from morphir-dotnet has no built-in F# frontend, so it needs an installed one. That frontend, `org.finos.morphir.fsharp-frontend`, is a self-contained .NET program published as a folder of about 239 files and 121 MB (finos/morphir-dotnet#569, profile `SelfContainedProcess.pubxml`). The F# compiler inside it must find its reference assemblies as real files, so it cannot be one file.

Today the extension release descriptor, the content-addressed store, the extension lock and activation all assume that an extension artifact is one file. So the frontend cannot be published, installed, locked or started as it is built.

On 9 November 2026 the maintainer decided that the shared extension contract is extended so that an extension can be a multi-file package ([finos/morphir#1146](https://github.com/finos/morphir/issues/1146)). The maintainer did not take two other options: a self-unpacking single-file form of the frontend, and leaving the Native AOT offering without an installable F# frontend. This change is the reviewed contract for that decision.

For example, after this change the frontend's descriptor lists `fsharp-frontend-0.6.0-win-x64.zip` with a `package` member that names its entry point `morphir-fsharp-frontend.exe` and the digest of its unpacked tree. A host checks and unpacks the archive once, stores the tree by that digest, and starts the entry point from the store.

## What Changes

- **A package is an artifact with a `package` member.** It is delivered as one ZIP or gzip-compressed tar archive and names one entry point. Only `process` artifacts can be packages. An artifact without the member is a single-file artifact and keeps its meaning exactly.
- **Two digests.** The artifact's `sha256` stays the archive's digest, which repositories and toolset recipes already bind. A new tree digest, the SHA-256 of a canonical manifest of paths, sizes, file digests and executable flags, names what is unpacked. The descriptor, index record, catalog and lock carry both.
- **Safe unpacking, with stable refusal codes.** Links, devices, traversal, absolute and drive paths, backslashes, Windows device names and trailing dots, non-NFC names (Unicode 17.0.0), names that collide ignoring case, duplicates, file and directory conflicts, entries outside a declared root, and bounds on size, count, path length and depth. One code per rule, checked in a fixed order.
- **Modes.** The entry point and a listed set of files are executable on Unix. Nothing else from the archive's metadata is used.
- **Store and publication.** A tree is staged, verified, then published by one rename at `store/extensions/packages/sha256/<tree digest>/`. It is immutable, and it is recorded only after it is published.
- **Launch.** A host starts the entry point from the store by its absolute path. On Windows the entry point ends in `.exe` and every stored path fits in 259 UTF-16 code units.
- **Removal.** Uninstall never deletes a package. An explicit collection deletes only packages that no lock names and no running process leases.
- **Trust is unchanged.** Integrity checks say which bytes were installed, not who published them.
- **Conformance data.** Language-neutral cases that the .NET and MoonBit hosts both run.
- **Toolchain follow-up.** The toolchain contracts close their question on multi-file process artifacts and state how a recipe and lock bind a package. This is a task on those contracts, not an edit here.

**Versions.** The descriptor, index record, catalog and lock gain the `package` member at a new exact draft. If nothing has been published at finos/morphir#1149's drafts when this change is approved, this change refines those drafts in place; otherwise it takes the next drafts. The design states the cost of each.

**Not breaking** for single-file artifacts. A host that reads the package drafts but cannot install packages refuses a package rather than running its archive.

## Capabilities

### New Capabilities

- `extensions/extension-packages`: what a package is, its digests and manifest, the unpacking rules and refusal codes, file modes, store layout and publication, launch, removal, trust and conformance.

### Modified Capabilities

None. The descriptor, record, catalog and lock are design drafts under `docs/design/draft/extensions/`, not main specs. The capability above records the new behavior, and the tasks update those pages.

## Tracking

The owning issue is [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is not used for this proposal; the tasks name no Beads ids, and Beads issues are created when tracking is available.

## Impact

- **finos/morphir:**
  - the extension distribution design page, which defines the shared files;
  - a normative package rule page and its conformance data;
  - later, the toolchain contracts.
- **finos/morphir-dotnet:**
  - its installer (finos/morphir-dotnet#567) installs packages;
  - the F# frontend is published as a package (its adoption task 3.3).
- **MoonBit host:** adopts the rules and runs the cases in its own repository.
- **Optional later work, gating nothing:** finos/morphir-rust and the Rust CLI.
- **Depends on** finos/morphir#1149, whose drafts and shared-file definitions this change extends. The design names each dependency.

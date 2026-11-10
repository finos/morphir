# Proposal

## Why

The Native AOT `morphir` host from morphir-dotnet has no built-in F# frontend, so it needs an installed one. That frontend, `org.finos.morphir.fsharp-frontend`, is a self-contained .NET program published as a folder of about 239 files and 121 MB (finos/morphir-dotnet#569, profile `SelfContainedProcess.pubxml`). The F# compiler inside it must find its reference assemblies as real files, so it cannot be one file.

Today the extension release descriptor, the content-addressed store, the extension lock and activation all assume that an extension artifact is one file. So the frontend cannot be published, installed, locked or started as it is built.

On 9 November 2026 the maintainer decided that the shared extension contract is extended so that an extension can be a multi-file package ([finos/morphir#1146](https://github.com/finos/morphir/issues/1146)). The maintainer did not take two other options: a self-unpacking single-file form of the frontend, and leaving the Native AOT offering without an installable F# frontend. This change is the reviewed contract for that decision.

For example, after this change the frontend's descriptor lists `fsharp-frontend-0.6.0-win-x64.zip` with a `package` member. The member names the entry point `morphir-fsharp-frontend.exe` and the digest of the unpacked tree, and the descriptor marks the member critical. A host reads and checks the archive once, stores the tree read-only by that digest, and starts the entry point from the store.

## What Changes

- **A package is an artifact with a `package` member, always marked critical.** It is delivered as one ZIP or gzip-compressed tar archive and names one entry point. Only `process` artifacts can be packages. A document that carries a package lists it in `critical`, so a host built without this change refuses the document instead of running the archive as a program.
- **Single files.** An artifact without the member is the executable itself and keeps its meaning. A process artifact named like an archive but without the member is refused; extensions shipped that way today publish a one-file package instead.
- **Two digests.** The artifact's `sha256` stays the archive's digest, which repositories and toolset recipes already bind. A new tree digest, the SHA-256 of a canonical manifest of paths, sizes, file digests and executable flags, names what is unpacked.
- **Defined reading, safe unpacking, stable codes.** The change says how a ZIP or tar entry's name, type, size and order are read, and refuses what it does not accept. That covers links, devices, traversal, absolute and drive paths, backslashes, Windows device names and trailing dots, case collisions, duplicates, file and directory conflicts, entries outside a declared root, and bounds. One code per rule, in a fixed order. **Entry names are ASCII in this version.**
- **Read-only store, published and recorded together.** A tree is staged and verified, then published by a no-replace rename and recorded, all under one hold of the state lock. It is stored read-only at `store/extensions/packages/sha256/<tree digest>/`.
- **Launch and lifetime.** A host starts the entry point from the store by its absolute path, with a lease that lasts as long as the guest's process tree. On Windows the entry point ends in `.exe`, and every stored path fits the process and directory limits.
- **Removal.** Uninstall never deletes a package. An explicit collection deletes only packages that no lock names and no running process leases.
- **Trust is unchanged.** Integrity checks say which bytes were installed, not who published them.
- **Conformance data.** Language-neutral cases, as archive bytes, that the .NET and MoonBit hosts both run.
- **Toolchain follow-up.** The toolchain contracts make their provisional binding of the frontend's archive final, and say how a recipe, lock and receipt name a package. This is a task on those contracts, not an edit here.

**Versions.** The descriptor, index record, catalog and lock belong to the extension state family, which has one version carried by a required `$schema` URL (maintainer, Decision 15, 10 November 2026). They gain the `package` member at the package version. If the family's `0.1.0-preview.1` schemas are not yet published and no released host, publisher or tool reads or writes `0.1.0-preview.1` when this change is approved, `package` is part of `0.1.0-preview.1`, which finos/morphir#1149 also defines; otherwise the family moves to `0.1.0-preview.2`. Either way the published schemas under `website/static/schemas/extensions/` carry the member, and the tree manifest's header names the same version.

**Not breaking** for raw-executable artifacts. Process extensions that ship one executable inside an archive, such as morphir-elm today, must be published with a `package` member to be installed by a current host; #1149 already requires them to be published again.

**For the maintainer to confirm.** Starting packages from the shared store, with an explicit collection command, changes the existing rule of starting a private copy (Q-LAUNCH). What activation checks each time is open (Q-VERIFY).

## Capabilities

### New Capabilities

- `extensions/extension-packages`: what a package is, its digests and manifest, how archives are read, the unpacking rules and refusal codes, file modes, store layout, publication and recording, launch and lifetime, removal, trust and conformance.

### Modified Capabilities

None. The descriptor, record, catalog and lock are defined on design pages under `docs/design/draft/extensions/`, not in main specs. The capability above records the new behavior, and the tasks update those pages.

## Tracking

The owning issue is [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is not used for this proposal; the tasks name no Beads ids, and Beads issues are created when tracking is available.

## Impact

- **finos/morphir:**
  - the extension distribution design page, which defines the shared files;
  - a normative package rule page and its conformance data;
  - later, the toolchain contracts.
- **finos/morphir-dotnet:**
  - its installer (finos/morphir-dotnet#567) installs packages, keeping its ASCII name rule;
  - the F# frontend is published as a package (its adoption task 3.3).
- **MoonBit host:** adopts the rules and runs the cases in its own repository.
- **No Rust work:** the Rust CLI is to be deleted from finos/morphir (Decision 16, 10 November 2026), so this change plans no Rust reader or writer.
- **Depends on** finos/morphir#1149, whose family version, schemas and shared-file definitions this change extends, and on its review fixes (finos/morphir#1150) for the lock opening rules. The design names each dependency.

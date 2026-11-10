# Proposal

## Why

morphir-dotnet's F# guests identify themselves as `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend`. The version 2 extension release descriptor (`2.0.0-draft.2`) accepts only a single lowercase token as `extensionId`, and the descriptor id must equal the id in the guest's capability claims. So these guests cannot be published to an extension repository under their own names, and a toolset recipe cannot bind them. The MEP protocol page and the approved toolchain lock example already use dotted ids.

On 9 November 2026 the maintainer decided to allow dotted ids in the descriptor. The approved deployment change requires any extension to a released descriptor to be "a separately reviewed compatible addition or next-major draft". This change is that review: it settles the grammar, the versioning and the paths, and keeps every existing extension, store, lock and catalog working unchanged.

For example, after this change the frontend's `release.json` can say `"extensionId": "org.finos.morphir.fsharp-frontend"`, its claims can say the same, and a host installs it beside `morphir-elm`.

## What Changes

- **Grammar.** An extension id becomes one or more lowercase portable tokens joined by `.`, at most 238 characters, and its first segment is not a Windows device name. Every single-token id that is valid today stays valid and keeps its meaning. This is morphir-dotnet's rule plus the device-name refinement that upstream already applies to single tokens.
- **No new names for existing ids.** Ids keep mapping to repository, lock and catalog names by appending fixed suffixes. The content-addressed artifact store does not use the id. No existing file, layout or index key changes.
- **Dotted ids are kept apart from what older hosts read.** A Morphir home and a repository index are shared, and an older host reads some of their files whole. One unreadable entry there would stop it for every extension.
  - In a home, dotted extensions get their own installed catalog and their own lock directory, under the same state lock. The existing catalog and lock directory hold only single-segment ids.
  - In a repository, dotted histories get their own index directory.
  - So an older host keeps installing, updating, searching and running `morphir-elm` on a home or repository that also holds `org.finos.morphir.fsharp-frontend`; it simply does not see the dotted extension.
- **Equality.** The descriptor id, the claims id and the id an extension reports in a session stay byte-for-byte equal.
- **No trust from names.** A reverse-DNS style id is a naming convention. Nothing verifies domain ownership, and an id grants no trust, permission or precedence. Publisher authentication stays a separate mechanism.
- **Versioning.** The descriptor, repository index record and dotted installed catalog gain an exact draft, `2.0.0-draft.3`, that differs from `2.0.0-draft.2` only in the id grammar. A dotted extension's lock is at `2.0.0-draft.1`.
  - These versions appear only in documents and files that concern a dotted id, so every existing document stays byte-identical.
  - An older host meets none of them in a home or repository, because they sit in the separate files above. If an older host is handed a dotted release descriptor directly, it refuses it with its existing unsupported-version error. Existing hosts are not changed. The new readers also read every earlier version.
- **Configuration.** A dotted id in project configuration is a quoted TOML key, `[extensions."org.finos.morphir.fsharp-frontend"]`. An unquoted dotted key is refused with the quoted spelling in the message.
- **Conformance data.** Language-neutral cases for valid and invalid ids, device names, length boundaries, derived names that must not collide, equality, quoting and an old reader's refusal. Every host runs them.
- **Follow-up in the toolchain contracts.** Once this lands, the toolchain contracts align their identity grammar with this rule. The signed F# fixtures move to the dotted ids, and the open question on dotted provider identities closes.

No change is **BREAKING**: no valid document becomes invalid, and no existing path changes.

## Capabilities

### New Capabilities

- `extensions/extension-identity`: the grammar of an extension id, how it is compared, what it does and does not mean, the names derived from it, and the contract versions that carry a dotted id.

### Modified Capabilities

None. The descriptor and record formats are design drafts under `docs/design/draft/extensions/`, not main specs. This change records their new behavior in the capability above and updates those pages as part of its tasks.

## Tracking

The owning issue is [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked at the time of writing; the tasks name no Beads ids, and Beads issues are created when tracking is available.

## Impact

- **finos/morphir:**
  - the extension distribution and protocol design pages;
  - a normative extension id page and its conformance data;
  - the Rust CLI's configuration diagnostics;
  - a move of the `ecosystem/morphir-rust` pin;
  - later, the toolchain contracts and their signed fixtures.
- **finos/morphir-rust** (`morphir-distribution`, `morphir-common` home layout and configuration): the id grammar, the new drafts in readers and writers, the dotted home and repository partitions, configuration quoting, and tests over the shared cases.
- **MoonBit host:** the pinned `ecosystem/morphir-moonbit` holds no extension registry code. The host that reads extension ids adopts the rule in its own repository, and its pin moves only if that repository is a submodule here.
- **finos/morphir-dotnet:** already accepts dotted ids. It adopts the device-name refinement and runs the shared cases. Its task that waits on dotted descriptor ids then unblocks. Its installer (finos/morphir-dotnet#567), which plans to read and write the same home files as the Rust host byte for byte, writes dotted extensions into the dotted catalog and lock directory.
- **No change:** the MEP protocol versions and the capability claim set version. Both already carry the id as a string, and their equality rules stay.

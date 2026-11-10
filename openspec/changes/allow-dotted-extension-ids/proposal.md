# Proposal

## Why

morphir-dotnet's F# guests identify themselves as `org.finos.morphir.fsharp-frontend` and `org.finos.morphir.fsharp-backend`. The version 2 extension release descriptor (`2.0.0-draft.2`) accepts only a single lowercase token as `extensionId`, and the descriptor id must equal the id in the guest's capability claims. So these guests cannot be published to an extension repository under their own names, and a toolset recipe cannot bind them. The MEP protocol page and the approved toolchain lock example already use dotted ids.

On 9 November 2026 the maintainer decided to allow dotted ids in the descriptor. The approved deployment change requires any extension to a released descriptor to be "a separately reviewed compatible addition or next-major draft". This change is that review: it settles the grammar, the versions and the paths.

For example, after this change the frontend's `release.json` can say `"extensionId": "org.finos.morphir.fsharp-frontend"`, its claims can say the same, and a host installs it beside `morphir-elm`.

The same day the maintainer made three decisions that shape this change:

- the Rust CLI is legacy, and work goes to the morphir-dotnet and morphir-moonbit hosts first;
- transient pre-1.0 document formats are not read or converted, so readers take the current exact drafts only;
- one installed catalog is chosen over a separate partition for dotted ids.

## What Changes

- **Grammar.** An extension id becomes one or more lowercase portable tokens joined by `.`, at most 238 characters, and its first segment is not a Windows device name. Every single-token id that is valid today stays valid and keeps its meaning. This is morphir-dotnet's rule plus the device-name refinement that upstream already applies to single tokens.
- **One catalog, one lock directory, one history directory.** Ids keep mapping to repository, lock and catalog names by appending fixed suffixes. A dotted id lives in the same `catalog/extensions.json`, `locks/extensions/` and repository `extensions/` as a single-segment one. The content-addressed artifact store does not use the id.
- **Equality.** The descriptor id, the claims id and the id an extension reports in a session stay byte-for-byte equal.
- **No trust from names.** A reverse-DNS style id is a naming convention. Nothing verifies domain ownership, and an id grants no trust, permission or precedence. Publisher authentication stays a separate mechanism.
- **Versioning.** The descriptor, the repository index record and the installed catalog move to a new exact draft, `2.0.0-draft.3`. It differs from `2.0.0-draft.2` only in the id grammar. The extension lock moves to `2.0.0-draft.1`, which differs from `"1.0"` only in the id grammar.
  - Writers write the new drafts for every id.
  - Readers read the new drafts and need not read earlier ones.
  - No conversion between versions is part of the contract.
- **Older hosts are not protected.** A host that reads only the earlier versions refuses every document a current writer produces, with its existing unsupported-version error. That includes the released Rust CLI. Once a current host has written a home's catalog, every extension command of an older CLI in that home is refused. The maintainer accepted this cost: "we don't have users to support the cost of maintaining 2 versions". A user who needs an older CLI again gives it its own Morphir home (`MORPHIR_HOME`) and installs its extensions there.
- **The contract pages define the shared files.** Two installers that share a home must agree on the catalog, lock, transaction journal and index record. The extension design pages define their members and values. Today that definition lives in the Rust source.
- **Configuration.** A dotted id in project configuration is a quoted TOML key, `[extensions."org.finos.morphir.fsharp-frontend"]`. An unquoted dotted key is refused with the quoted spelling in the message.
- **Conformance data.** Language-neutral cases for:
  - valid and invalid ids, device names and length boundaries;
  - derived names that must not collide;
  - equality;
  - the version rules;
  - quoting.

  Every host runs them.
- **Follow-up in the toolchain contracts.** Once the .NET guests are published under their dotted ids, the toolchain contracts align their identity grammar with this rule. The signed F# fixtures move to the dotted ids, and the open question on dotted provider identities closes.

**BREAKING** for hosts that predate this change: they cannot read a home or repository after a current writer has written it. No valid id becomes invalid.

## Capabilities

### New Capabilities

- `extensions/extension-identity`: the grammar of an extension id, how it is compared, what it does and does not mean, the names derived from it, and the contract versions that carry the new grammar.

### Modified Capabilities

None. The descriptor and record formats are design drafts under `docs/design/draft/extensions/`, not main specs. This change records their new behavior in the capability above and updates those pages as part of its tasks.

## Tracking

The owning issue is [finos/morphir#1146](https://github.com/finos/morphir/issues/1146). Beads tracking is blocked at the time of writing; the tasks name no Beads ids, and Beads issues are created when tracking is available.

## Impact

- **finos/morphir:**
  - the extension distribution and protocol design pages, which now define the shared files' members and values;
  - a normative extension id page and its conformance data;
  - later, the toolchain contracts and their signed fixtures.
- **finos/morphir-dotnet:** its registry already accepts dotted ids. It adopts the device-name refinement and runs the shared cases.
  - Its installer (finos/morphir-dotnet#567) writes the one catalog, the lock and the journal at the new drafts, with the members and values the design pages define.
  - Its task that waits on dotted descriptor ids then unblocks.
- **MoonBit host:** the pinned `ecosystem/morphir-moonbit` holds no extension registry code. The host that reads extension ids adopts the rule in its own repository, and its pin moves only if that repository is a submodule here.
- **Optional later work, gating nothing:** finos/morphir-rust (`morphir-distribution`, `morphir-common`) and the Rust CLI would need the grammar, the new drafts and configuration quoting to read homes and repositories that current hosts write. No `ecosystem/morphir-rust` pin move is planned.
- **No change:** the MEP protocol versions and the capability claim set version. Both already carry the id as a string, and their equality rules stay.

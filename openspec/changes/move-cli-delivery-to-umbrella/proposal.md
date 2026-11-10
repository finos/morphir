# Proposal

## Why

finos/morphir builds and releases a Rust `morphir` CLI, but the Morphir CLI is the .NET one from finos/morphir-dotnet. A user who downloads the latest finos/morphir release, or a contributor who reads `crates/morphir`, meets the wrong product. The maintainer decided on 10 November 2026 (Decision 16, modified as 16A, on [#1146](https://github.com/finos/morphir/issues/1146)) to delete the Rust CLI and to make this repository the place that builds, qualifies and releases the .NET CLI.

## What Changes

A maintainer pushes the tag `cli/v0.4.0-alpha.4`. The release workflow checks that `ecosystem/morphir-dotnet` is pinned at the recorded commit and that the pinned CHANGELOG releases `0.4.0-alpha.4`, runs that source's own reusable build workflow at that commit for each offering and platform, launches each produced executable, apphost and tool package as a user would, and publishes one release whose manifest names the source commit, the kit digest and every artifact digest.

```text
cli/v<version> tag -> verify pin + CHANGELOG -> source's cli-offering.yml (PackRelease) x 19
  -> launch each artifact (morphir, apphost, dotnet-morphir, dotnet morphir)
  -> manifest(source, kit, artifacts, qualification) -> new release, never replaced
```

- Pin finos/morphir-dotnet as `ecosystem/morphir-dotnet`. The first pin was `7c263485547598085ea83d7d12bf6328056affba` (its `main`, with #574). To wire the source's reusable `cli-offering.yml`, the pin is now the head of draft, unmerged finos/morphir-dotnet#590, `8c15df59ce902c3ec06bb2df0c8ab4a88445a39d`, marked as a candidate: the release builds and qualifies from it but refuses to publish. The final pin follows #590's merge. The CLI source stays in that repository.
- **BREAKING** Delete the Rust product CLI (`crates/morphir`) and the crates only it used: `integration-tests`, `morphir-decoration`, `morphir-evaluator`, `morphir-opa`. Delete its generated reference (`docs/cli`, the man page, shell completions).
- **BREAKING** Replace the Rust CLI release jobs. Official CLI releases use `cli/v*` tags (proposed for review; see design REL-1) and the four .NET offerings: Native AOT, self-contained managed and framework-dependent `morphir`, and the `Morphir.Tool` package with `dotnet-morphir` and `dotnet morphir`. Existing `v*` releases and tags are left as they are.
- Move the shared MCK command tree to the standalone, development-only program `morphir-mck` (`crates/morphir-mck-cli`) with the same commands, adapters, expectations and exit codes. The .NET CLI's `morphir mck ARGS` delegates to it.
- Move `kb` and the library-level repository gates (MEP contract IR, tool release metadata, package runtime vectors) to the internal development tool `morphir-dev` (`crates/morphir-dev-tools`), which is never released.
- Retire, by name, the gates that tested the deleted CLI's own behavior, and say where each one goes.
- Update the ownership statements in `AGENTS.md`, `ecosystem/AGENTS.md`, the installation guide and the `add-deployment-and-acquisition` change.

## Capabilities

### New Capabilities

- `cli/official-delivery`: how finos/morphir pins the CLI source, builds the four offerings from it, qualifies the produced artifacts and publishes a release.
- `mck/standalone-runner`: the `morphir-mck` program, its command contract and how the Morphir CLI delegates to it.
- `repository/development-tools`: the internal development tool and how every former CLI gate is either kept or retired by name.

### Modified Capabilities

None. `openspec/specs/` holds only the MEP generic guest profile, which this change does not alter. The unarchived `remove-rust-cli-gleam-provider` change describes providers of the deleted CLI; it is left for its owner to withdraw or archive.

## Tracking

- GitHub: [#1153](https://github.com/finos/morphir/issues/1153) (this implementation) and [#1146](https://github.com/finos/morphir/issues/1146) (Decisions 13, 15 and 16).
- Beads: none. A task create attempt rolled back on the existing shared Dolt merge conflict, so no bead exists and none is cited. #1153 is the record until the tracker is writable. Do not run `bd dolt push` on Windows.
- Depends on the unmerged acquisition contracts of [#1147](https://github.com/finos/morphir/pull/1147) (`crates/morphir-toolchain-contract`) and is stacked on that branch.
- The Contract Versioning block of `AGENTS.md` belongs to [#1152](https://github.com/finos/morphir/pull/1152) and is not edited here.

## Impact

- Code: `crates/morphir`, `crates/integration-tests`, `crates/morphir-decoration`, `crates/morphir-evaluator` and `crates/morphir-opa` are removed; `crates/morphir-mck-cli` and `crates/morphir-dev-tools` are added. `Cargo.lock` drops 337 packages, among them `regorus`, so building no longer needs the MSVC Spectre libraries ([#886](https://github.com/finos/morphir/issues/886)).
- CI: `morphir-cli-test`, `library-publish-macos` and `check-cli-docs` are replaced by `rust-dev-tools`; `release.yml` is rewritten; `.github/scripts/select_release_assets.py` goes.
- Tasks: the MCK and package tasks call `morphir-mck`; `test:examples` and `migrate:validate` stop with a pointer; `test:itest`, `test:host-compatibility`, `docs:cli`, `vendor:morphir-web` and the YAML/tree fixture generators go.
- Users of the Rust CLI install the .NET CLI instead. The last Rust release, `v0.4.0-beta.12`, stays downloadable.
- `ecosystem/morphir-rust` stays: `morphir-mck` and `morphir-dev` still build on its crates.

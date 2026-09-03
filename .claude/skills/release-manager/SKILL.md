---
name: release-manager
description: Assists with Morphir CLI release management for finos/morphir, including pre-release verification, extension verification, version bumps, tagging, and release coordination. Use when preparing releases, checking release readiness, or managing version bumps.
user-invocable: true
---

# Release Manager Skill

You are a release management assistant for the Morphir CLI released from
**finos/morphir**. The release is the Rust `morphir` binary built from
`crates/morphir`. Go tooling is released from finos/morphir-go and is out of
scope here.

## Release policy

- One workspace version lives in the root `Cargo.toml` under
  `[workspace.package]`. Every crate inherits it. Never set a crate version by
  hand.
- The release tag is `v<version>`, for example `v0.4.0-alpha.6`. The release
  workflow refuses a tag that does not match the workspace version.
- Alpha versions use the `MAJOR.MINOR.PATCH-alpha.N` spelling. Bump only `N`
  for another alpha of the same target version.
- Tags point at a commit on `main`. The version bump lands through a pull
  request from a `release/v<version>` branch. Tag the merge commit, not the
  branch tip.
- Any tag with a `-` in it publishes as a GitHub prerelease. The workflow sets
  this flag itself.
- Do not add AI co-authors or AI attribution to the release commit, pull
  request, or release notes. This breaks EasyCLA.

## Files that carry the version

| File | What to change |
|------|----------------|
| `Cargo.toml` | `[workspace.package] version` |
| `Cargo.lock` | Regenerate with `cargo update --workspace --offline` after the bump |
| `tests/ci/test_release_workflow.py` | The expected version strings in `test_workspace_uses_release_prerelease_version` |
| `.github/workflows/release.yml` | The example tag in the `workflow_dispatch` input description |
| `INSTALLING.md` | The `mise use -g github:finos/morphir@<version>` example and the pinned `mise.toml` snippet |
| `docs/getting-started/morphir-cli.md` | The same two mise install examples |
| `CHANGELOG.md` | Move `[Unreleased]` into a `[<version>] - <date>` section and add a fresh empty `[Unreleased]` |
| `docs/cli/`, `docs/man/`, `completions/` | Generated. Run `mise run docs:cli` after the release build and commit the result; CI fails on drift |

Check for other references before the bump:

```bash
git grep -n "$(python3 -c 'import pathlib,tomllib;print(tomllib.loads(pathlib.Path("Cargo.toml").read_text())["workspace"]["package"]["version"])')" -- ':!Cargo.lock' ':!CHANGELOG.md'
```

## Pre-release verification

Run every gate from a clean checkout of `main` with the submodules populated.
`ecosystem/morphir-rust` must be present because the CLI has path dependencies
into it. Confirm its pinned commit is on `morphir-rust` `main`, not on a pull
request branch:

```bash
git -C ecosystem/morphir-rust fetch origin main
git -C ecosystem/morphir-rust branch -r --contains "$(git -C ecosystem/morphir-rust rev-parse HEAD)"
```

### Automated checks

These are the gates CI enforces. Run them locally in this order:

```bash
# Formatting and Clippy
mise run fmt-check:rust
mise run lint:rust

# Rust unit and integration tests. CI gates on the morphir and
# integration-tests packages; `mise run test` also runs the pinned
# ecosystem/morphir-rust crates.
cargo test --locked --package morphir
mise run test

# Release workflow and CI helper tests (Python)
python3 -B -m unittest discover -s tests/ci

# Documentation, tool metadata, schema, and naming-corpus checks
mise run ci:validate-docs
mise run ci:validate-tool-release-metadata
mise run schema:validate
mise run fixtures:naming-corpus-check

# Release binary
cargo build --locked --release --package morphir
target/release/morphir --version
```

On macOS, four `morphir-common` tests in `cache_maintenance_inventory` fail
because APFS is case-insensitive. They pass on Linux CI and are not a release
blocker.

`mise run check` is not a usable gate today. It depends on `examples:validate`
and `fixtures:validate`, which no longer exist, and on `lint:schema`, which
reports several hundred style findings that CI does not enforce. Use the
individual tasks above until `check` is repaired.

CI also runs `mise run docs:cli` and fails if the generated CLI docs drift.
Run it locally when a command's help text changed and commit the result.

### Extension verification

The CLI ships with no extensions. Extensions install from repositories at run
time, so the release must prove the installed-extension paths still work.

**Process extensions (Elm, Scala).** CI builds the Morphir Elm extension and
the Morphir Scala Elm extension and runs the `elm_extension` and
`cli_integration` ignored tests against them. A green CI run on the release
commit covers these. To run the Elm path locally:

```bash
mise -C ecosystem/morphir-elm run build:mep-extension
MORPHIR_ELM_EXTENSION_BIN="$PWD/ecosystem/morphir-elm/dist/morphir-elm-extension/morphir-elm-extension" \
  cargo test --locked --package integration-tests --test elm_extension -- --ignored --nocapture
```

**WASM extensions (Avro, OpenAPI).** CI builds the Avro and OpenAPI guests
from `ecosystem/morphir-rust` and runs the ignored `generate_extension` and
`generate_openapi_extension` tests against them. To run them locally:

```bash
rustup target add wasm32-unknown-unknown
cargo build --locked --release --manifest-path ecosystem/morphir-rust/Cargo.toml \
  -p morphir-avro-extension -p morphir-openapi-extension --target wasm32-unknown-unknown
cargo test --locked -p morphir --test generate_extension --test generate_openapi_extension -- --ignored
```

Then prove the published bundles against the release binary in a clean home.
Published bundles come from finos/morphir-rust releases tagged
`extension/<short-id>/v<version>`. The publish command requires the descriptor
to be named `release.json` and the bundle directory to hold exactly the
descriptor, the `.wasm` artifact, and its `.sha256` file:

```bash
export MORPHIR_HOME="$(mktemp -d)"
bin=target/release/morphir
mkdir -p bundles/avro && gh release download extension/avro/v0.1.1 -R finos/morphir-rust --dir bundles/avro
mv bundles/avro/*.release.json bundles/avro/release.json

$bin extension repository init repo
$bin extension repository add local --directory repo
$bin extension repository publish local --bundle bundles/avro
$bin extension search avro
$bin extension install --repository local morphir-avro
$bin extension list
$bin generate --target avro --input website/static/ir/examples/v3/greeting-example.json --output out/avro
```

Repeat the same steps for `extension/openapi/v<version>` with
`morphir-openapi` and the `openapi` and `json-schema` targets. Every command
must succeed and the generate step must write artifacts.

### Manual verification

- [ ] `CHANGELOG.md` has a section for this version with every user-visible
      change since the previous tag. Breaking changes are marked and describe
      the migration.
- [ ] Version references listed above all agree.
- [ ] CI on `main` is green for the commit you will tag.
- [ ] Open dependency pull requests that touch `Cargo.lock` are either merged
      or deliberately left out.
- [ ] The docs site builds if docs changed: `cd website && npm ci && npm run build`.

## Release workflow

### 1. Prepare the release branch

```bash
git switch main && git pull --ff-only
git submodule update --init --recursive
git switch -c release/v<version>
```

Update every file in the version table. Then:

```bash
cargo update --workspace --offline
# run every gate from "Automated checks" and "Extension verification"
git commit -am "chore: prepare v<version> release"
git push -u origin release/v<version>
gh pr create --title "chore: prepare v<version> release" --body "<summary and verification>"
```

### 2. Merge and tag

Wait for CI on the pull request to pass, then merge. Merge on green CI.
Bot reviews land after the checks and are advisory.

```bash
git switch main && git pull --ff-only
git tag -a v<version> -m "Release v<version>"
git push origin v<version>
```

Pushing the tag starts `.github/workflows/release.yml`. It validates the tag
against the workspace version, builds the CLI for six targets, packages
`.tgz` and `.zip` archives with `.sha256` files, and creates the GitHub
release with generated notes. Re-running the workflow only uploads assets
whose hash changed.

If the tag already exists and the workflow needs to run again:

```bash
gh workflow run release.yml -f tag=v<version>
```

### 3. Post-release

- [ ] `gh release view v<version>` shows twelve CLI assets (six archives with
      checksums) and the prerelease flag for alpha versions.
- [ ] Install the published build on one machine and run
      `morphir --version`:
      `mise use -g github:finos/morphir@<version>` or `cargo binstall morphir`.
- [ ] Repeat the WASM extension steps above against the installed binary.
- [ ] Close the release bead with `bd close`.

## Troubleshooting

### Release tag does not match workspace version

The `release-info` job exits with that message when `Cargo.toml` at the tag
does not carry the tagged version. Delete the tag, fix the version on `main`
through a pull request, and tag again.

### Cargo reports a stale lockfile

`--locked` builds fail after a version bump until `Cargo.lock` is regenerated.
Run `cargo update --workspace --offline` and commit the lockfile.

### Path dependency into ecosystem/morphir-rust is missing

The submodule is empty. Run `git submodule update --init --recursive`. In a git
worktree, also run `git -C ecosystem/morphir-rust reset --hard HEAD` if the
index is empty after the update.

### Extension publish rejects the bundle

`release bundle has no release.json` means the descriptor still has its
download name. `release bundle files do not match release.json` means an extra
file sits in the bundle directory. Keep only the three expected files.

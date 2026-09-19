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
- Prerelease versions use the `MAJOR.MINOR.PATCH-<stage>.N` spelling, for
  example `0.4.0-alpha.6` or `0.4.0-rc.1`. Bump only `N` for another
  prerelease of the same stage and target version. Change the stage when the
  release moves from alpha to beta or to a release candidate.
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

Run the aggregate first, then the gates CI enforces:

```bash
# Formatting, Clippy, schema lint, example validation, naming corpus,
# and metaschema validation
mise run check

# Formatting and Clippy on their own
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
mise run ci:validate-tool-release-metadata
mise run schema:validate
mise run fixtures:naming-corpus-check

# Release binary
cargo build --locked --release --package morphir
target/release/morphir --version
```

`lint:schema` excludes the rules the schemas do not satisfy yet; the list is
in `.config/mise/config.toml`. `fixtures:validate` is not part of `check`
because it needs `mise run fixtures:fetch` first. Four `morphir-common`
cache-inventory tests are ignored on macOS because APFS is case-insensitive;
Linux CI runs them.

CI also runs `mise run docs:cli` and fails if the generated CLI docs drift.
Run it locally when a command's help text changed and commit the result.

### Extension verification

The CLI ships with no extensions. Extensions install from repositories at run
time, so the release must prove the installed-extension paths still work.

**Process extensions (Elm, Scala).** CI downloads the Morphir Elm extension
that finos/morphir-elm releases on its own tag, `extension/elm/v<version>`, from
the `vnext` branch. The pin is `[executables.elm]` in
`.config/published-extension-bundles.toml` (repository, tag, archive and the
archive's `sha256`), for the `x86_64-unknown-linux-gnu` archive that CI runs.
CI also downloads the Morphir Scala Elm provider, `morphir-scala-elm`, which
finos/morphir-scala releases with its root `v*` release as a raw executable.
Its pin is `[executables.scala-elm]` with an `asset` in place of an `archive`,
and its version equals the morphir-scala release version. CI runs the
`elm_extension` and `cli_integration` ignored tests against both. A green CI
run on the release commit covers these.

`mise run ci:fetch-published-bundles` unpacks the pinned Linux executable. To
run the Elm path on another platform, download the archive for that platform
from the same release:

```bash
gh release download extension/elm/v0.1.0 -R finos/morphir-elm \
  --pattern "*aarch64-apple-darwin.tgz" --dir /tmp/elm-ext
tar -xzf /tmp/elm-ext/*.tgz -C /tmp/elm-ext
export MORPHIR_ELM_EXTENSION_BIN=/tmp/elm-ext/morphir-elm-extension
# The version of the pinned release. The CLI refuses an extension that reports another one.
export MORPHIR_ELM_EXTENSION_VERSION=0.1.0
cargo test --locked --package integration-tests --test elm_extension -- --ignored --nocapture
cargo test --locked --package morphir --test cli_integration \
  real_installed_morphir_elm_is_verified_and_activates_offline -- --ignored --nocapture
```

The Scala provider test takes its executable and version the same way:

```bash
gh release download v0.5.0-M06 -R finos/morphir-scala \
  --pattern "morphir-scala-elm-mac-aarch64-0.5.0-M06" --dir /tmp/scala-elm
chmod +x /tmp/scala-elm/morphir-scala-elm-mac-aarch64-0.5.0-M06
export MORPHIR_SCALA_ELM_EXTENSION_BIN=/tmp/scala-elm/morphir-scala-elm-mac-aarch64-0.5.0-M06
export MORPHIR_SCALA_ELM_EXTENSION_VERSION=0.5.0-M06
cargo test --locked --package morphir --test cli_integration \
  real_installed_morphir_scala_elm_is_selected_and_activates_offline -- --ignored --exact --nocapture
```

Before a release, check finos/morphir-elm for a newer `extension/elm/v*` tag and
finos/morphir-scala for a newer `v*` release, and move the pins.

**WASM extensions (Avro, OpenAPI, Python, Rust).** finos/morphir does not build
the guests. finos/morphir-rust owns the check that a new bundle works with the
released CLI. This repository owns the check that a CLI change does not break the
bundles users already installed: CI downloads the bundles pinned in
`.config/published-extension-bundles.toml` and runs the ignored extension tests
against them. Run the same check with the release binary:

```bash
mise run ci:fetch-published-bundles
B="$PWD/.dev/out/published-bundles"
MORPHIR_AVRO_GUEST="$(ls "$B"/avro/*.wasm)" MORPHIR_OPENAPI_GUEST="$(ls "$B"/openapi/*.wasm)" \
MORPHIR_PYTHON_BUNDLE="$B/python" MORPHIR_RUST_BUNDLE="$B/rust" \
  cargo test --locked --release -p morphir \
    --test generate_extension --test generate_openapi_extension \
    --test python_extension --test rust_extension -- --ignored
```

Before a release, check finos/morphir-rust releases for newer `extension/<id>/v*`
tags and move the pins. When the CLI changes the extension protocol on purpose,
publish a compatible bundle from finos/morphir-rust first, then move the pin in
the same pull request as the CLI change.

Then prove one bundle by hand in a clean home. `generate` needs a project
configuration, so the steps run inside a directory with a `morphir.toml`:

```bash
export MORPHIR_HOME="$(mktemp -d)"
bin="$PWD/target/release/morphir"
ir="$PWD/website/static/ir/examples/v3/greeting-example.json"
work="$(mktemp -d)" && cd "$work"
printf '[project]\nname = "Acme.Greeting"\nversion = "1.0.0"\n' > morphir.toml

$bin extension repository init repo
$bin extension repository add local --directory repo
$bin extension repository publish local --bundle "$B/avro"
$bin extension search avro
$bin extension install --repository local morphir-avro
$bin extension list
$bin generate --target avro --input "$ir" --output out/avro
```

Every command must succeed and the generate step must write artifacts.

**Native Elm provider.** `morphir-elm-native` is compiled into the CLI. Prove it
with a project whose `morphir.toml` sets `[frontend] language = "elm"` and
`[frontend.elm] extension = "morphir-elm-native"`: `morphir compile --ir-version 3`
and `--ir-version 4` must both write `morphir-ir.json` with that `formatVersion`.

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

# Signed two-Library review fixture

This draft.3 signed fixture passed user review on 2026-09-17. It is not an executable
package client, an MCK compatibility result, or production trust material. The review
gate is complete; shared MCK and package runtime implementation may proceed.

The published root is `example.com/finance/loan-rules` version `1.0.0`. Its provider is
`example.com/finance/eligibility` version `1.2.0`. Their IR names remain
`example/loan-rules` and `example/eligibility`; the consumer reference remains
`example/eligibility:decision#default-decision`. Package versions remain outside the IR.

## What to review

- [morphir.lock](morphir.lock) binds the unchanged graph to exact record and evidence bytes.
- [trust-policy.json](trust-policy.json) separately authorizes the repository and publishers.
- [registry](registry/) contains both original bundles, four authenticated targets, and
  the four TUF roles. The numbered timestamp and current timestamp are byte-identical.
- [configuration-one.json](configuration-one.json), [view-one.json](view-one.json), and
  [empty-cache.json](empty-cache.json) are complete MCK setup inputs, not protected-state exports.
- [fixture-description.json](fixture-description.json) records input hashes and public keys.
- [Fixed first-restore observations](../../expected/observations-wire-valid-two-node.json)
  specify the expected future client state. They are not an observed runtime result.

The original [two-Library source files](../../../two-libraries/) are unchanged. The bundle
copies retain their exact manifest and IR bytes. Canonical manifest and content digests
also remain unchanged. Registry records use canonical Morphir metadata plus exactly one
LF; the signed statement payloads use canonical metadata without a final LF. TUF and DSSE
file hashes cover the complete stored files, not reserialized objects.

## Public test keys and fixed time

Never trust these keys for real packages. Every seed is public and reproducible as the
SHA-256 of UTF-8 `morphir-mck-fixture:<label>`. Labels are `root`, `timestamp`, `snapshot`,
`targets`, `publisher-a`, and `publisher-b`. All six keys differ. Both publishers sign each
statement; the fixture policy requires one of them. Repository signatures do not grant
publisher authority.

The clock is fixed at `2027-01-01T00:00:00Z`. All metadata versions are 1. Root expires
`2030-01-01T00:00:00Z`, snapshot and targets expire `2028-01-01T00:00:00Z`, and timestamp
expires `2027-02-01T00:00:00Z`. Verification at the timestamp expiry instant must fail.
Do not renew these files based on the wall clock. Expired historical evidence is not fresh
authorization, and copying this directory creates no continued-use grant.

The repository identity is
`sha256:aec72527f7dd06a472f1aab6a703500ff697db37b31a52ef80519b97b60c8be6`.
It hashes the original root's TUF-canonical signed body. The separate bootstrap file pin is
`sha256:655cacea8dc5a51e17a82f0c6c9065fadeef995edde1414bb93980b8f68b8c8a`.
Fixture configuration supplies these out of band; the lock supplies neither authority.

## Reproduce and verify

Use [TypeScript PR #21](https://github.com/finos/morphir-typescript/pull/21), commit
`7a99f3810c6ea8ad35f6bfe8ae90e5a1439218ab`, in a `finos/morphir-typescript` checkout.
The parent submodule pin has not yet advanced to that change. No checker is duplicated here.

The pinned toolchain is Bun 1.4.2 and Node 20.20.2. MCK's test-only dependencies are
`@noble/curves` 2.4.0, `@tufjs/canonical-json` 2.0.0, and `tuf-js` 5.0.1. The adopted
wire protocols are TUF 1.0.36 and DSSE 1.0.2, as pinned by the
[trust profile](../../../../../package-trust-profile.md).

From the TypeScript checkout, set the parent checkout explicitly:

```sh
export MORPHIR_FIXTURE_SOURCE=/absolute/path/to/finos/morphir
export MISE_OVERRIDE_CONFIG_FILENAMES=mise.toml
export MISE_ACTIVATE_AGGRESSIVE=1
mise run setup
mise exec -- bun packages/mck/test/support/package-signed-fixture-cli.ts \
  --source "$MORPHIR_FIXTURE_SOURCE" \
  --check "$MORPHIR_FIXTURE_SOURCE/spec/package/mck/fixtures/local-registry/assets/signed"
mise exec -- bun packages/mck/test/support/package-signed-fixture-integration.ts \
  --source "$MORPHIR_FIXTURE_SOURCE" \
  --fixture "$MORPHIR_FIXTURE_SOURCE/spec/package/mck/fixtures/local-registry/assets/signed"
mise run ci
```

The mise overrides prevent the enclosing ecosystem checkout from selecting its own tasks
or Homebrew executables in a nested worktree. To regenerate without replacing any files:

```sh
mkdir -p .dev/out
fixture_output="$(mktemp -d .dev/out/signed-fixture.XXXXXX)"
mise exec -- bun packages/mck/test/support/package-signed-fixture-cli.ts \
  --source "$MORPHIR_FIXTURE_SOURCE" --output "$fixture_output"
```

Generation accepts only the pinned source bytes and an absent or empty output directory.
It does not read developer keys, update trust stores, or overwrite existing fixtures.
The byte check compares every generated file and rejects unexpected files except this
handwritten README. The explicit integration command fails if the parent corpus is absent;
standalone TypeScript unit tests use their own small test inputs.

Node-compatible crypto APIs sign the fixture; Noble independently verifies Ed25519.
The pinned `tuf-js` trusted metadata store verifies root signatures, role signatures,
expiry, linked versions, hashes, lengths, and all four targets offline. Its deep import is
confined to test support. Separate assertions check Morphir-specific fields because a
successful upstream TUF check does not certify the entire Morphir profile.

## Fixed expectations and remaining work

The first-restore expectation follows the approved `local-registry.wire.valid-two-node`
scenario: both verified grants at the fixed time, role floors 1, no revocations or recovery
marker, unchanged registry and lock, both promoted bundles, and an empty destination.
Both publisher keys are retained as verified keys even though the threshold is one.
The graph is root-first; grants are sorted by PackagePath. File lengths and hashes describe
the exact fixture inputs. No resolver or package operation produced these expected results.

Expected observations live outside this generated directory and must be reviewed rather
than regenerated from a testee. Six base assets are bound; 121 remain pending. All 54 case
definitions retain `candidate-definitions` status. The new local-registry executor is
still absent, so no case is reported as a compatibility pass.

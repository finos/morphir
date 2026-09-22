# Test-only rust-tuf compatibility patch

This directory contains the published `tuf 0.3.0-beta14` crate with one narrowly
scoped compatibility patch. Morphir uses it only from parent MCK test and fixture
authoring support. It is not a production registry client.

Upstream: https://github.com/theupdateframework/rust-tuf

Archive: https://static.crates.io/crates/tuf/tuf-0.3.0-beta14.crate

Archive SHA-256: `52690b52ac55d07c9e2448be7589b7f17f35e09ec24aa5f15127577699484059`

Published VCS revision: `8e60df7e6adc95cffe4b4bc9a913b924dc82d860`, directory `tuf`.
The original `.cargo_vcs_info.json`, normalized manifest, original manifest,
lockfile, sources, tests and both upstream licenses are preserved.
`UPSTREAM-SHA256SUMS` records every original archive file before patching.
The private-key-shaped files in `tests/ed25519/` are upstream public test vectors.

## Patch and scope

`morphir-spec-version.patch` adds the literal `1.0.36` to
`src/pouf/pouf1/shims.rs::valid_spec_version` and its acceptance regression.
Unmodified upstream accepts only `1.0` and `1.0.0`, rejecting Morphir's frozen
metadata before verification. The parent profile continues to require exactly
`1.0.36` and rejects `1.0.35`. Other upstream version-rejection tests are unchanged.

[TUF section 4.3](https://theupdateframework.github.io/specification/latest/#file-formats-root-json)
lets adopters define matching specification versions. This patch changes only
that matching rule. It does not rewrite signed input, canonicalization, hashes,
lengths, role signatures, metadata versions, expiry, or clock behavior. It does
not claim complete TUF 1.0.36 conformance or authorize a production client.

The parent verifier uses the upstream `Client`, in-memory `EphemeralRepository`,
and explicit update/fetch times. Default HTTP features are disabled. The
upstream client verifies role signatures, versions and expiry, while its download
readers verify original metadata/target hashes and upper length bounds. The
parent fixture verifier compares complete supplied bytes against lengths from
upstream-authenticated descriptions to preserve the original exact-length gate. The fixture author
uses ed25519-dalek, and its independent DSSE verifier uses ring.

## Maintenance and removal

The MCK maintainers own this patch. Do not edit other upstream files to silence
lint warnings or implement Morphir behavior. An upstream release that accepts
`1.0.36` can replace this directory after the unchanged frozen fixture and all
negative tests pass. Remove the root `[patch.crates-io]` entry and workspace
exclude entry together with this directory, update the exact dev-dependency pin,
and regenerate Cargo.lock. Preserve fixture bytes and historical provenance.

Verification from the parent checkout:

```sh
cargo test --locked -p morphir-mck --test package_fixture
cargo run --locked -p morphir-mck --example package_fixture -- --source . --check spec/package/mck/fixtures/local-registry/assets/signed
cargo tree --locked -p morphir-mck --edges normal --target all
cargo tree --locked -p morphir --edges normal --target all
```

The normal dependency trees must contain no `tuf` dependency. The fixture suite
also checks this boundary using Cargo's normal dependency graph and
checks vendor files against the pinned upstream manifest and reviewed patch.

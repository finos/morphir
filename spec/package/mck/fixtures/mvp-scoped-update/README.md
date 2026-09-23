# Fresh scoped update MVP fixture

This sibling corpus leaves the historical draft.2/draft.3 and first-restore fixtures unchanged. It covers the `local-library-mvp:0.1.0-draft.1` prerelease profile through the real CLI. `tests/support/package_update.rs` only copies and mutates isolated inputs; it does not resolve packages or execute a compatibility runner.

The old graph is `loan-rules@1.0.0 -> eligibility@1.2.0 -> child@1.0.0`, with a separate `loan-rules -> sibling@1.0.0` edge. The root remains fixed. Updating eligibility selects 1.3.0, whose minimum child requirement forces child to 1.1.0. Sibling 1.1.0 is advertised but remains pinned to 1.0.0 because it lies outside eligibility's old closure. Exact eligibility 1.2.0 preserves child 1.0.0. Reordered multiple targets select the same frozen full lock.

The old lock refers to signed metadata version 1, expired in 2020. Fresh metadata version 2 authenticates unchanged immutable records for every old node. This distinguishes fresh authorization from historical evidence replay. New selection excludes the advertised yanked eligibility 1.9.0. Separate signed views yank the frozen sibling or root, revoke the sibling, or expose eligibility 1.4.0 requiring sibling 2.0.0. An exact request for 1.4.0 requires a change outside the old closure and must report a scope conflict.

`package_update_fixture.rs` authors the signed inputs and the explicit fixed graph choices using the existing public-seed Ed25519 signer. It never links a package implementation or captures its output. The tests independently authenticate each current view using upstream rust-tuf and both publisher signatures using ring, then verify content digests, exact acquisition pins, metadata links, lock normalization, IR schemas and dependency associations. Expiry is independently signed; bad signatures and damaged content are isolated controller mutations.

The frozen refusal labels retain existing resolver enum names and existing MVP diagnostic phrases. `exitCode` distinguishes malformed CLI requests from runtime refusals. Every success compares the complete lock. Every failure must preserve the input lock and leave the new output absent or preserve its existing sentinel. State corruption happens only after explicit initialization.

Reproduce without overwriting reviewed files:

```sh
mise exec -- cargo run -p morphir-mck --example package_update_fixture -- \
  --source . --check spec/package/mck/fixtures/mvp-scoped-update/signed
mise exec -- cargo test -p morphir-mck --test package_update_fixture
mise exec -- cargo test -p morphir --test package_update
```

Signing keys derive from deterministic public test seeds. They provide test provenance only and must never authorize a real registry.

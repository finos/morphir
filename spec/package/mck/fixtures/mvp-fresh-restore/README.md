# Metadata refresh, resolution and exact-lock restore MVP fixture

This fixture supplies the first executable CLI slice of the
`local-library-mvp:0.1.0-draft.1` prerelease profile. The separate
[case descriptor](cases.json) freezes outcomes before execution. It does not claim
the full MVP milestone, the production recovery profile, or the 296-obligation
portable inventory has passed.

The separate [resolve descriptor](resolve-cases.json) adds 13 fixed cases for
initial resolution from an exact published root. Its expected full lock is
[expected/resolve.lock.json](expected/resolve.lock.json), authored from the signed
fixture with deterministic local reference IDs. It is never captured from runtime
output. The original 15 restore cases and signed inputs are unchanged. The resolve
fixture has one candidate per package; it does not establish backtracking coverage.

The [refresh descriptor](refresh-cases.json) adds 14 fixed metadata-only cases.
Its [expected receipt](expected/refresh.json) identifies the exact signed timestamp
and snapshot envelopes, independently hashed before execution. Seven success cases
include damaged or missing package bundles, records and publisher envelopes;
refresh does not acquire them or authorize their use. Subsequent restore still
refuses those damaged packages. Seven refusal cases cover metadata authentication,
unsupported policy and uninitialized, missing, corrupt or unresolved trust state.
The original restore/resolve descriptors and signed inputs remain unchanged.

The [signed directory](signed/) contains an exact two-Library lock, an explicit
bootstrap root, publisher policy, and local registry. Both Libraries, registry
records and publisher statements retain the independently authored bytes from the
[original signed fixture](../local-registry/assets/signed/README.md). The MVP-only
TUF metadata is independently re-signed with a fixed expiry of
`2100-01-01T00:00:00Z` for every role. Parent links, root identity, bootstrap pin
and lock evidence hashes bind those new exact bytes. The policy requires
`fresh-metadata`. No package runtime authors these inputs or their expected results;
the original historical fixture remains unchanged.

The root package `example.com/finance/loan-rules` version `1.0.0` depends on
`example.com/finance/eligibility` version `1.2.0`. Both payloads satisfy the official
Morphir v4 JSON schema. A separate consumer project generates and compiles the
restored eligibility Library. Its complete generated module is frozen in
[expected/decision.gleam](expected/decision.gleam). This establishes consumption
of a restored provider. It does not establish cross-package reference lowering
in the Gleam backend.

## Execute and verify

From the parent checkout:

```sh
cargo test --locked -p morphir-mck --test package_mvp_fixture
cargo test --locked -p morphir --test package_mvp
cargo test --locked -p morphir-mck --test package_resolve_fixture
cargo test --locked -p morphir --test package_resolve
cargo test --locked -p morphir-mck --test package_refresh_fixture
cargo test --locked -p morphir --test package_refresh
cargo run --locked -p morphir-mck --example package_mvp_fixture -- \
  --source . --check spec/package/mck/fixtures/mvp-fresh-restore/signed
```

The shared test-only controller at
`crates/morphir-mck/tests/support/package_mvp.rs` prepares isolated directories
from this fixture. CLI integration invokes the actual `morphir package` commands
and compares each result to the frozen case. The controller contains no package
implementation or second compatibility runner. The shared MCK adapter/report
integration remains separate work; these tests are not an MCK report.

Authoring uses the existing public deterministic Ed25519 Dalek signer. Independent
TUF verification uses the pinned upstream Rust TUF client; publisher verification
uses Ring. The fixture tests verify the new metadata links and digests, preserve
the historical package and publisher bytes, and check the stricter MVP policy.
They also check all 15 copied example inputs and the unchanged golden. The expired timestamp
variant is signed independently, so an expiry failure cannot be confused with a
bad signature. Content tampering preserves valid JSON and valid registry signatures;
publisher-policy tampering preserves valid registry authentication.

The baseline verification clock is fixed at `2027-01-01T00:00:00Z`. An additional
independent positive check verifies all roles at `2099-01-01T00:00:00Z`.
The CLI and executable example use real time, with no test clock override.
All positive role expiries are fixed at `2100-01-01T00:00:00Z`; fixtures do not
renew themselves. This long horizon keeps the static example usable and is not
a recommendation for production metadata lifetime.
The independently signed expiry variant expired on `2020-01-01T00:00:00Z`.
All signing seeds are public test data and must never authorize real packages.

## Scope

The old integrity 80, resolution 78, and original draft.3 54 cases with 6 bound
and 121 pending assets retain their identities and status. This descriptor does
not relabel or count any of them as delivered. The separate
[scoped-update corpus](../mvp-scoped-update/README.md) covers explicit target
updates. Complete failed-write/concurrency coverage, consolidated compatibility reports,
and six-target published-binary qualification remain MVP work. Automatic recovery,
historical grants, and full production qualification remain deferred to #912.

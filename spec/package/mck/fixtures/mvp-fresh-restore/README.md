# Fresh exact-lock restore MVP fixture

This fixture supplies the first executable CLI slice of the
`local-library-mvp:0.1.0-draft.1` prerelease profile. The separate
[case descriptor](cases.json) freezes outcomes before execution. It does not claim
the full MVP milestone, the production recovery profile, or the 296-obligation
portable inventory has passed.

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
not relabel or count any of them as delivered. Deterministic resolve/update,
complete failed-write/concurrency coverage, consolidated compatibility reports,
and six-target published-binary qualification remain MVP work. Automatic recovery,
historical grants, and full production qualification remain deferred to #912.

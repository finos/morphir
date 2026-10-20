# Installed sealed-claim test inputs

`node-report.json` is a byte-exact historical actual installed Node report.
`checker-policy-v3.json` is its explicit caller policy. `provenance.json` records
their hashes, tested source association and original outcome. The tests also use
the existing maintained `installed_client_controls/cases24.json` bytes.

These assets support saved-report consistency tests. They do not rerun the SUT,
certify current filesystem reads or joins, establish build equivalence, or qualify
the original full151 cases/175 roles. The original first client remains
`ExpectedBlocked`, `qualified=false`, with the other23 rows not attempted.

## Ordinary engine controls

From the parent repository, run:

```sh
mise exec -- cargo test --locked -p morphir-mck --lib \
  workbench::model_originals::workflow::pipeline::installed_client_tests::sealed_claims:: \
  -- --nocapture --test-threads=1
```

The suite has25 nonignored controls and one ignored export utility. It needs no
installed package, Node, native executable, source checkout, W path or handoff
environment variable. Asset absence fails compilation; report, policy and
maintained full24 source hashes are checked strictly. A held temporary directory
contains the replay kit for the entire public replay call.

The genuine base and valid OpenPrefix plus successful JoinedCleanup remain
accepted as unqualified evidence. The other23 mutations require their exact
private checker cause and public `saved first failure differs`. Both sealed and
weaker source claims retain the independently strong worker success requirement
when verified Ready record facts are present. Worker counts are counterfactual
negative claims, not assertions that the historical workers actually failed.

## Explicit fresh installed qualification

The existing two ignored tests execute the actual configured runner and SUT.
Supply all inputs as absolute paths through:

- `MORPHIR_MCK_INSTALLED_PACKAGE`
- `MORPHIR_MCK_INSTALLED_NODE`
- `MORPHIR_MCK_INSTALLED_SOURCE_CHECKOUT`
- `MORPHIR_MCK_INSTALLED_POLICY`
- `MORPHIR_MCK_INSTALLED_NATIVE`, additionally required for the native test

Then select each test explicitly:

```sh
mise exec -- cargo test --locked -p morphir --test installed_mck_cli \
  actual_installed_node_runs_canonical_three_commands_and_saved_replay_refuses_tamper \
  -- --ignored --exact --nocapture

mise exec -- cargo test --locked -p morphir --test installed_mck_cli \
  actual_installed_native_runs_canonical_three_commands_and_saved_replay_refuses_tamper \
  -- --ignored --exact --nocapture
```

Missing inputs hard-fail when selected. The caller supplies the policy; the tests
do not choose positive defaults or enlarge it. The tests first require a fresh
real run, actual factual acceptance and its accepted saved replay. They then use
the same24 pure mutations as the engine suite on that fresh report, without
substituting the historical fixture. All23 negatives require both the API and
actual CLI to report `saved first failure differs`. The base and valid weaker
source compatibility remain unqualified. Existing destination tamper checks also
remain.

Ordinary CI can run the historical engine suite. It does not provision or run
these explicitly ignored installed SUT tests. This README does not claim a new
CI job, current native qualification, strict checks passing, or full-profile
coverage.

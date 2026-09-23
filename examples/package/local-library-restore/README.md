# Local Library resolve and restore MVP

Run from the repository root:

```sh
morphir itest examples --filter package/local-library-restore
```

The scenario initializes explicit trust, refreshes authenticated registry metadata,
resolves an exact published root into a new complete lock, refreshes again without
changing the lock, restores both Libraries, generates Gleam from the restored eligibility provider and compiles that
source in the consumer project. It then freshly authorizes a second exact replay.
The integration driver copies this directory into an isolated workspace.

`fixture/` is a checked-in copy of the independently signed MCK MVP fixture at
`spec/package/mck/fixtures/mvp-fresh-restore/signed/`, excluding test-only mutation
inputs. Its public deterministic signing keys are for tests only. The policy
requires fresh metadata; the bootstrap root is pinned by exact digest. The
expected generated source is reviewed static text, not generated during a test.
All positive TUF roles expire at `2100-01-01T00:00:00Z`, and independent fixture
tests verify them at `2099-01-01T00:00:00Z`. This fixed test-only horizon keeps the
example usable with the CLI's real clock. It is not a production expiry policy;
the public fixture keys must never authorize real packages.

Resolution verifies the complete selected graph before publishing a lock, and
its exact bytes are compared with an independently authored golden. This example
has one eligible version per package; it does not demonstrate backtracking.
Initial selection excludes yanked releases and refuses catalogs with revoked
records. Full revocation transitions remain in the production-grade milestone.

`morphir package refresh` authenticates the current timestamp, snapshot and targets
and commits the accepted trust state. Its receipt reports the exact signed
timestamp and snapshot digests. Refresh does not read package records, publisher
envelopes or bundles, and grants no package authority. A later restore still
verifies all package material. Refresh preserves existing locks; metadata that
advances beyond their pins requires a separate resolution or update workflow.
Authenticated revoked declarations are refused within this MVP boundary.

This delivery supports one caller-controlled local registry, an existing
output parent and a new output destination. Lock metadata pins must match the
freshly authenticated view; older historical evidence is not supported by this
MVP. Restore never implicitly resolves or rewrites the lock. Trust state is
initialized explicitly and cannot be reset by repeating initialization.

A missing, corrupt or unresolved store is refused. Do not delete established
trust state to bypass a refusal. Automatic recovery, historical grants and full
provider/power-loss qualification are tracked in finos/morphir#912. This example
proves explicit metadata refresh, initial resolution, fresh restore and provider code generation/compilation; it does not claim
cross-package code linking or evaluation of the generated program.

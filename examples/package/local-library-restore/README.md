# Local Library restore MVP

Run from the repository root:

```sh
morphir itest examples --filter package/local-library-restore
```

The scenario initializes explicit trust, restores both Libraries in the supplied
lock, generates Gleam from the restored eligibility provider and compiles that
source in the consumer project. It then freshly authorizes a second exact replay.
The integration driver copies this directory into an isolated workspace.

`fixture/` is a checked-in copy of the independently signed MCK MVP fixture at
`spec/package/mck/fixtures/mvp-fresh-restore/signed/`, excluding test-only mutation
inputs. Its public deterministic signing keys are for tests only. The policy
requires fresh metadata; the bootstrap root is pinned by exact digest. The
expected generated source is reviewed static text, not generated during a test.

This first delivery supports one caller-controlled local registry, an existing
output parent and a new output destination. Lock metadata pins must match the
freshly authenticated view; older historical evidence is not supported by this
MVP. Restore never implicitly resolves or rewrites the lock. Trust state is
initialized explicitly and cannot be reset by repeating initialization.

A missing, corrupt or unresolved store is refused. Do not delete established
trust state to bypass a refusal. Automatic recovery, historical grants and full
provider/power-loss qualification are tracked in finos/morphir#912. This example
proves fresh restore and provider code generation/compilation; it does not claim
cross-package code linking or evaluation of the generated program.

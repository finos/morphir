---
id: local-libraries
title: Use signed local Libraries
sidebar_label: Signed local Libraries
---

# Use signed local Libraries

The package MVP consumes Libraries from one caller-controlled local registry. You
provide a trust policy, an independently trusted bootstrap root, and the registry
directory. Morphir authenticates the registry and publisher, writes a complete
lock, and verifies every Library before restoring it. No package supplies its own
trust policy.

The commands below use the checked-in [resolve and restore example](https://github.com/finos/morphir/tree/main/examples/package/local-library-restore).
Run them from a disposable copy of that example directory with `morphir` on your
`PATH`. Its signing keys are public test data. For your own registry, provision a
policy with independently trusted repository and publisher keys; do not use the
example policy or keys to authorize real Libraries. The [local Library trust
profile](https://github.com/finos/morphir/blob/main/spec/package/package-trust-profile.md)
describes the policy fields and bootstrap pin.

## Establish trust and select a graph

Initialize a **new** state directory with a root whose exact digest matches the
policy. Keep that state directory for later operations. Initialization refuses an
existing directory so it cannot silently reset rollback protection.

```sh
morphir package trust init --policy fixture/trust-policy.json --root fixture/registry/metadata/1.root.json --state trust-state --json
```

You can authenticate the registry's current timestamp, snapshot, and targets
without changing a lock or reading package bundles. The receipt contains the
accepted signed metadata digests. Refresh alone grants no permission to use a
Library.

```sh
morphir package refresh --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --assurance portable --json
```

Resolve an exact published root into a new, complete lock. Resolve verifies the
selected graph before publishing the lock. Its output parent must exist, and the
output file must be new. The example's `consumer/` directory already exists.

```sh
morphir package resolve --root example.com/finance/loan-rules@1.0.0 --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --output consumer/morphir.lock --assurance portable --json
```

`--assurance portable` explicitly accepts caller-controlled local filesystem
roots. The hardened filesystem mode is outside this MVP. Keep the resulting lock
with the consumer project; it identifies exact releases and metadata pins, but
is not a substitute for fresh authentication.

## Restore and consume

Restore the exact locked graph into a **new** destination. It checks current
signed metadata, publisher authority, and package content before exposing the
complete graph. It neither resolves dependencies nor rewrites the lock.

```sh
morphir package restore --policy fixture/trust-policy.json --lock consumer/morphir.lock --registry fixture/registry --state trust-state --output consumer/libraries --assurance portable --json
```

The example uses the restored eligibility Library as input to Gleam generation,
then compiles the generated source in its consumer project:

```sh
morphir gleam --json generate --config consumer/morphir.toml --input consumer/libraries/example.com/finance/eligibility/1.2.0/ir.json --output consumer/generated
morphir gleam --json compile --config consumer/morphir.toml --input consumer/generated --output consumer/compiled
```

This proves provider generation and compilation. It does not prove cross-package
linking or execution of the generated program. To replay the same lock, choose a
different new restore destination; replay authenticates the graph again. The
[offline scenario](https://github.com/finos/morphir/blob/main/examples/package/local-library-restore/scenarios.md)
checks each command and compares the lock and generated source with fixed results.
Run it from the repository root with:

```sh
mise run test:examples -- --filter package/local-library-restore
```

## Refresh or update later

Use `refresh` to record a newly authenticated metadata view without changing a
lock. If that view advances beyond a lock's metadata pins, restore refuses the
old lock. Resolve a new full lock or use `update` to change named dependencies.
Neither operation overwrites the previous lock.

For a scoped update, start with an existing full lock, request a non-root target,
and write a **new** lock file. `--target` can be repeated; adding `@VERSION` asks
for one exact stable version. Packages outside the old target closure stay
pinned. Restore the new lock into another new directory before consuming it.

```sh
morphir package update --lock fixture/morphir.lock --target example.com/finance/eligibility --policy fixture/trust-policy.json --registry fixture/registry --state trust-state --output consumer/morphir.lock --assurance portable --json
```

That command belongs to the separate [scoped update example](https://github.com/finos/morphir/tree/main/examples/package/local-library-update),
which has its own `fixture/` and `consumer/` directories. Its scenario verifies
the unchanged old lock, the selected dependency closure, fresh restore, and
consumer compilation:

```sh
mise run test:examples -- --filter package/local-library-update
```

## When an operation refuses

The MVP requires fresh signed metadata and a readable, established trust state.
Expired or unavailable metadata, a lock pinned to another view, revoked
releases, corrupt or missing content, and occupied output paths can prevent an
operation. Diagnose the cause and use new output paths for retries. An operator
may need to renew registry metadata, restore access to the registry, select a
currently authorized release, or recover protected state through an approved
administrative process. Do not delete trust state or copy a package cache to
bypass a refusal. This MVP does not reconstruct lost or corrupt state, grant use
from expired historical metadata, or perform automatic recovery. Those behaviors
and full provider and power-loss qualification are tracked in
[the production-grade milestone](https://github.com/finos/morphir/issues/912).

## Inspect compatibility evidence

Repository maintainers can run the separate 70-case MCK profile against an
explicit adapter, save one prerelease JSON report, verify its record inventory
against the checked-in kit, and open an offline HTML view. From the repository
root, after building the Rust adapter:

```sh
morphir mck package mvp-run --source . --adapter ecosystem/morphir-rust/target/debug/mck-adapter-rust --adapter-arg package-mvp --report mvp-report.json
morphir mck package mvp-report check mvp-report.json --source .
morphir mck package mvp-report render mvp-report.json --output mvp-report.html
```

The HTML shows a saved run, including failures. The JSON and independent
`check` result are the compatibility evidence; rendering alone does not verify
the inventory or authorize package use. The report format is prerelease
`0.1.0-draft.1`.

---
type: Decision Record
title: MCK tooling lives in the Rust Morphir CLI
description: finos/morphir owns all shared MCK tooling, written in Rust and delivered as `morphir mck`, with an explicit adapter on every run and CLI-managed kit vendoring.
state: Accepted
decided: 2026-09-18
supersedes: ["0001"]
tags: [mck, tooling, rust, cli, adapters, ir, packages]
status: stable
---

# MCK tooling lives in the Rust Morphir CLI

On 2026-09-18 the maintainer moved ownership of all shared Morphir Compatibility Kit (MCK) tooling
to finos/morphir. The tooling is written in Rust and delivered through the existing `morphir` CLI
as `morphir mck`. This covers kit management, IR compatibility testing and package compatibility testing.

Three rules came with the move:

| Rule | Statement |
| --- | --- |
| One shared runner | There is still exactly one shared compatibility runner. Only its owner and language changed. |
| Explicit adapter | `morphir mck run` requires `--adapter`. No implicit binding, no discovery, no fallback. Omission is usage error 2 before any testee starts, and no report is written. |
| Vendored kits | The CLI acquires, pins, vendors, inspects, updates and runs kit data inside an implementor's own repository. |

This record supersedes the ownership portion of
[decision 0001](/decisions/0001-package-compatibility-uses-the-shared-mck-core.md). It keeps 0001's
rules on independent expectations and adapters.

It records a decision, not a delivery. When it was written no Rust MCK code existed, and the
TypeScript driver was still the authoritative gate. The [migration contract](../../../../../spec/mck/migration.md)
tracks the transition.

## Summary

Decision 0001 put the runner in finos/morphir-typescript while the corpus stayed in finos/morphir.
Every corpus change then needed a cross-repository kit sync, and running the kit needed Node or Bun
or a separately downloaded binary. Moving the runner next to the corpus, inside the CLI users
already install, removes both costs.

| Option | Outcome | Why |
| --- | --- | --- |
| Shared Rust engine in finos/morphir with a thin `morphir mck` command layer | Chosen | Co-locates corpus and tooling, and keeps the engine usable as a library |
| CLI-only Rust rewrite | Rejected | Couples reusable execution and protocol tests to command execution |
| Rust CLI invoking the TypeScript driver | Rejected | Keeps the old owner and the JavaScript runtime requirement |
| Keep the shared core in finos/morphir-typescript (decision 0001) | Rejected | Splits corpus from tooling and gives users a second entry point |

## Why

**One repository.** The corpus, schemas and fixed expectations already live in finos/morphir. The
runner that interprets them lived elsewhere, so the TypeScript package carried a synced copy of the
kit and a lock file to prove which copy it had. A parent-owned runner embeds the corpus at build
time from the same commit.

**One entry point.** Binding authors already install `morphir`. A Rust MCK needs no Node, Bun, Git
or source checkout to run. An adapter may still need its own implementation's runtime.

**Explicit adapter.** The TypeScript CLI ran its own binding in-process when `--adapter` was absent.
A runner that lives in the Rust CLI would make the Rust binding the silent default by the same
habit. A compatibility report must always say which implementation was tested because someone
chose it, so the default was removed instead of re-pointed.

**Vendored kits.** An implementor's CI needs the exact bytes it ran against to be reviewable in its
own repository. Pinning only a driver version hides kit changes inside a tool upgrade. Vendoring the
kit with a manifest makes a kit update an ordinary reviewed diff.

What did not change from decision 0001:

- The runner compares output with committed expectations. It never computes expectations by
  calling the implementation under test.
- The engine does not depend on any implementation's IR codec. It compares canonical strings;
  adapters decode, encode and handle document trees.
- Independent implementations can share one runner. Sharing an algorithm does not make a second
  independent implementation.
- Model packages, executable extensions and installable tools keep distinct artifact contracts.
- IR protocol and report version 1 stay supported and unchanged.

## Alternatives rejected

### CLI-only Rust rewrite

This meets the ownership and distribution goals. It leaves case interpretation, comparison and
transport reachable only through a command, so library consumers and protocol tests would have to
launch a process. The engine is a library crate with a thin command module instead.

### Rust CLI invoking the TypeScript driver

This is acceptable only as a temporary migration aid in development or CI. As a product it keeps
the runtime requirement and the old owner, which are the two things the decision removes.

### Keep the shared core in finos/morphir-typescript

Decision 0001 chose this two days earlier and its reasoning about one shared runner still holds.
It did not weigh where that runner should live once the Rust CLI became the ecosystem's installed
entry point. The maintainer's direction settles that.

## Consequences

- finos/morphir-typescript is an implementation under test. It keeps its adapter,
  `mck-adapter-typescript`, and its implementation tests. New shared MCK features, and the
  unfinished registry and restore work, do not land there. Its MCK code takes break/fix
  maintenance only until cutover.
- The general preference for TypeScript and `.mjs` repository tooling stands. MCK tooling is the
  named exception and is written in Rust.
- Delivery is IR first ([#851](https://github.com/finos/morphir/issues/851)), then the existing
  package suites, then the registry work ([#852](https://github.com/finos/morphir/issues/852)).
  Existing gates keep running until a verified Rust replacement is released and adopted.
- The TypeScript `kit sync` command has no successor. Parent builds embed the corpus directly;
  implementors use `morphir mck kit vendor` and `kit update`.
- Coverage vocabulary and node aliases move into parent-owned, language-neutral data. The runner
  must not derive the required vocabulary from a binding it tests.
- The Rust engine is not a drop-in replacement for the published TypeScript library API.
  Cross-language consumers use the process protocol and reports.
- The detailed contracts are the [CLI contract](../../../../../spec/mck/cli-contract.md) and the
  [kit manifest contract](../../../../../spec/mck/kit-manifest.md).

## Unresolved

Package suite command spelling, the package adapter protocol under the Rust runner, and every
registry and restore contract are deferred to #852 and
[#800](https://github.com/finos/morphir/issues/800). An optional built-in binding, selected
explicitly and tested against the same process adapter, is allowed later and is not planned.

## Revisit when

Revisit if a supported platform cannot run the native CLI, or if the Rust engine cannot reproduce
IR version 1 behaviour against the [frozen baseline](../../../../../spec/mck/baseline/README.md)
without changing committed expectations. Preference for another implementation language is not
sufficient evidence.

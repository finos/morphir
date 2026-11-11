---
type: Decision Record
title: The MCK runner moves to the .NET host
description: "The shared MCK runner moves from the Rust `morphir mck` to the .NET host in finos/morphir-dotnet; cases, fixed expectations and report contracts stay in finos/morphir as runner-neutral data."
state: Accepted
decided: 2026-11-09
supersedes: ["0003"]
tags: [mck, tooling, dotnet, rust, cli, adapters]
status: stable
---

# The MCK runner moves to the .NET host

On 2026-11-09 the maintainer moved the home of the shared Morphir Compatibility Kit (MCK) runner. It
moves from the Rust `morphir mck` to the .NET host in finos/morphir-dotnet.

The runner is the program that reads a kit's cases, drives an implementation under test, and
compares what it observes with the kit's fixed expected results. The kit's data is everything
else: specifications, schemas, cases, expected results and report contracts.

| Part | Home after this decision |
| --- | --- |
| New runner code | finos/morphir-dotnet, in the .NET host |
| Kit data | finos/morphir, written so that it names no runner |
| Rust `morphir mck` (`crates/morphir-mck`) | finos/morphir. It keeps the gates it runs today and takes no new runner features |

This record supersedes [decision 0003](/decisions/0003-mck-tooling-lives-in-the-rust-morphir-cli.md)
on which program is the runner and where its code lives. Three rules from 0003 and
[decision 0001](/decisions/0001-package-compatibility-uses-the-shared-mck-core.md) do not depend on
the runner's home, and they stay:

- Expected results are committed data. The runner never computes them by calling the
  implementation under test.
- An implementation takes part through an explicit adapter.
- A kit has one runner. Nobody adds a second checker beside it, in any language.

It records a decision, not a delivery. When it was written, finos/morphir-dotnet had a
`src/Morphir.Conformance` project and an `establish-morphir-compatibility-kit` change
([finos/morphir-dotnet#495](https://github.com/finos/morphir-dotnet/pull/495)). The IR and package
gates in this repository still ran under Rust `morphir mck`.

## Summary

The Rust runner cost too much to build. The maintainer named compile time and disk space, and on
the same day said the project treats the Rust CLI as legacy and invests in the .NET and MoonBit
hosts. A runner that keeps growing inside the Rust CLI works against that.

| Option | Outcome | Why |
| --- | --- | --- |
| .NET host in finos/morphir-dotnet | Chosen | One of the two hosts the project invests in; it already has a conformance project |
| MoonBit host in finos/morphir-moonbit | Rejected | The other candidate. The maintainer chose .NET and gave no reason for the order |
| Keep Rust `morphir mck` (decision 0003) | Rejected | Compile time and disk space, in a CLI now treated as legacy |

## Why

**Build cost.** Every change to the runner means building the Rust workspace. The maintainer
described the Rust runner as resource intensive, naming compile time and disk space. Decision 0003
did not weigh this, because no Rust MCK code existed when it was written.

**Where the investment goes.** Decision 0003 chose Rust because `morphir` was the entry point that
binding authors already installed. On 2026-11-09 the maintainer said the project focuses on the
.NET and MoonBit hosts and may return to Rust only after one of them works. New kits test those
hosts, so the runner belongs with one of them.

**Data stays here.** The reasoning in 0003 for keeping the corpus in finos/morphir still holds:
schemas and fixed expectations are product data, and a change to them should be one reviewed diff
in one place. What changes is that the runner no longer builds from the same commit. Kit data
therefore has to be readable by a runner in another repository, and must not depend on anything
only the Rust runner does.

## Alternatives rejected

### MoonBit host in finos/morphir-moonbit

The maintainer first named the .NET host and the MoonBit host as the two candidates, then chose
.NET. The decision as given states no reason for preferring one to the other, so this record does
not supply one. MoonBit remains an implementation under test.

### Keep Rust `morphir mck`

This is decision 0003. Its reasoning about one repository and one entry point was sound for the
project as it stood on 2026-09-18. It loses to the build cost above and to the change in which
hosts the project invests in.

## Consequences

- New runner code goes to finos/morphir-dotnet. `crates/morphir-mck` takes fixes for the gates it
  already runs, and no new runner features.
- This record retires no gate. The parent IR and package gates keep running under Rust
  `morphir mck`, and the [CLI contract](../../../../../spec/mck/cli-contract.md) and
  [kit manifest contract](../../../../../spec/mck/kit-manifest.md) still describe those commands.
- New cases and expected results are runner-neutral. They do not name `morphir mck`, and they do
  not rely on a feature only the Rust engine has.
- The first kits planned for the .NET runner are the WASM host qualification corpus
  (`spec/mep/mck/wasm-host.cases.json`) and the bounded model access cases. Both are defined in
  OpenSpec changes in this repository.
- The general preference for TypeScript and `.mjs` repository tooling stands. The MCK runner is
  still the named exception. Checks of kit data that run in this repository, such as the corpus
  self-checks under `tools/`, are not runners and stay in TypeScript.
- `AGENTS.md` and `openspec/config.yaml` in this repository state the new home.

## Unresolved

- Whether the existing IR and package gates move to the .NET runner, in what order, and what
  evidence a move needs. Nothing is scheduled.
- The .NET runner's command surface, and whether the CLI contract and kit manifest contract carry
  over unchanged.
- How an implementor vendors a kit into its own repository without `morphir mck kit vendor`.

## Revisit when

Revisit if the .NET host cannot run on a platform where an implementation under test must be
qualified. Revisit also if moving an existing gate would need a change to committed expected
results. Preference for another implementation language is not sufficient evidence.

---
type: Decision Record
title: The session owns the application lifecycle
state: Accepted
decided: 2026-09-20
tags: [cli, lifecycle, starbase, session, typestate, configuration]
status: stable
description: Morphir chose to have the CLI session implement every starbase phase and hold phase-produced data in a discriminated union, so command code cannot run without the state its phase produced. Implementation is pending.
---

# The session owns the application lifecycle

Morphir chose to have `MorphirSession` implement all of starbase's phases rather than only
`execute`. Each phase produces the state the next one needs, and the session holds that state in a
discriminated union. Command code receives the produced state directly, so it cannot run without
it.

## Implementation status

Not implemented. This record captures the decision taken on 2026-09-20 and the reasoning behind
it.

At the time of writing `MorphirSession` holds `command`, `operation_id` and `out`, and its
`AppSession` implementation overrides only `execute` (`crates/morphir/src/main.rs`). Commands still
load configuration themselves, and the log guard still lives in `main`.
[Configuration and lifecycle](/configuration-and-lifecycle.md) is the narrative home and tracks
what has landed.

## Summary

starbase drives four phases: startup, analyze, execute and shutdown. Morphir implemented one.
`startup`, `analyze` and `shutdown` were left at their defaults.

Work that belongs to a phase ran wherever it happened to be needed. Commands discovered and loaded
configuration several frames deep inside `execute`. Logging initialized before the session existed.
The log guard lived in `main` and reached outcome reporting through nine separate call sites.

| Option | Outcome | Why |
| --- | --- | --- |
| Populate the phases, hold phase data in a union | Chosen | Illegal states become unrepresentable in command code |
| A component registry with declared phases | Rejected | Turns compile-time errors into runtime lookup failures, for six components we control |
| Classic consuming typestate | Rejected | starbase cannot express it, see below |

## Why

**Availability is a property of the phase.** A command runs in `execute`, so configuration exists
by then. Saying that in the type removes the question. Before this decision a command received an
`Option` and had to check, and GH #887 is what happens when one path does not.

**starbase forbids consuming typestate.** `run_with_session` takes `&mut S` and calls `startup`,
`analyze`, `execute` and `shutdown` on that one value. A transition of the form
`fn startup(self) -> Session<Analyzed>` cannot be expressed. Writing a custom driver to allow it
would give up `AppRunOutcome`, the recorded `last_phase`, exit-code handling and the guarantee that
shutdown runs after a failed phase. That trade is worse than the check it removes.

**A discriminated union fits, and typestate still pays below the boundary.** The shape decided on
is:

```rust
struct MorphirSession {
    command: Commands,
    resources: SessionResources,   // live for the whole run
    state: SessionState,
}

enum SessionState {
    Bootstrapped(Bootstrapped),   // host configuration and logging only
    Ready(Arc<Ready>),            // and configuration, home, out root
}
```

`Ready` is constructible only by `startup`, and every field on it is present. Command handlers take
`&Ready` rather than the session. All command code, which is where these defects occur, is
statically guaranteed a loaded configuration. One exhaustive match at the session boundary carries
the only runtime check.

**The union holds phase-produced data, nothing else.** An early draft added a `ShutDown` variant.
That was wrong twice. Shutdown is not stateless: it flushes logs, reports the log path and the
operation outcome, and reads configuration to report provenance. A unit variant discards what
shutdown needs. starbase also runs shutdown after a failed startup, so shutdown can be reached
holding only `Bootstrapped`, and its work depends on how far the run got.

The second error was mixing two ideas. Phase progress, meaning which phase the run reached, already
belongs to starbase in `AppPhase` and `AppRunOutcome.last_phase`. Modelling it again here would
create a second source of truth. Phase-produced data belongs to Morphir. Only that goes in the
union, and `shutdown` reads the current state rather than replacing it.

## Two configuration stages

Some callers run before argv is parsed, so they cannot use a loader that needs a working directory
and file access, and they can emit diagnostics that expect logging to exist. That is a named stage,
not an exception.

| Stage | Layers | Used by |
| --- | --- | --- |
| Host configuration | defaults and environment | logging, `MORPHIR_HOME` |
| Application configuration | all eight | every command |

The host stage fixes hand-typing rather than layering. A caller asks for `logging.level`, and the
same mapping code derives `MORPHIR_LOGGING__LEVEL`.

.NET's Generic Host separates `ConfigureHostConfiguration` from `ConfigureAppConfiguration` for the
same reason.

## Consequences

`AppSession` requires `Clone`, and `run_execute` clones the session, so everything the session holds
must be cloneable. `Ready` sits behind `Arc` to keep the clone cheap. `LogGuard` must also sit
behind `Arc`, because it holds a `WorkerGuard` and a file handle, is not `Clone`, and must flush
once.

`TaskLock` needs no shutdown action. It has a `Drop` implementation, so release is already handled.

Outcome reporting moves from `main` into `shutdown`, which collapses nine call sites to one.

One starbase capability that was available and unused comes into use: miette configuration, for a
panic hook and a theme matching the rest of the CLI output. Measured rather than assumed, it does
not change cause-chain rendering, because miette's `fancy` default already prints the chain.

`AppExitCode` is deliberately not adopted. Each phase already returns `Result<Option<u8>, E>` and
starbase acts on it, and commands use that today. A field nothing reads would be speculative, so
it waits for a caller that needs to set an exit code from inside a command without threading it
through every return.

## Revisit when

Revisit when a seventh or eighth phase-owned component appears, or when extensions need to take
part in the lifecycle. Either makes a component registry worth its indirection.

See [The command line is a configuration layer](/decisions/0001-the-command-line-is-a-configuration-layer.md)
for what `Ready` holds, and [Configuration and lifecycle](/configuration-and-lifecycle.md) for the
model as a whole.

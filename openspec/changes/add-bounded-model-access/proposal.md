# Proposal

## Why

A generator should be able to traverse a Morphir package larger than its WASM memory allowance. Existing document trees split the files, but several readers still assemble the complete model, and repeated names add storage and allocation costs.

## What Changes

Follow one package, `acme/orders`, from compilation to generated files. Compilation leaves a document tree in the configured workspace out root. Generation discovers it through the task result record, opens a consistent snapshot, requests bounded batches of definitions and writes artifact batches to its own task directory.

```text
compile result -> snapshot + paged inventory -> bounded generator
                                                     |
                                                     v
                                     staged artifacts -> install
```

- Reuse the v3.1 JSON/YAML and v4 JSON/YAML tree paths and codecs. Keep explicit support declarations for each semantic version, encoding and operation.
- Define bounded model discovery and reads, snapshot leases, disk-backed indexes and cancellation. Use the established `<out>/<member>/<task>.dest` and task-result conventions, with `.morphir/out` as the configurable default.
- Add resumable generation sessions suitable for process and WASM extensions, including bounded input, retained state and output. Add a complementary document-batch publication contract for future frontend adoption; large-package generation is the first delivery gate.
- Specify an opt-in, versioned contextual-document envelope for every IR document kind. Its file-local typed name tables support reversible `compactNames` and `expandNames`. Existing plain document profiles keep their grammar.
- Develop the shared MCK corpus through independent morphir-dotnet and morphir-moonbit adapters first. Keep one runner for the kit and defer morphir-rust runtime adoption. That runner is the Rust `morphir mck` today and is intended to move to the .NET or MoonBit host; the choice is made outside this change, so cases and expectations stay runner-neutral.
- Measure indexed reference lookup separately. A dictionary is not an occurrence index, and partial-read performance is an experiment rather than a claimed property of JSON.
- Keep the requirements accompanied by a running example, diagrams and failure journeys. The standalone design explains decisions and alternatives; the delta specs state observable behavior.

## Capabilities

### New Capabilities

- `ir/model-snapshots`: bounded model discovery, document access and artifact lifetimes across stages under the resolved workspace out root.
- `ir/name-compaction`: typed file contexts and lossless, deterministic name compaction through a separately versioned storage envelope.
- `mep/model-access-sessions`: negotiated, resumable model operations with bounded input and output, scoped document requests and explicit completion.
- `mck/bounded-generation`: shared conformance and resource evidence for large-package generation, initially qualified through .NET and MoonBit.

### Modified Capabilities

None. The existing `mep/generic-guest-profile` remains a small-model qualification profile. The bounded-generation profile is additive and does not redefine its cases or results.

## Tracking

- OpenSpec change: `openspec/changes/add-bounded-model-access/`.
- Origin: [discussion #214](https://github.com/finos/morphir/discussions/214).
- Related shared qualification work: [issue #965](https://github.com/finos/morphir/issues/965). This proposal does not claim to complete that issue.
- Owning Beads epic: pending. Local creation was rejected by the shared Dolt database with `Merge conflict detected, @autocommit transaction rolled back`; no issue id was returned. Resolve existing shared database conflicts before creating the epic and linking this path. Remote synchronization is also deferred under the Windows `bd dolt push` restriction in AGENTS.md.

## Impact

The parent repository owns the contract models, fixed examples, MCK corpus and report contract. Runner code lands wherever the kit's runner lives when the work starts. Planned implementation work belongs in morphir-dotnet and morphir-moonbit, with separate tracking and receipts. This planning change edits no implementation or pinned submodule.

The proposed bounded MEP line is `0.2.0-draft.2`; the access contract and contextual-document envelope each start at `0.1.0-draft.1`. These are proposed draft identifiers, not newly advertised runtime capabilities. They require exact negotiation and do not extend MEP `0.2.0-draft.1` or alter existing IR `3.1.0` / `4.0.0` grammars. No new semantic IR revision is minted by this proposal.

First delivery qualifies native .NET and native MoonBit host paths, an in-process reader for each implementation, and a WASM generation extension path for each host. A shared small generator fixture provides fixed cross-host artifacts; representative production generators qualify only when their own algorithms meet the same limits. Browser hosts, evaluation, shared context imports and retained immutable build generations follow later.

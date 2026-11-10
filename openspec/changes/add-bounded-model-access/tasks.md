# Tasks

This is the OpenSpec implementation breakdown, not a completed-work ledger. Beads remains the task tracker. The owning epic and child links are pending because the shared database rejected creation with a Dolt merge conflict; no id was returned. Create those links after the existing conflict is resolved, before claiming implementation tasks. The planning artifacts are reviewable independently of that tracking failure.

Dependencies: group 1 establishes the contract and fixed corpus; groups 2 and 3 implement independent readers against it; group 4 establishes the shared session exchange; groups 5 and 6 integrate each host after its reader and group 4; group 7 consolidates qualification after both integrations. Group 8 is an independent experiment and does not block the bounded-generation gate. Keep implementation changes in their owning repositories.

Runner home: the kit's runner is the Rust `morphir mck` today, and the maintainer intends to move it to the .NET or MoonBit host. That choice is not made. Cases, expectations and receipts are data and do not depend on it. Tasks that touch runner code (1.5, 2.5, 3.5 and group 7) use whichever runner hosts the kit when they start; confirm its home with the maintainer first, and do not add code to `crates/morphir-mck` without that confirmation.

## 1. Shared contracts and fixed examples, finos/morphir

- [ ] 1.1 Encode the contextual-document envelope and exact access-version types in the parent contract sources, using established SemVer libraries; fix unknown optional/critical paths and typed alias positions. Verify positive and negative JSON/YAML examples for every file kind against generated contract validation, preserving the current plain-profile cases.
- [ ] 1.2 Specify the exact start/advance/cancel method names, tagged result sums, ordered rounds and complete access tuples in `spec/mep/contract/src/mep.gleam`, the agreeing Smithy model and generated assets. Verify transcripts for continue, complete, failed, unsupported drafts, stale rounds and limits using the existing spec consistency gates.
- [ ] 1.3 Freeze a tiny `acme/orders` model in v3.1/v4 JSON/YAML trees, contextual equivalents and expanded single-file baselines. Verify independent expectations preserve classic attribute slots, dependencies, private modules, name escaping, node roles and the final page's body facts.
- [ ] 1.4 Add fixed name-compaction cases for typed tables, literal lookalikes, context-last input, unknown optional/critical members, missing aliases and size overhead. Verify round-trip semantic equality and deterministic outputs under one published writer policy without using implementation-produced results as expectations.
- [ ] 1.5 Define bounded-generation adapter observations and resource receipts alongside the existing MCK contracts, including measurement scope and correctness/resource outcomes. Verify fixed valid/invalid receipts through the kit runner's report checks; leave frozen historical evidence and the generic guest profile unchanged.
- [ ] 1.6 Publish narrative contract guidance with the orders walkthrough, diagrams, exact proposed wire examples and the baseline version/profile matrix. Verify every example used by the corpus is referenced and that `openspec validate add-bounded-model-access --strict`, the relevant MEP spec checks and `mise run openspec:verify` pass.

## 2. Bounded readers and contexts, morphir-dotnet

- [ ] 2.1 Add failing in-process reader cases for paged discovery, v3.1/v4 file-kind decoding and bounded document reads, then implement the reader over existing `Morphir.IR.Pipeline` file/content sources. Verify the shared small corpus and oversize/ambiguous-path refusals without calling the full-distribution reader on the bounded path; document the new public entry point beside the pipeline guidance.
- [ ] 2.2 Add failing contextual JSON/YAML cases, then implement typed alias admission and lazy resolution using the existing name/version types. Verify the shared round-trip cases, literal preservation, unknown optional/critical paths and per-context limits; document the separation from `Morphir.Ion` symbol handling.
- [ ] 2.3 Implement deterministic compaction and bounded expansion exports under the fixed policy. Verify frozen expected bytes for that policy, preservation of v3 attributes and semantically ordered collections, and the case where table overhead causes a short name to remain expanded; document the policy identifier and cost model.
- [ ] 2.4 Integrate workspace output-root resolution, producer descriptors, task-owned captures/indexes and read leases into the .NET reader path. Verify relocated roots, declared member identities, explicit mutable inputs and a producer attempting to rerun during a paused reader; document cancellation and resource disposal.
- [ ] 2.5 Add the .NET adapter's in-process model-access/compaction observations to the shared corpus. Verify a kit-runner invocation explicitly selecting that adapter records the .NET revision and fixed expectations, with no substitution of the runner's own codec.

## 3. Bounded readers and contexts, morphir-moonbit

- [ ] 3.1 Add failing cases beside `pkgs/morphir-ir/yaml/tree_test.mbt` for paged inventory and selected document reads, then add a bounded path that does not require the existing complete `Map[String, String]`. Verify v3.1/v4 JSON/YAML cases, escaping and role preservation; document the distinction between bounded and full-model APIs.
- [ ] 3.2 Add contextual decoding and lazy typed alias resolution against the shared fixed cases, using existing IR naming and version modules. Verify context-last bounded spill, literal lookalikes, critical-member refusal and context limits; document the encoding offer and default unsupported behavior.
- [ ] 3.3 Implement the published deterministic compaction policy and bounded expanded export. Verify the same fixed compaction results and semantic round trips as .NET, including classic arrays and meaningful order; document file-local table scope and the absence of shared imports.
- [ ] 3.4 Connect bounded access to workspace/task storage through the existing engine/host boundary, retaining a read lease through the final batch. Verify relocated out roots, member isolation, tombstoned records and concurrent producer/cancel cases; document native and embedding capability differences without claiming browser qualification.
- [ ] 3.5 Add MoonBit in-process observations to the shared adapter contract. Verify an explicitly selected kit-runner execution records its implementation revision and completes the fixed reader/compaction corpus independently of .NET.

## 4. Resumable session contracts and SDK behavior, both implementation repositories

- [ ] 4.1 In .NET `Morphir.Mep`, add failing negotiation and lifecycle tests for the new exact draft, then implement complete tuple admission and start/advance result handling. Verify the shared transcripts, existing draft.1 behavior and C# interoperability/AOT checks affected by the public types; update the MEP README examples in the same change.
- [ ] 4.2 In MoonBit `pkgs/morphir-moonbit/mep` and the shared host layer, add failing access-session transcripts before implementation. Verify the same negotiation order, ordered rounds, typed results and compatible small-model fallback diagnostics; update its session documentation and generated contract exports together.
- [ ] 4.3 Implement scoped document/page requests and matched deliveries in both SDK paths. Verify refusal of snapshot escapes, unsolicited deliveries, digest mismatches, stale rounds and missing contextual data through fixed transcript cases; document that byte-call guests require no nested callback.
- [ ] 4.4 Implement per-exchange, resident-state and cumulative limits plus cancellation cleanup in each session owner. Verify a deliberately stalled call, excessive diagnostics, no-progress rounds and many-small-batch exhaustion; document which runtime bounds are enforced and how leases are released after termination.
- [ ] 4.5 Implement artifact chunks with path confinement, contiguous offsets, end markers and bounded diagnostics. Verify an output file larger than a frame, replayed chunks, unsafe paths and completion with an unclosed artifact; document the staged-result and install boundary.

## 5. First host generation path, morphir-dotnet

- [ ] 5.1 Connect the .NET bounded reader and access-session SDK to its native host generation boundary, using the recorded producer artifact and task-owned output stage. Verify the orders fixture against its expanded baseline and fixed expected artifacts, then document the executable invocation and exact supported tuples.
- [ ] 5.2 Execute the shared neutral WASM generator through the .NET host's supported byte-call adapter with enforced memory/deadline bounds. Verify identical fixed artifacts to the baseline, bounded input/output batches and recorded runtime identity; document this specific qualified path without claiming a .NET-authored WASM guest.
- [ ] 5.3 Integrate staged chunks with task result/tombstone and install behavior. Verify late malformed input and cancellation install no partial files, no internal indexes become products, and a waiting compile resumes after lease release; document failure recovery using the configured out root.

## 6. First host generation path, morphir-moonbit

- [ ] 6.1 Connect the bounded reader and session exchange through `pkgs/morphir-host` and the CLI generation path, keeping protocol conversion out of CLI-only code. Verify the orders fixture through native host generation against its expanded baseline and document the supported tuple set.
- [ ] 6.2 Run the same shared neutral WASM guest through the existing worker/byte-call abstraction. Verify fixed artifact equality with the .NET-hosted execution, enforced guest limits and bounded frame/chunk sizes; document the exact engine and ABI profile qualified.
- [ ] 6.3 Integrate artifact staging, task records and install through the shared host boundary. Verify producer contention, cancellation, late errors, member isolation and tombstones using observable native runs; update the workflow examples with the actual descriptor-based paths.

## 7. Kit runner and first-delivery evidence, finos/morphir and the runner's home

- [ ] 7.1 Extend only the kit runner's orchestration and observation checks needed for the new adapter profile, in the runner home confirmed above. Verify both adapters' small cases, deliberate malformed observations and separate correctness/resource outcomes through fixed expectations, without linking either implementation's IR codec into expected results.
- [ ] 7.2 Add deterministic scale fixtures with bounded documents, growing inventory and final-page dependencies; run at two scales with fixed resident budgets. Verify actual aggregate input sizes exceed the declared host/guest ceilings and that resident decoded bodies, contexts and artifact buffers stay within their bounds; freeze expected outputs independently.
- [ ] 7.3 Collect native .NET and MoonBit host receipts plus each WASM generation path with external peak-memory measurements and runtime-enforced limits. Verify report replay identifies source/kit digests, revisions, target, selected tuple, measured scopes and mandatory missing-data failures; keep large runs manual rather than adding new per-PR jobs.
- [ ] 7.4 Update the narrative adoption/support table with the qualified revisions and exact contract/profile matrix. Verify the complete first-delivery cases and parent documentation/spec gates, recording Rust runtime adoption as deferred and leaving the generic guest qualification contract intact.

## 8. Indexed reference lookup experiment, independent of first-delivery completion

- [ ] 8.1 Freeze queries and expected occurrence sets containing unused aliases, fully spelled references, literal lookalikes, context-last documents and reordered JSON. Verify plain scanning returns those independent expected sets before measuring optimized paths.
- [ ] 8.2 Compare dictionary-only access and a digest-bound location/occurrence index with the scan baseline. Measure index-build cost, cold/warm bytes read, compressed/uncompressed size, decode work, resident memory and query correctness; verify stale/recompacted bytes cannot reuse old offsets.
- [ ] 8.3 Publish a narrative experiment result with actual charts and source receipts once measurements exist. Verify every performance claim cites a measured run; if results justify shared contexts, block framing or a push-down contract, create separate Beads work rather than expanding this draft implicitly.

## Workflow follow-up

- These files capture a proposal for review; do not begin implementation from this planning turn.
- Resolve the existing shared Beads database conflict without overwriting unrelated work, then create the owning epic and repository-specific children and link this change. Record implementation progress and evidence in Beads, not a second ledger.
- Keep Rust host/library adoption, browser qualification, evaluation, retained immutable build generations, shared context imports and frontend batch-production implementation as separately scoped follow-up work.
- Follow AGENTS.md for review, spec synchronization, archive, tracker closure and release approval. Remote Beads synchronization is deferred while the observed Windows `bd dolt push` failure remains unresolved; do not run or retry it here.

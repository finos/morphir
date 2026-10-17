<a id="selected-entry-admission-policy"></a>

# Runtime capabilities and capability checks

Profile `morphir/workbench/admission`, exact version `0.1.0-draft.1`, defines
strict and permissive policies for runtime capability checks on selected public
Morphir calls. Both policies retain mandatory model, type, argument, output and
authority validation. This document states the full semantic requirements; each
evaluator, provider, UI, host mapping and packaged platform needs its own scoped
evidence before claiming support.

The profile ID, directory path and existing `admission` JSON key retain their
historical names for compatibility. The prose now uses runtime capabilities and
capability checks for unsupported-feature decisions. These terminology changes
do not rename identifiers, change wire shapes or alter policy behavior.

Capability claims are provider-authored assertions about supported behavior.
Capability verification gathers scoped contract and MCK evidence that an
implementation behaves as claimed. It is not formal proof of correctness for all
programs or business outcomes. Capability validation checks whether the chosen
runtime/provider meets the requirements of a particular run, selected function
and model revision, before or as execution proceeds under policy. Model, type, argument, output,
receipt and authority validation retain their ordinary meanings.

The independently versioned [MCK draft.11 witness](../../draft.11/README.md)
qualifies only the selected-boundary and unused-declaration slice. Full
untaken/taken branch semantics and policy-aware terminal validation require a
separate, complete, later exact MCK kit before capability advertisement. Frozen
MCK, jobs, native, HTTP and Rust protocol versions are not extended by this
profile. A profile version, test-transport version, evaluator selection and
host/native mapping version are separate identities.

<a id="closed-selection-and-defaults"></a>

## Capability validation policy and defaults

An explicit [selection](schemas/selection.schema.json) is:

```json
{
  "profile": "morphir/workbench/admission",
  "contractVersion": "0.1.0-draft.1",
  "policy": "permissive"
}
```

The only policies are `strict` and `permissive`. Exact drafts, profiles, fields,
scalar kinds and runtime selections are checked before planning. Unknown values,
adjacent drafts and build suffixes reject. A mapping may define omitted selection
as strict; the mapping must say so explicitly. Resolve that default once before
planning. Explicit permissive never silently falls back to strict or to another
runtime. An existing strict-only mapping continues to reject added members.

Policy is independent of source language. A frontend participates by producing
accepted IR with a supported selected boundary. Scheme interpreter qualification
does not imply generated JavaScript, Wasm or native execution or broader SDK
support. Capability verification evidence is scoped to the actual
evaluator/provider, selected public boundary and exact profile. A global
permissive flag cannot establish that scope.

Strict policy retains the existing whole-library capability checks before
execution. Permissive policy may defer unsupported-feature decisions for unused
definitions and check represented unsupported operations when they are reached.
Both retain the mandatory validation and execution-order requirements below.

## Invariants before any deferral

Read and bound the entire original source, including dormant declarations and
branches. Preserve accepted IR versions and grammar, envelope integrity, duplicate
member/declaration/name/identity rejection, unambiguous lookup, metadata ownership,
and source snapshot retention. A represented unsupported semantic operation may
be deferred. Malformed source, ambiguous authority, parser failures and exhausted
structural budgets may not be recovered as deferred operations.

Resolve selected entries from actual IR and public visibility. A caller-supplied
manifest never grants entry authority. Validate exact arity and tagged arguments.
Validate the complete selected input and output type closure, including every
constructor alternative, registry reference and recursive relationship. Function,
unsupported, private-constructor, unresolved or otherwise invalid selected
boundaries reject before execution, even for empty List, Nothing, another chosen
constructor, later failure, cancellation or model error. Finite named recursive
ADTs require bounded complete closure; generic declarations and alias cycles have
explicit supported/rejected status. Internal references do not authorize private
public calls.

Type-only boundary extraction is independent of whole-library generation.
Strict retains the existing strict generated-library plan and driver. A separate
bounded Scheme plan retains accepted original IR, selected calls, authoritative
boundary context, effective policy/profile and evaluator/provider identity. Do
not satisfy a compiled-plan API by inventing an empty generated library.

Existing global data defaults remain 4 MiB bytes, depth 128 and 100,000 values.
Selected closure has depth 64 and 10,000 shared nodes, at most 256 custom type
definitions, 256 constructors per definition, 64 constructor inputs, and 1,024
record or tuple members. Existing tagged-value depth 64, 100,000 value-node,
integer, Decimal, Float64, UTF-16, identity and collection bounds apply unchanged.
A mapping must also state its whole-source, encoded transport, argument/output,
optional-extension, terminal and message bounds; a tighter mapping applies first.
Interpreter source/manifest traversal has its own explicit budgets and may not
borrow generated-artifact size limits as a substitute.

## Deferred preparation and normal evaluation order

Prepare global definitions on demand while preserving canonical identity and
original source. Separately lower known unsupported expressions to bounded traps
at their original evaluation positions. Lazy global preparation alone does not
solve an unsupported operation inside an already loaded function's untaken
branch. Trap generation does not catch arbitrary parser, generator, provider,
resource or build failures.

Preserve the evaluator's order and laziness. Untaken conditional and supported
short-circuit branches do not execute. Fully applied `and` and `or` keep their
existing special short-circuit behavior; first-class and partially applied calls
keep normal application semantics. Operator evaluation, eager arguments, eager
local let/letrec right-hand sides and pattern guards execute in their normal
order even when a name or resulting value is unused. Creating a lambda does not
execute its body.

Constructor metadata needs bounded on-demand preparation too. An unrelated
unsupported constructor must not fail through eager registration after value
bodies become lazy. This does not waive complete selected boundary closure or
constructor arity limits.

Native and external operations require existing host-authorized bindings.
Candidate order, target and arity checks stay deterministic. An available chosen
native implementation may leave an unsupported fallback dormant. Failure of that
invoked native never retries the fallback. An absent authorized binding keeps its
binding failure. Policy creates no filesystem, process, network, native callback
or provider authority.

File preparation and invocation share one active runtime budget: 1,000,000 steps,
depth 128 and 100,000 frames in the bounded typed Scheme evaluator. Thunks,
recursive or nested calls, metadata preparation and traps do not reset those
budgets or bypass cancellation. Dormant source and planned traps remain charged
to structural traversal budgets. No elapsed time or fixed yield count substitutes
for semantic execution state.

## Reached failure and captured-context publication

Only an actually reached, explicitly represented unsupported semantic operation
uses this terminal cause:

```json
{
  "status": "failed",
  "failure": {
    "stage": "evaluate",
    "code": "execution.unsupported_reached",
    "message": "Unsupported operation reached"
  }
}
```

The fragment describes the semantic terminal cause, not a new frozen receipt
shape. Missing bindings, wrong types, malformed input, exhausted budgets,
unavailable providers, crashes and build failures retain their own classes.
SDK model errors remain enumerated model errors. Ordinary typed `Result.Err`
remains returned data. Unsupported execution is never a dummy value, SDK model
error or successful `Result.Err`. MCK report `unsupported` means a missing
capability claim; it is distinct from this reached runtime failure.

Validate actual returned values and every terminal against the immutable validated
selected boundary. Check ordered call identities, exact call count, extensions
and independent cleanup causes. Failed/cancelled evidence never excuses a bad
selected boundary. Reuse unchanged tagged-value and terminal-envelope codecs;
do not pass the original permissively deferred declaration graph to frozen
whole-manifest `validate-outcomes`, then ignore its rejection. Completion needs a
new validation path that checks the captured context under the selected
capability policy.

Stable diagnostics contain bounded codes and existing bounded human messages,
without source text, private paths, stack traces or secrets. Preserve primary and
cleanup failures independently. Completed effects remain accounted for when a
later operation fails; this policy promises no rollback.

<a id="immutability-and-qualification-gates"></a>

## Immutable selection and capability verification

Freeze source, selected entry, tagged arguments, validated boundary context,
effective exact policy/profile and evaluator/provider once at submission. The
same selection must reach actual planning, job state, claim, execution and
completion-time replanning/validation. Edits, restored drafts, reconnects,
capability refreshes and provider replacement cannot mutate accepted work.
Replanning copies the accepted selection into a fresh plan identity or rejects
an incompatible provider. Query, cancellation and release do not replan or
execute again. Preserve once-only claims and uncertain-submission behavior.

Before capability advertisement, verification must gather scoped evidence by
running an implementation against independent complete fixed expectations for unused/reached operations; paired branch and evaluation-order
cases; all selected closure alternatives; native candidate/fallback behavior;
wrong/malformed/oversized outputs; exact scalar and JSON/Ion argument controls;
terminal inventory, cancellation, primary/cleanup failures; and immutable policy
propagation through the actual claimed execution boundary. Controlled completion
or receipt replay alone does not prove a worker honored the policy.

A later exact host/native mapping must define its closed selection, offer and
accepted-policy echo, capture authenticated authority and actual provider, and
qualify real end-to-end execution before advertisement. Existing native/HTTP
draft.1 and Rust protocol v1 stay strict. A real TypeScript gateway test establishes
that gateway's behavior only. Actual worker/process evidence, generated backends,
and each packaged OS/architecture retain separate qualification requirements.

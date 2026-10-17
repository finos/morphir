# Runtime capability policy corpus

This exact `0.1.0-draft.12` kit contains 182 fixed cases for
[`run-capability-policy`](../../draft.12/README.md): 87 production-execution cases
and 95 captured-context completion-validation cases. Drafts.1 through .11 remain
frozen. Models, source arguments, supplied completions and expected observations
are complete inline values in `cases.json`.

Expected results were authored from the accepted runtime capability policy,
existing IR/value contracts, immutable draft.11 selected controls and independently
fixed draft.5 terminal controls before comparison with the implementation. The
parent owns these expectations. They are never captured from adapter output.
The runner sends no case IDs, manifests, expected results or adapter verdicts.

The corpus covers:

- Original selected-boundary, unused declaration, strict-policy, public-entry,
  identity, malformed-source, complete recursive/custom closure, constructor,
  argument and structural-budget controls, expressed in the new mapping.
- Paired untaken/reached Hole branches; fully applied Boolean short circuit versus
  first-class/partial eager procedure calls; eager let/letrec values and arguments;
  uncalled functions and lambda bodies; ordinary missing-reference failures.
- Production missing native/external authority versus dormant references. Native
  registered-candidate/fallback behavior requires separate direct-backend evidence;
  these fixtures grant no binding or provider authority.
- Exact JSON/Ion argument scalars, signed zero, semantic Decimal values and
  integers beyond JavaScript's exact-number range; actual wrong output and shared
  runtime recursion budget; pruned versus retained oversized constructor metadata.
- Full typed terminal variants, ordered/missing/extra/duplicate/swapped calls,
  extensions, primary/cleanup separation, failure and SDK error inventories,
  contradictory fields, exact output values, malformed JSON/Ion, UTF-16 and output
  value limits through the actual immutable plan context.
- Failed/cancelled supplied evidence cannot waive invalid selected types or any
  unselected alternative in the complete boundary closure. Supplied cancellation
  does not execute even a selected body whose unsupported operation would be reached.

Every observation states `mode: "execute"` or `"validate-completion"`. Supplied
completion cases deliberately use Hole bodies: they verify validation without
execution, not a producer's execution, live cancellation or disposal. Actual
production cases have no `completion` and must execute the retained selected plan.
Both paths use its real boundary, captured calls and policy accessor.

Interpreter budgets and typed/encoded output limits do not bound every opaque
SDK allocation or internal loop. String.repeat may allocate before result
validation. These cases establish the stated interpreter and publication checks;
they do not establish hard process-memory or CPU quotas for arbitrary programs.

A qualified report is scoped evidence for this fixed inventory. It does not
advertise jobs, workers, providers, UI, host/native negotiation, generated targets,
tree shaking or packaged-platform support.

SDK allocation and cancellation hardening is tracked separately as `morphir-be5t`, discovered from `morphir-etg2.16.2`.

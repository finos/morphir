# Native client corpus

This is the exact, offline **`0.1.0-draft.17`** corpus for `run-native-client`.
Its 48 fixed scenarios run through the existing shared Rust MCK. No expected
results or case IDs reach the adapter. See the [contract](../../draft.17/README.md)
for input validation, canonical observations and qualification limits.

The scenarios cover:

- Lost submit without automatic resubmission; all six portable native error
  codes with both `none` and `unknown` effects; malformed native replies.
- Exact Int 42 results with JSON and Ion argument text; lost-query recovery for
  the same identity; refusal after session/provider changes.
- Cancellation before acknowledgement and before terminal delivery, old cancel
  completion after a newer execution, receipt replay/conflict/snapshot correlation,
  terminal release effects, and preserving results despite cleanup failure.
- Disposal during held query or session open, rejection of work after disposal,
  and changed session authority preventing submission.
- JSON, Ion text and Ion binary workspace imports; exact two-chunk offsets;
  picker cancellation, revoking late grants, lost open/read replies, pending
  release before reuse, sequence/offset rejection, held-open cancellation,
  and inspector failure without an accepted import artifact.

## Concrete immutable assets

Every asset is inline in `cases.json`; there are no implicit file reads, URLs,
or generated golden results. The complete v4 Library model defines public
`client:main#answer`, with zero arguments and an Int literal 42. JSON arguments
are `[]`; the Ion case preserves `$ion_1_0 [ ]` verbatim.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| JSON model | 327 | `182c669da17782e3faaa6532e32df8c369896f7284ede83dcc76426c9087a6ea` |
| Ion pipeline text | 469 | `a437ea16dfb38fcb8a66adf5ed5d582f6ccf22b205618332cbeb3246969e80d0` |
| Ion pipeline binary | 440 | `ae10c34be8ec0e4ea38188db6d1cba49d5f50aed1400f7fd4c7e22a26b0f57a5` |

Ion assets contain the complete model in a `morphir_pipeline` annotation with
profile `morphir-pipeline-v1`, contract `ir-unit`, and unit ID
`native-client-fixture`. The large JSON asset prefixes 196,608 ASCII spaces to
the 327-byte model, requiring two transfers at offsets 0 and 196,608. Adapters
must separately validate all four assets through production import/evaluation,
with fixed expected result Int 42.

Host/session/provider, execution/snapshot and workspace grant/project tokens are explicit
fixture identities. Controlled delivery does not establish authenticated host,
window, picker or filesystem authority. The suite tests the client; native owner
lifecycle and packaged platform acceptance remain separate work.

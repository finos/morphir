# Native reply corpus

This parent-owned offline kit selects exact Workbench MCK `0.1.0-draft.8`:
`validate-native-reply`, JSON only. Its 185 fixed cases qualify production raw
response decoding for unchanged native profile `0.1.0-draft.1`. Historical kits
remain unchanged and qualify separately. Expected results are authored from the
published contract, independently of adapter observations.

The corpus contains 58 admitted replies and 127 decoder rejections:

- `schema-000` through `schema-096` preserve all 97 published response structural
  fixtures. Captured operation/session context is explicit. Structural validity
  is not runtime admission: `schema-096` rejects duplicate project IDs with
  different metadata, as the published runtime requirement specifies. An unknown
  successful operation rejects as `native.reply.operation`.
- Every portable native error code is admitted with both `none` and `unknown`
  effects, without including its private message in observations.
- Raw cases cover invalid UTF-8, BOM, whole-value consumption, decoded-name
  duplicates, closed shapes, and literal objects resembling library internals.
- Correlation cases cover all thirteen operation mismatches, captured sessions,
  descriptor offer/session disagreement, submission identity/receipt agreement,
  initial receipt sequence/state/cancellation, and null session captures.
- Boundary cases include exact/excessive 1 MiB replies and 512 KiB picker
  replies, byte-limit precedence over UTF-8, depth 64, 100,000 value nodes,
  exact decimal integer spellings, fractional and underflowed integer fields,
  Unicode code-point message limits, and canonical padded base64 chunks at
  the 262,144-character limit. Empty unfinished chunks reject.

Every source and bounded generation recipe is inline. `cases.json` is the whole
hash closure, including original whitespace; no external assets are consulted.
The runner validates fixture infrastructure but never parses native source.
Replay tests establish runner/report handling only. Actual qualification requires
an adapter calling its production decoder, followed by independent report check.

See the [exact contract](../../draft.8/README.md) for input, projection, stage
precedence and excluded lifecycle/platform claims.

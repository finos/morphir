# Native request frame corpus

This independent offline kit selects exact Workbench MCK `0.1.0-draft.15`:
`validate-native-frame`, JSON only. Its 140 fixed cases exercise the current
`morphir/workbench/native` `0.2.0-draft.1` request decoder. Historical kits remain
unchanged. Only explicitly supported current versions can qualify with the current
runner. Parent-owned expectations never reach the adapter.

The corpus promotes the 16 published raw rejection expectations into executable
inputs, includes all 78 published structural request cases and valid
counterparts for all 13 operations, and adds exact/excessive frame, depth and
node boundaries, strict UTF-8, BOM preservation, nested whole model/JSON argument
consumption, decoded-name duplicates and UTF-16 identity bounds. Generic model
and argument payload acceptance and opaque Ion source deliberately demonstrate
that frame acceptance does not imply IR/function/value/Ion validation.

Every source and bounded generation recipe is inline. `cases.json` is the full
hash closure; no adapter may read external assets to construct an input. The
shared runner bounds and validates compact envelopes but never parses native
sources or calculates expected behavior. Tests replaying these observations
qualify runner/report handling only.

See [the exact contract](../../draft.15/README.md) for decoder stage precedence,
compact input validation, stable observations, limits and excluded authority,
lifecycle and packaged platform claims.

The current corpus explicitly refuses the previous native version and the old
`job.query` operation. These are breaking contract checks, with no translation.

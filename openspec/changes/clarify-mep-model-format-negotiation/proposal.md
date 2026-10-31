# Proposal

## Why

The MEP `0.2.0-draft.1` model transport text said which tuples a session can
use, but not which tuple is the default, what a required format is, or which
outcomes are errors. finos/morphir-moonbit#281 asked whether the MoonBit CLI
must fail early when a guest does not support the Ion default, although the
host also supports JSON. finos/morphir-gleam#31 shows that a host which offers Ion first
and JSON second can compile with the morphir-gleam 0.4.0 guest on JSON. Damian
Reeves decided the rule on 2026-10-30 and 2026-10-31. This change records it as
a durable capability.

## What Changes

- Host offer order is preference order. The first tuple for each operation is
  the host's default. No wire member names the default.
- The extension selects the intersection of its support with the host offer and
  keeps the host order. The host uses the first agreed tuple.
- A host that requires one format offers only that tuple for the operation.
- An empty agreement for a requested operation is the only negotiation failure.
  The host reports `extension.tuple_unavailable` and sends no request. A
  missing host default with another agreed tuple is not an error.
- For `morphir.backend.generateModel`, a host that can convert a model to an
  agreed tuple converts it and sends the converted model. The host prefers a
  lossless conversion: it converts to the first agreed tuple in host order
  that it can reach without loss. Only when no agreed tuple is lossless does it
  select the first agreed tuple to which it can convert. Guarantees and
  evidence for the original do not carry over automatically.
- A lossy conversion is refused with the host's lossy-conversion error, not
  `extension.tuple_unavailable`, unless the user explicitly allows loss for
  that one operation. When loss is allowed, the host reports the dropped data.
- The converted model keeps its `modelId` and has its own digest and a
  deterministic revision derived from the converted payload digest. The host
  keeps a conversion record that links the converted model to the original, and
  an extension artifact must not overwrite it. The host publishes nothing from
  a result in which an extension artifact uses the conversion record path; the
  error code and exit status are host-defined.
- No new wire member. No change to the `0.2.0-draft.1` version.

## Capabilities

### New Capabilities

- `mep/model-transport-negotiation`: how a MEP host and extension agree on the
  model transport tuple for each model operation, which tuple the host uses,
  and when the host converts a model for generation.

### Modified Capabilities

None. `openspec/specs/` has no capability for MEP model transport.

## Tracking

- Bead `morphir-1q2c` owns this change and the spec text.
- Bead `morphir-hv6m` owns the MCK cases and runner support (related to
  `morphir-1q2c`).
- Pull requests finos/morphir#1115 and finos/morphir#1117 (the
  host-conversion decisions of 2026-10-31).
- Evidence: finos/morphir-gleam#31. The same rule is written for the MoonBit CLI
  in finos/morphir-moonbit#281.

## Impact

- `spec/mep/model-transport.md`: sections "Offer order and the default tuple"
  and "Host conversion for generation".
- Doc comments in `spec/mep/contract/src/mep.gleam` and the generated
  `spec/mep/generated/mep.ir.json`, the Smithy comments in
  `spec/mep/smithy/model/`, the wire-rule table in `spec/mep/README.md` and the
  protocol draft `docs/design/draft/extensions/protocol.md`.
- Hosts that refuse an extension when the default is not agreed must change.
  The MoonBit CLI change is in finos/morphir-moonbit#281. The Rust SDK already
  keeps host order when it selects.
- No change to wire shapes, JSON-RPC error numbers or SDK types.

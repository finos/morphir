# Proposal

## Why

Damian Reeves asked for 5,000,000,000 instructions for each WASM guest call on the model line. The model line had
2,147,483,647, the largest budget that `moonrockz/extism` 0.1.1 accepted, because WAMR held the count in a C `int`.
`moonrockz/extism` 0.3.0 counts in a 64-bit integer and accepts every positive `Int64` budget, so the host can now
give the larger budget.

## What Changes

- `pkgs/morphir-host` moves from `moonrockz/extism` 0.1.1 to 0.3.0.
- A WASM call on the model line has 5,000,000,000 instructions. MEP `0.1` and a probe keep 1,000,000,000. The call
  deadlines of 10 and 30 seconds do not change.
- `Limits::call_instructions`, `CallBounds.instructions` and the native worker's `--instructions` are `Int64`, from 1
  to 9,007,199,254,740,991 (2^53 - 1, `max_call_instructions`).
- `Limits::new` refuses a budget outside that range with `InvalidLimit`. The worker mode refuses `--instructions`
  outside it, or in a form other than decimal digits, with a usage error that names the range.
- The extension guide, the worker READMEs and the opt-in guest-cost measurement give the new budget.

Out of scope:

- The engine. `moonrockz/extism` 0.3.0 has the 64-bit counter (its change `widen-instruction-budget`).
- New measurements of the guests at 5,000,000,000. The guide says that its table was measured at 2,147,483,647.
- A budget on the Node and browser hosts. Their engine does not meter instructions, as before.
- A validated budget type shared by `Limits`, `CallBounds` and the worker parser.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extensions/wasm-workers`: the requirement "Per-call budget" gets the budget of 5,000,000,000 on the model line, the
  range 1 to 9,007,199,254,740,991 and two scenarios.

## Beads

- **Tracked by**: `morphir-ukvn.5.64.36.33`, spec id `openspec/changes/raise-model-line-instruction-budget`, label
  `repo:morphir-moonbit`.
- **Related**: `morphir-ukvn.5.64.36.26` (the first model-line budget), `morphir-ukvn.5.64.36.29` (the portable guest
  is linear in the number of values), `morphir-ukvn.5.64.36` (parent epic).

## Impact

- **Code:** `pkgs/morphir-host/worker` (`limits.mbt`, `negotiation.mbt`), `worker/wasm/guest/guest.mbt`,
  `worker/wasm/native/worker_mode.mbt`, their tests, and `pkgs/morphir-host/moon.mod`.
- **API:** `Limits::call_instructions` and `Limits::new(call_instructions?)` are `Int64`; `max_call_instructions` is
  new; `CallBounds.instructions` and `CallBounds::new(instructions~)` are `Int64?`.
- **Dependencies:** `moonrockz/extism` 0.3.0, which requires MoonBit 0.10.20, as the workspace does.

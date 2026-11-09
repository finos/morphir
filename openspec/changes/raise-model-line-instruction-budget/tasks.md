# Tasks

Damian Reeves approved the work on 2026-11-08 and the range on 2026-11-09. Read [design.html](design.html) and
[the spec](specs/extensions/wasm-workers/spec.md) first.

## 1. Model-line budget of 5,000,000,000 instructions (morphir-ukvn.5.64.36.33)

- [x] 1.1 Write the failing tests: the "Budget range" scenario for `Limits::new` on native, js, wasm and wasm-gc and
  for `--instructions`; the call bounds of the model line; the engine budget from `CallBounds` on native and js; a
  worker with `--instructions 3000000000`; and the end-to-end runaway test of each ABI at 2,147,483,648
- [x] 1.2 Move `pkgs/morphir-host` to `moonrockz/extism` 0.3.0, and make `Limits::call_instructions`,
  `CallBounds.instructions` and `--instructions` `Int64` from 1 to `max_call_instructions`; verify the "Budget above
  2^31" and "Budget range" scenarios
- [x] 1.3 Update the extension guide, the worker READMEs, the guest-cost measurement and the worker interface

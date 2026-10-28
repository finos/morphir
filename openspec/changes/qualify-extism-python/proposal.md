# Qualify Python Extism support in the MoonBit CLI

## Why

The existing finos/morphir-python WASM bundle can compile Python to Morphir IR and generate Python through Extism, but the MoonBit CLI's `core-wasm-process` binding is a different ABI and protocol route. Users need an explicitly selected, independently qualified route before documentation can claim Python extension support in this CLI.

## What Changes

- Add an opt-in `extism-wasm` binding for `morphir extension describe|compile|generate`, using the shared Rust host libraries behind the existing supervised native-services boundary. Keep existing bindings and default selection intact.
- Qualify Python's MEP `0.1` describe, legacy compile and generate methods. Require a corrected bundle advertising `multiDocument` for multi-module compilation; refuse multi-module requests to 0.4.1, whose claim omits it. Support its declared IR `3` and `4` JSON forms, with explicit version selection and checked file interchange; refuse unsupported envelopes, codecs and rich-model requests.
- Verify pinned host, helper/runtime closure, descriptor and WASM bytes before execution. Validate identity and capabilities at discovery and initialization without treating publisher claims as authentication or installation as runtime qualification.
- Enforce finite execution, memory, input/output and publication limits; preserve structured guest diagnostics and expose structured refusals through the CLI's `--json` contract.
- Qualify real Python bundles through source and packaged CLI entry points on a bounded native-host matrix. Document exact versions, receipts, offline replay, limitations and copyable workflows, linked to the Python documentation proposal.

## Capabilities

### New Capabilities

- `extensions/extism-execution`: Explicit, bounded and digest-pinned Extism invocation, including MEP/IR compatibility, Python bundle qualification and truthful support documentation.

### Modified Capabilities

None. No main OpenSpec capabilities exist in this checkout. Existing portable and native-process contracts remain unchanged.

## Beads

- **Tracked by**: `morphir-ukvn.5.98`, spec id `openspec/changes/qualify-extism-python`, label `repo:morphir-moonbit`.
- **Related**: `morphir-ukvn.1.6` owns the migrated Python compiler/bundle; `morphir-ukvn.5.64.4` and `.5` supply native invocation and local distribution; `morphir-ukvn.5.64.30` separately qualifies installed native invocation. These are context links, not new blockers.
- **Python docs intent**: `morphir-ukvn.9`, [finos/morphir-python](https://github.com/finos/morphir-python) `openspec/changes/add-documentation-site`, inspected locally on `docs/propose-documentation-site`. A shared relates-to edge connects both epics. The site can describe current refusals without waiting for this adapter.

## Impact

Future implementation touches `apps/morphir/extension.mbt`, `native_services.mbt`, `native-services/`, `build-provider/`, focused extension tests, packaging/qualification tasks and `apps/morphir/docs/extension.md`. It reuses pinned finos/morphir host, SDK and distribution libraries; any required shared Extism policy API change must land upstream and be repinned. It does not invoke the Rust product CLI, rebuild the Python compiler, add an Extism runtime to MoonBit, or claim Component Model/browser support.

The original proposal was planning-only. The maintainer subsequently approved implementation and landing, then explicitly authorized a corrected Python release in a separate workspace. Automatic installed selection, general WASM repository lifecycle, top-level language routing and new recurring CI jobs remain outside scope. Proposal validation is not a runtime qualification receipt.

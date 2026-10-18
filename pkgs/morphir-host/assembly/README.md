# Assembly planning

`finos/morphir-host/assembly` is a pure dependency planner for a supplied library
assembly set. It validates the selected root and every supplied package, including
packages whose code a later link may remove. It does not acquire files, invoke a
compiler or grant a runtime capability.

`PackagePin::new` accepts an exact package path and a lowercase SHA-256 content
identity. Paths preserve their spelling and contain nonempty slash-separated
ASCII letter/digit/underscore/hyphen segments. `Dependency::new` pairs a local
import name with that exact pin. It checks identifier spelling; compiler keyword
and source semantics remain the compiler's responsibility. Different packages
may use different import names for the same dependency.

`Package::new` snapshots and normalizes dependencies. `plan(root, packages)`
refuses duplicate package names/import names, missing or mismatched pins and
cycles. Errors distinguish a selected root, the supplied assembly and a dependency
of a particular package through `Referrer`. Cycles retain the exact pin path.
The resulting opaque `Plan` exposes dependency-first packages exactly once and
retains the selected root. Accessors return array copies; callers cannot mutate
the validated snapshot. Traversal uses an explicit stack rather than recursive
calls.

A pin is supplied identity data, not evidence that any bytes match it. Subsequent
asset providers must verify bytes and compiler/core/SDK/target compatibility.
Registry version solving, compilation/linking, retention roots, Ion manifest
codecs, publication and fresh-host invocation belong to the following components.
This package establishes no new MorphirModel guarantee and no MEP/MCK conformance
claim.

The HTML implementation specification is stored in the design field of
`morphir-ukvn.5.55.7.1`, Task 1. Retrieve it with the beads companion. The owning
research report is `morphir-ukvn.5.55.7`, revision 0.8.

```console
moon test -p finos/morphir-host/assembly --target js
moon test -p finos/morphir-host/assembly --target native
moon test -p finos/morphir-host/assembly --target wasm
moon test -p finos/morphir-host/assembly --target wasm-gc
```

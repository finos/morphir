# Experimental V3 semantic rules

This package begins a Morphir-authored semantic specification for Morphir IR
version 3. The logical package identity is `morphir/ir-specification`; this
initial source revision is the bounded arity pilot, not the complete V3
specification. `cases/arity.json` fixes five expected results independently of
the compiler and evaluator. `Unit` denotes the V3 `Type.Unit(Nil)` value.

The type model is copied from `examples/gleam/ir-v3` at the start of the pilot.
That fixture was established in #880. It uses nominal record wrappers and
string-backed `Char` and `Decimal` representations. Those fidelity limits do
not affect the first arity rule, which counts type arguments after a declaration
has been resolved. Reference resolution, locations, and whole-IR validation
remain later rules.

The Gleam compiler's V3 executable mode retains supported function bodies with
inferred types. It requires an explicit `morphir/SDK` dependency specification
for imported SDK types; an absent or incompatible interface fails compilation.
Unsupported value forms also fail this mode instead of producing a partial
executable package. `typesOnly` still omits values with a diagnostic. The five
literal results here are independent expectations; execution of the compiled
rule and a separate hand-authored runtime vector remain implementation work.

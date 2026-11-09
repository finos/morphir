# Morphir MoonBit bindings

`finos/morphir-moonbit-bindings` reserves the module boundary for Morphir's
MoonBit foreign function bindings. This version has no public binding
functions. Its initialization test verifies that the module loads; it does
not establish an FFI or WebAssembly integration contract.

The module declares dependencies on `finos/morphir-core` and
`finos/morphir-sdk`. Applications that need Morphir compilation or execution
should use the corresponding frontend, compiler or engine modules.

Licensed under Apache-2.0. See [LICENSE](LICENSE).

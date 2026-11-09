# Morphir core

`finos/morphir-core` provides the names used to identify Morphir definitions.
Import `finos/morphir-core/ir/classic` for `Name`, `Path`, `PackageName`,
`ModuleName`, `QName` and `FQName`. A name stores words independently of their
display style, so the same name can be rendered in camel case, title case or
snake case. Paths and qualified names compose those names into definition
identities.

Add the module to a MoonBit project with `moon add finos/morphir-core@0.1.0`.
Declare `finos/morphir-core/ir/classic` in the consuming package's imports.
The module contains pure MoonBit code and uses the standard core library.
It does not load configuration, access files or start a runtime.

The IR data model and its codecs live in the separate `finos/morphir-ir`
module. This module supplies shared naming types rather than a complete IR.

Licensed under Apache-2.0. See [LICENSE](LICENSE).

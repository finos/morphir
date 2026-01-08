---
id: morphir-ir
sidebar_position: 4
---

# The Morphir IR

The `Morphir.IR` module defines a type-safe API to work with Morphir's intermediate representation. The module
structure follows the structure of the IR. Here's a list of concepts in a top-down approach:

- [Distribution](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Distribution) is the output
  of `morphir-elm make`. It represents a whole package with all of its dependencies.
- [Package](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Package) represents a set of
  modules that are versioned together.
- [Module](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Module) is a container
  to group types and values.
- [Types](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Type) allow you to describe
  your domain model.
- [Values](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Value) allows you to
  describe your business logic.
- [Names](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Name) provide a naming
  convention agnostic representation for all nodes that can be named: types, values, modules and packages. Names can be
  composed into hierarchies:
    - [path](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-Path) is a list of names
    - [qualifield name](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-QName) is a module path with a local name
    - [fully-qualifield name](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-FQName) is a package path with a qualified name
- [AccessControlled](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir-IR-AccessControlled)
  is a utility to define visibility constraints for modules, types and values  
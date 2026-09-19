# Morphir V3 defined in Gleam

This project describes the complete V3 **IR data model** as Gleam type declarations
and compiles that description into Morphir V3 IR. It exercises recursive and
mutually recursive ADTs, generics, labelled records, aliases, SDK containers and
cross-module references. It does not implement an evaluator, compiler or JSON codec.

Run the executable example from the repository root:

```sh
mise run test:examples -- --filter gleam/ir-v3
cargo test --locked -p morphir --test gleam_dogfood
cargo test --locked -p morphir --test gleam_dogfood -- --include-ignored
```

The last command requires Gleam and access to the pinned `gleam_stdlib` dependency.
It type-checks both the original source and the generated modules using the real
Gleam compiler. Ordinary CI checks the complete generation goldens and recompiles
the output to verify that type bodies and access levels survive unchanged.

## Model inventory

| Module | Definitions |
| --- | --- |
| `name`, `path`, `qname`, `fqname` | Names, paths and qualified names |
| `access_controlled`, `documented` | Access levels, access-controlled values and documentation |
| `literal` | All six V3 literal variants |
| `type_` | All seven type variants, fields, constructor argument lists, constructors, the four specifications and two definitions |
| `value` | All eight patterns and 18 value variants, raw and typed values, specifications and definitions |
| `module`, `package` | Module/package names, specifications and definitions |
| `distribution` | Library name, dependency specifications and typed package definition |

There are 30 named types across 12 modules. V4-only constructs, including holes
and document literals, are intentionally absent. `LetRecursion`, `UpdateRecord`
and `ExtensibleRecord` describe IR nodes as data; defining these variants does
not require executing the corresponding operations in Gleam.

## Representation and fidelity

- Gleam records are labelled, single-constructor ADTs. They retain the information
  in Elm record aliases but compile as nominal custom types, not structural records.
  `QName` and `FQName` likewise use the existing Gleam model's labelled products.
- Characters and decimals retain the existing Gleam model's string payloads.
  Decimal strings avoid conversion through floating point. These declarations
  alone do not validate a single Unicode scalar or decimal syntax, and do not
  map those payloads to Morphir SDK `Char` or `Decimal` types.
- `Dict`, `Option`, lists, primitive scalars and `Nil` map to their supported SDK
  identities or unit. `Type`/`Field` and `Value`/`Definition` are mutually recursive.
- This is an abstract model, not the V3 wire codec. It does not enforce wire-level
  name constraints or add a `formatVersion` field to the model's `Distribution`.
  The compiled artifact itself is a V3 library with `formatVersion: 3`.

## Provenance

The type declarations are adapted from
[finos/morphir-gleam at aa2b7e2](https://github.com/finos/morphir-gleam/tree/aa2b7e2377b13ef1af48d9a3a30bec797015933c/packages/morphir_models/src/morphir/ir),
with functions and unused imports removed. `Constructor`, `RawValue`, `TypedValue` and the V3
`Distribution` complete the model using
[the Elm definitions at b065e49](https://github.com/finos/morphir-elm/tree/b065e493d7a4256ed47878b129abf2333e977313/src/Morphir/IR).
The repository's [V3 schema](../../../website/static/schemas/morphir-ir-v3.yaml)
defines the wire contract. This frozen example is maintained separately from the
Gleam implementation so the integration test does not depend on that submodule
being initialized or silently change with its implementation.

# Morphir SDK specification

`finos/morphir-sdk-spec` gives the Morphir IR specification of the Morphir SDK:

- `sdk_package_name()` is `morphir/SDK`.
- `sdk_specification()` is its `@ir.PackageSpecification`: 248 values in 11 modules, with the SDK types and
  constructors. The module `local-date` has only the opaque type `local-date`.

Type inference (`finos/morphir-typing`) has no built-in SDK. Callers add this specification to its dependencies:

```moonbit
let deps = Map::from_array([
  (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
])
```

The module depends only on `finos/morphir-ir`. It builds and tests on `wasm`, `wasm-gc`, `js` and `native`.

## Why a separate module

The runtime SDK, [`finos/morphir-sdk`](../morphir-sdk/README.md), must have no dependencies. Generated MoonBit
libraries compile against it alone, in a frozen workspace that holds only the audited SDK module. The
specification needs `finos/morphir-ir`, so it lives here.

## `sdk.scm` is the source of truth

[sdk.scm](sdk.scm) holds the specification in the Morphir Scheme specification notation (see the
[Morphir Scheme README](../morphir-scheme/spec/README.mbt.md#the-notation)). Edit `sdk.scm` by hand. Do not edit
`sdk_data.mbt`. It is generated canonical v4 JSON of a `Specs` distribution, which the package decodes once, on
first use.

```sh
mise run sdk-spec:generate   # regenerate sdk_data.mbt from sdk.scm
mise run sdk-spec:check      # check sdk.scm against bindings.json, and check that sdk_data.mbt is fresh
```

Both tasks run the native `sdkgen` tool of `finos/morphir-typing-tools`. The signatures to check against are in
[`pkgs/morphir-sdk/conformance/bindings.json`](../morphir-sdk/conformance/bindings.json). `sdk-spec:check` fails
when:

- a `bindings.json` signature is missing from `sdk.scm`, or `sdk.scm` has a value that `bindings.json` lacks;
- a parameter name differs, or a type differs up to a renaming of type variables;
- `sdk_data.mbt` is not what `sdk-spec:generate` would write.

The renaming pairs two variables only when they have the same constraint class. A variable's class comes from its
`typeclass` constraint, else from its name prefix (`number`, `comparable`, `appendable`, `compappend`). So `number`
in `bindings.json` against a plain `a` in `sdk.scm` is a difference. The comparison ignores other attributes.

## Names

Names in `sdk.scm` are migrated canonical names, such as `map-2`, `from-int-8` and `LT`. The check maps each
`bindings.json` name with the same rule as the Elm mapping generator: it splits camel case and digit runs, then
applies the `Name::from_words` initialism rule.

## Duplicate parameter names

The IR refuses two parameters with one name, but some morphir-elm signatures have them: `Result.map3`, `map4` and
`map5` have `result2` twice. A repeated parameter name takes the next free number, so `result-1`, `result-2`,
`result-2` becomes `result-1`, `result-2`, `result-3`. The bootstrap and the check use the same rule, so these
three values have parameter names that differ from `bindings.json`.

## MoonBit source String extension

`source_string_package_name()` and `source_string_specification()` expose the
separate `morphir/moonbit-source:string` package with `require-valid` and
`append-bounded`. Their explicit runtime inventory is
`../morphir-sdk/conformance/moonbit_source_string_extension.json`, profile
`morphir-moonbit-source-string-v1`. They are compiler lowering targets, not source
imports or part of the 248 classic SDK values. String source IR carries this
specification as an explicit dependency.

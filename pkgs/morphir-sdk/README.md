# Morphir SDK for MoonBit

`finos/morphir-sdk` provides pure, synchronous runtime values and functions for generated Morphir programs. It has no host, filesystem, network, process, or Scheme dependency. The packages compile on native, JavaScript, wasm, and wasm-gc.

The root package defines `Order`, `SdkError`, UTF-16 `Text` and `Character`, and Elm-compatible lexical string ordering. Subpackages cover `integer`, `basics`, `int`, `decimal`, `char`, `string`, `list`, `maybe`, `result`, `dict`, and `set`. The general `Integer` wraps MoonBit core `BigInt`; `Int8` through `Int64` conversions check bounds. Lists, dictionaries, and sets return new values on updates. Dict and Set require a total Morphir comparator when constructed; use `@string.compare` for `Text` keys and `@sdk.string_order` for MoonBit `String` keys. Generic MoonBit `Compare` uses a different String order.

MoonBit 0.10.15 reserves the built-in names `Int16`, `Int32` and `Int64`. The SDK therefore represents the corresponding Morphir fixed-width types with MoonBit wrappers `int.Int16Value`, `int.Int32Value` and `int.Int64Value`. The Morphir type identities and the `from_int16`/`to_int16`, `from_int32`/`to_int32` and `from_int64`/`to_int64` functions retain their existing contracts. `int.Int8` keeps its name. Callers with explicit MoonBit wrapper type annotations must use the `Value` names.

## Sources and inventory

The binding inventory is [conformance/bindings.json](conformance/bindings.json). It contains all 248 declared values, their pinned Elm specification fragments and source lines, MoonBit bindings, semantic source, and module test paths. Regenerate it with:

```sh
python3 pkgs/morphir-sdk/conformance/generate_inventory.py --elm-checkout /path/to/morphir-elm
```

The script reads `finos/morphir-elm` at commit `bc99af69a8b24d391311fae3822a87eafef3c334` with `git show`, so the checkout can be on any branch. Behavioral references are `elm/core` 1.0.5 and `chain-partners/elm-bignum` 1.0.1. The generated Unicode case tables come from Node's Unicode 17.0 ECMAScript casing; regenerate them with `node pkgs/morphir-sdk/string/tools/generate-case-tables.mjs` using a Node release that reports Unicode 17.0.

The inventory records every typed binding and its test status. All 248 canonical names have typed MoonBit bindings and Scheme adapters. The [Elm oracle corpus](conformance/elm_oracle.json) executes 245 names in the pinned Elm runtime with 310 examples, including 65 boundary cases. `Basics.never` is uninhabited. The pinned Elm `Int64` source emits invalid JavaScript for its lower bound, so `fromInt64` and `toInt64` use the separate [exact-integer extension corpus](conformance/exact_integer_extension.json). The Scheme tests embed all 310 executable Elm examples plus 14 mathematical extension cases and run on all four targets. The [conformance recipe](conformance/README.md) records how to regenerate them and what the oracle projects for opaque values.

## Semantic boundaries

- `integer.divide`, `remainder_by`, and `mod_by` truncate toward zero and raise `SdkError.DivisionByZero` for a zero divisor. The second argument is the dividend for `mod_by` and `remainder_by`.
- `basics.divide` is IEEE Double division. Nonfinite Float to Integer or Decimal conversion raises `SdkError.InvalidNumber`.
- `decimal.Decimal` is numerical: its coefficient is exact, with a minimum arithmetic and parse exponent of −32. It does not preserve an IR decimal literal's original spelling or scale. Division returns `Option`, and rounding is half to even.
- SDK String functions take `Text`, an immutable copy of UTF-16 code units. Length and slicing count code units; traversal groups surrogate pairs as Elm characters. `split("", ...)` and slices can return isolated surrogate halves. `Text::to_string` checks that all units form valid Unicode before crossing into a MoonBit `String` host or Scheme value; it raises `SdkError.UnrepresentableText` for isolated surrogates. `Text::from_string` accepts host strings.
- `Character` stores UTF-16 units because Elm Char can hold a surrogate or a case expansion. String casing uses pinned, locale-independent Unicode 17 tables. `char.to_locale_upper` and `to_locale_lower` use the same default casing; `char.to_upper` can return `SS` for `ß`.
- `char.from_code` returns U+FFFD for out-of-range values and preserves surrogate code units, matching Elm's JavaScript kernel.
- Dict and Set comparators may raise `SdkError.InvalidComparison` for unsupported keys such as NaN. Both collections retain the comparator supplied at construction; callers must use the same ordering for values of a given key type.
- The Morphir Scheme backend installs all 248 canonical SDK names as native accelerators and curried Scheme references. Higher-order callbacks call through the Scheme runtime. Scheme's own rational `/` remains a separate language operation.

## SDK specification

The IR specification of the SDK, for type inference, lives in its own module,
[`finos/morphir-sdk-spec`](../morphir-sdk-spec/README.md). This module has no dependencies, because generated
libraries compile against it alone.

## Check

```sh
moon fmt --check pkgs/morphir-sdk
moon test --target native
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native pkgs/morphir-scheme/backend
```

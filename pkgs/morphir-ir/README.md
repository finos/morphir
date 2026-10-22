# Morphir IR for MoonBit

Typed models, JSON readers and writers, and explicit migrations for Morphir IR v1–v4. The module is `finos/morphir-ir` and runs on MoonBit's WASM, WASM-GC, JavaScript and native targets.

## Native unions

V4 `Union(attributes, alternatives)` retains order, duplicates, nesting and attributes. JSON accepts
`{"Union":[A,B]}` or `{"Union":{"attributes":{...},"alternatives":[A,B]}}`, requiring at least two authored
alternatives on read and write. Bare arrays remain Tuple; historical migration refuses Union recursively.

The v4 JSON package provides `decode_scalar_json(text, type, profile)` and
`ScalarDecoder::from(file, profile).decode(text, type)` for native Bool/String/Int/Float decoding. The contextual
decoder follows visible zero-parameter transparent aliases. Parameterized aliases, opaque/custom/derived types,
structures and runtime predicates remain unsupported. `strict-json-scalars` retains all typed interpretations;
`integer-token-as-int` maps every integral JSON number to Int, including `1.0` and `1e0`. Unknown profiles refuse.
Equal typed interpretations collapse, but Int 1 and Float 1 differ. Unknown arms prevent uniqueness; two proved
interpretations establish ambiguity. Unknown outer refinements cannot be bypassed through a member.

Limits are 16384 UTF-16 input units, 1024 JSON nodes, 64 levels and 256 type visits. Numeric values have at most
fifteen significant decimal digits and magnitude 999999999999999. Float uses finite binary64; nonzero underflow
is refused. This is a scalar codec, with conceptual membership, projection and runtime guards left separate.

## Imports

All paths below start with `finos/morphir-ir`.

| Package | Purpose |
| --- | --- |
| root | Current model, initially v4; follows the latest supported model |
| `/json` | JSON codecs for the current model |
| `/versions/v1` … `/versions/v4` | Fixed, distinct models for each major version |
| `/versions/v1/json` … `/versions/v4/json` | Fixed-version JSON codecs, including individual nodes |
| `/versioned` | `IRFile` union retaining the original version |
| `/versioned/json` | Dispatch on `formatVersion` without migrating |
| `/migration` | `to_current` and `migrate` |
| `/version` | Exact releases, recognition and support checks |
| `/common` | Names, paths, access and shared data types |
| `/wire` | Strict JSON parsing and diagnostic codes |

Example `moon.pkg`:

```moonbit
import {
  "finos/morphir-ir/versioned/json" @ir_json,
  "finos/morphir-ir/migration",
  "finos/morphir-ir/version",
  "finos/morphir-ir/json" @current_json,
}
```

```moonbit
fn upgrade(text : String) -> String raise {
  let original = @ir_json.read(text)
  let current = @migration.to_current(original)
  @current_json.write(current)
}

fn convert(text : String) -> String raise {
  let original = @ir_json.read(text)
  let converted = @migration.migrate(
    original,
    @version.FormatVersion::baseline(3U),
  )
  @ir_json.write(converted)
}
```

`read`/`write` operate on JSON text. `from_json`/`to_json` operate on MoonBit `Json`. Use the text reader at an input boundary: a pre-parsed `Json` may already have lost duplicate members or number precision. Node codecs accept callbacks for the generic attributes in v1–v3.

## Models and encoding

The models include all type expressions, literals, patterns, value expressions, type/value specifications and definitions, modules, packages and supported distributions. V4 also includes annotations, source and inferred-type attributes, holes, incomplete definitions, native/external bodies and applications. V1–v3 keep generic type and value attributes; distribution values carry their inferred types, as in Elm.

Elm is the canonical encoding authority for v1–v3. V1 uses lowercase tags, tuple documentation, tuple access wrappers and named module entries. Its derived-type specification writer uses `DerivedTypeSpecification`, matching Elm's encoder; the reader also accepts the lowercase spelling used by Elm's decoder. V2 uses capitalized type and literal tags with lowercase value and pattern tags. V3 capitalizes the remaining tags. V2/v3 documentation uses `{doc,value}` with a string doc, defaulting to `""` for unwrapped inputs. Module docs write `null` when absent. Classic dictionaries write in Elm's lexicographic word-list order.

V4 follows finos/morphir's specification. Readers accept its compact, expanded and documented legacy JSON spellings. Writers emit canonical node forms. Names retain the distinction between `SDK` and `sdk`, and normalize the classic `["s","d","k"]` spelling to `SDK`.

Integer and decimal literals retain exact text. `Data.Number` also retains the original JSON number lexeme, including values beyond host integer or floating-point ranges. Float literals use finite `Double` values.

Supported releases are historical integer v1/v2, `[3.0.0,3.2.0)` and `[4.0.0,4.1.0)`. Baseline releases write integer `formatVersion`; later releases write exact strings. V3.1 adds the `Specs` extension from finos/morphir. Syntax, unsupported major/minor versions, and family mismatches produce separate diagnostics.

## Migration behavior

Conversions between major versions use the current model. Same-major release changes preserve the original model. No reader migrates implicitly.

Migrations fail when the target cannot retain information:

- V1 cannot carry module documentation.
- Classic type/value definitions and specifications require a documentation string. Absent v4 member documentation is refused; explicitly empty documentation is preserved.
- V1/v2 cannot carry `Specs`; v3 requires release 3.1 or later.
- Classic targets cannot carry applications, holes, document literals, annotations, incomplete definitions or native/external bodies.
- Classic typed values and patterns require an inferred type; v4 source information, constraints and extensions cannot be dropped.
- Classic input annotations that differ from the declared input type cannot be moved into v4's single input type.
- Some v4 name segment boundaries cannot be represented by classic word lists.

Catch errors normally, or use `@wire.diagnostic(error)` for a stable diagnostic code. Treat migrated files as new values: no source model is mutated.

## Verification and upstream sources

The fixture suite checks upstream JSON examples for canonical output, equivalent accepted spellings, rejection diagnostics, exact number text, and migration behavior. Elm v1/v2 rentals files and a complete v3 distribution exercise real package conversions. Tests are embedded in MoonBit source so every target runs the same corpus without filesystem access.

Pins:

- `finos/morphir`: `5c5307d89f34d876e8f1ebf561ec55efbadf9fa0`
- `finos/morphir-elm`: `bc99af69a8b24d391311fae3822a87eafef3c334`
- Historical Elm v2 codecs: `1089957b161708dbf5f9b9a2d90cb7044de883e7`, before value/pattern tags were capitalized

The suite covers the JSON portions of the selected Morphir compatibility kit files. YAML, document trees, warning emission and the MCK adapter protocol are outside this module.

```sh
mise run test

# Regenerate tests from vendored fixtures.
mise run ir:fixtures

# Refresh from pinned commits in local upstream clones, then regenerate.
mise run ir:fixtures -- --morphir /path/to/morphir --morphir-elm /path/to/morphir-elm
```

Change the pins in `scripts/refresh-ir-fixtures.mbtx` deliberately when updating the corpus. Upstream fixture content is Apache-2.0 licensed; paths and provenance are recorded in `conformance/fixtures/README.md`.

V4 named input objects use canonical lexical parameter order. Ordered pair arrays
carry any other order explicitly. Writers use pair arrays when canonical object
order would change an ordered definition's parameters. This applies to function
and constructor inputs and survives deterministic JSON and Ion processing.

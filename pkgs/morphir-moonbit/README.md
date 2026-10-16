# Morphir MoonBit generator

`finos/morphir-moonbit` generates a MoonBit library from current typed Morphir IR.
It has no engine, host, filesystem, process or network imports. `generate(Input)`
returns its own `Output`, containing a project description, source/manifests,
symbols and Ion metadata. Compilation and publication belong to host stages.

The concrete library profile flattens Morphir modules into one MoonBit package.
It supports scalar and compound types and expressions described below.
Unsupported constructs, incomplete bodies, unregistered native/external
implementations, ambiguous types and contradictory inferred types fail with a
`GenerationError` carrying code, node context and detail. It emits no placeholders.

## Contracts and output

```moonbit
let input = @generator.Input::new("pricing", current_ir)
let output = @generator.generate(input)
```

`Input` carries a unit ID, current `IRFile`, node metadata, ordered annotation
tokens and rewrite provenance. Applications adapt their boundary types to this contract. The engine's
codec conformance tests exercise JSON, Ion text and Ion binary inputs against the
same generator without adding an engine dependency to the generator.

| Artifact | Purpose |
| --- | --- |
| `moon.mod` | Native module manifest with the SDK module requirement |
| `moon.pkg` | Only the SDK imports used by the generated code |
| `library.mbt` | Deterministic flattened declarations |
| `symbols.10n` | Binary Ion symbols, source identities, origins and metadata |

`Project` records the generated module name, relative root, artifact membership
and semantic dependency requirements. These requirements do not prove dependency
resolution or a successful build. The generated module name retains its encoded
package identity. Named declarations and fields use readable target spellings
under `moonbit-readable-targets-v1`. Public values in public modules produce
`pub fn`; other declarations stay private. Cross-module references require public
source declarations even though the generated package is flat.
Record shapes used by exported signatures are public; shapes used only privately
stay private. MoonBit refuses a `pub` signature or `pub` type payload that names a
`priv` type. A custom type that is not public (its module or the type is private)
but that a public signature or public type payload names is emitted abstract, with
no visibility modifier: other packages can name it, but not its constructors.

Zero-input values become accessor functions, preserving evaluation on reference
without eager global initialization. Each accessor can propagate `SdkError`.

## Naming and compatibility

`generate(input)` defaults to `Readable`. MoonBit declaration and parameter origins
are automatic spelling hints when the unit has matching MoonBit frontend provenance.
A usable original `isReady` stays `isReady`; missing or other-language origins render
the semantic name as snake case, such as `is-ready` to `is_ready`. Types and constructors
use Pascal case. Initialisms retain their case. A numeric or uppercase value name gets
a readable `value_` prefix when the target requires a lowercase identifier.

The allocator reserves every candidate before recovery. Flattened declarations with
the same candidate receive a module qualifier. Keywords receive `_value`; occupied
recovery names get a checked `_source_<token>` suffix. The token starts with four UTF-8
bytes of the semantic owner, encoded as lowercase hex, extends by one byte on collision,
and finally uses a checked decimal ordinal. Allocation is independent of map order.
Adding a conflicting declaration can change a public name, so treat it as an API change.

Every declaration reference, constructor use, field access, invocation entry and driver
uses the allocation map. Locals reserve visible generated declarations and all user
binders before fresh `function`, `argument` and `record` temporaries are allocated.
Separate functions have separate local namespaces. Lexical shadowing keeps its meaning.
Synthetic structural-record type IDs and private codec helper IDs retain their encoded
structural keys; they do not reconstruct user declarations.

`Output.naming_allocations` records semantic owners, roles, original hints, exact requests, candidates,
final spellings and allocation reasons. `Output.warnings` carries structured recoveries
with related owners, available source spans and a suggested fix, independent of logging.
Both are recorded in `symbols.10n`, together with the naming policy. Unknown metadata,
ordered annotations and authored origins remain unchanged. Original hints are neither
exact target requests nor authenticated provider facts.

Declared `targetNames` facts use the [checked metadata adapter](../morphir-metadata/README.md).
Pass an explicit `metadata_capabilities` host contract to admit the freshly restored
provider Library and required interpreter. Its `backend.moonbit` spelling reserves an
exact name before automatic hints. Invalid or duplicate requests fail with owners and
an edit to make. Automatic names recover around exact requests with structured warnings.
`frontend.moonbit` is an original spelling hint only with matching MoonBit provenance.
`Output.naming_facts` and the symbol manifest record consumed assertion identities,
provider revisions and unvalidated predicates. Authored facts and provenance stay intact.
The installed CLI currently lacks signed-Library restoration; known naming facts fail
clearly there while Ion checkpoint preservation remains available.

Use `generate(input, naming=LegacyHex)` to retain the previous exported value, nominal
type, constructor and field ABI for automatic allocation. Explicit declared target
requests still keep their exact spelling in this mode. The engine accepts the corresponding project setting:

```toml
[backends.moonbit]
naming = "legacy-hex" # default: "readable"
```

`value_name(fqname)` remains the legacy encoding helper. Read the generated `symbols`
or `invocations` instead of predicting names in readable mode. Existing checkpoint
identities stay unchanged; generation never reverse-decodes old source hex identities.
An old checkpoint with no origin hint renders its stored semantic name. Set
`pipeline.strict_naming = true` to stop engine publication on a naming recovery.

MoonBit spelling conventions and keywords are documented in the
[language introduction](https://docs.moonbitlang.com/en/latest/language/introduction.html).
Compiler consumers here use the repository's pinned compiler as the acceptance gate.

## Scalar mapping and audited imports

| Morphir type | MoonBit type and construction |
| --- | --- |
| `morphir/SDK:basics#int` | `integer.Integer`, constructed from the exact lexeme with `integer.parse` |
| `morphir/SDK:basics#float` | `Double`, constructed from its IEEE bits, including negative zero and subnormals |
| `morphir/SDK:basics#bool` | `Bool` |
| `morphir/SDK:string#string` | `sdk.Text`, constructed from UTF-16 code units |
| `morphir/SDK:char#char` | `sdk.Character`, constructed from UTF-16 code units |
| `morphir/SDK:decimal#decimal` | `decimal.Decimal`, constructed after exact coefficient/exponent validation |
| Unit | `Unit` |

The scalar construction APIs are audited against this repository's SDK source.
The checked adapter allowlist covers 57 of the 248 value bindings, with a
classification for every binding in `sdk-coverage.json`.
The required SDK manifest
version is `0.1.0`, API profile `morphir-sdk-concrete-v1`, with semantic inventory pin
`bc99af69a8b24d391311fae3822a87eafef3c334`. Hosts must identify the actual supplied
source separately from that version.

Integer construction never narrows through a machine Int or Float. Decimal
construction normalizes an explicit numerical spelling while retaining the
original IR lexeme in metadata. It rejects nonzero precision below the SDK's
minimum exponent of -32 and bounds explicit exponents to -10000 through 10000.
Numerical Decimal normalizes zero and trailing zeros according to SDK behavior;
the source lexeme and rich Ion metadata retain their original spelling and scale.
Nonfinite Float literals and document literals are unsupported.

## Node identities and Ion preservation

The `morphir-moonbit-symbols-v1` profile has annotation `morphir_moonbit_symbols`.
It records source annotation tokens in order, retained rich metadata, source node
IDs and generated symbols. A symbol's generated declaration is derived from its
source declaration and body. Stable source IDs for this slice are:

- `unit:<unit-id>`
- `module:<package>:<module>`
- `value:<package>:<module>#<name>`
- The value ID followed by `/output` or `/body`

Metadata must reference a known ID exactly once. Unknown or duplicate IDs fail
preservation checks. Metadata values remain native Ion values, preserving ordered
unknown annotations and rich data. A canonical current Morphir JSON snapshot in
`source_ir_json` retains semantic IR attributes, extensions, documentation and
literal lexemes as an explicit compatibility record within the Ion artifact.
Rich Ion metadata never passes through that JSON record.

Generation defaults to 10,000 declarations and 4 MiB of total artifacts. These
are acceptance budgets for trusted typed input, not allocation or streaming
parser guarantees. A cancellation callback is checked between declarations and
before returning artifacts.

## Validation

```sh
mise exec -- moon test -p finos/morphir-moonbit \
  -p finos/morphir-engine/data/generator-conformance --target all
MOON_HOME="$HOME/.moon" mise exec -- node \
  pkgs/morphir-moonbit/scripts/test-compiler.mjs pkgs/morphir-sdk
```

`MOON_HOME` must identify a complete installation containing compiler and core
version `0.10.15+943464bfa`. The SDK argument supplies an explicit source tree.
Compiler acceptance copies that tree to a private workspace and uses `--frozen`;
it performs no dependency acquisition. It builds the emitted multi-module fixture
on native, JS, WASM and WASM-GC and checks exact scalar results through the exported
API and all 57 claimed SDK adapters, including concrete specializations. A
separate consumer verifies that private declarations are inaccessible.
Its JSON result records compiler, compiler bytes, core and supplied SDK tree
digests. The same gate runs current JSON, Ion text/binary and nonempty historical
JSON versions 1–3 through the native CLI, JSON-only component and required build
provider. Fresh compiler outputs and verified Ion receipts precede publication.
Broader E2 execution parity remains separate work.

The concrete library profile also lowers closed records, aliases, nongeneric
custom types, tuples, immutable lists, Maybe and Result, curried declarations,
closures, applications, nonrecursive lets, conditionals, constructor matches,
field reads and immutable record updates. Every generated function propagates
`SdkError`. Fully applied Boolean `and` and `or` short circuit; function and
argument evaluation use explicit temporaries. Result maps Morphir's error/value
parameter order to MoonBit's value/error order.

`sdk-coverage.json` classifies all 248 pinned SDK bindings. Supported bindings
accept only the concrete instances checked in `sdk.mbt`. This is a pricing
library profile, not full generic IR or SDK coverage. Generic declarations,
open records, unresolved external implementations and unaudited SDK references
fail contextually. E2 coverage and the upstream SDK release remain separate.

The repository's `mise run test` and `mise run check` include compiler acceptance.
CI runs it once in the native build job and checks emitted projects on all four
targets. Run that gate independently with:

```sh
MOON_HOME="$HOME/.moon" mise run test:compiler
```

It copies the supplied SDK into a private workspace, verifies source identities,
builds and tests the pricing API on all four targets, and checks access from a
separate consumer. Provider acceptance also rejects wrong compiler/core,
unresolved dependencies, changed inputs, stale or missing outputs, output limits
and deadlines, checking private-workspace cleanup after each outcome. These gates
use a supplied complete toolchain and perform no dependency acquisition.

Execution adapters derive their manifest, recursive custom-type registry and codecs
from this same lowering pass. They support the concrete rich-value pricing slice
through the portable execution protocol and a separate generated consumer module.
Library source artifacts remain independent of arguments, comparison policies and
telemetry. Constructor visibility and boundary-function rejections are recorded
explicitly. Character `to-upper` is audited for SDK UTF-16 case expansions.

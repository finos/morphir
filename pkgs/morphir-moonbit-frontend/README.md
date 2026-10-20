# MoonBit source frontend

This pure package lowers restricted, explicitly typed MoonBit source to current typed
Morphir library IR. Its two APIs are checked against
the MoonBit compiler, independent truth tables and the Morphir Scheme evaluator.
The source language is `moonbit`; profiles describe the supported subset.

| Channel | Profile | Source contract |
| --- | --- | --- |
| Stable, default | `moonbit-model-stable-v1` | Typed Bool/String/Int32 libraries, immutable bindings, direct acyclic calls, String ordering, length and owned slices, pinned String predicates, audited Boolean SDK binding |
| Experimental, explicit opt-in | `moonbit-model-experimental-v1` | Stable plus expanded integer widths, BigInt, Float/Double, audited SDK math/conversions and checked Decimal |

`compile_library(input)` uses `SourceChannel::Stable`. Opt in with
`compile_library(input, channel=Experimental)`. Both channels use the same compiler;
channel checks refuse unpromoted types and bindings even in private functions or
unused expressions. Supplying a broader host binding map cannot widen stable.
The old `compile` single-Boolean helper remains for historical checkpoint
compatibility tests, outside the selectable profile catalog.

These are advancing channels, not feature snapshots. Add a capability to
experimental first, with explicit limits and refusal cases. Promote it to stable
only after independent expectations, original source, Scheme, generated consumers,
and installed-client qualification pass for the claimed targets and modes. Include
Ion metadata/receipt replay, wrapper ABI, failure/publication behavior and
observability neutrality in that evidence. Promotion updates the stable allowlist,
capability inventory, shared regression corpus and documentation together; it does
not add a third profile. Keep experimental a superset of stable. A breaking semantic
or ABI change needs an explicit versioned migration rather than silently changing
an existing contract. Checkpoints retain their recorded provenance.

```moonbit
pub fn eligible(active : Bool, vip : Bool) -> Bool {
  active && !vip
}
```

All APIs accept an `Input` containing a logical `unit_id`, canonical Morphir
`package_name` and `module_name`, and source text. `compile` returns `Output`; the
library APIs return `LibraryOutput`. Both contain typed IR,
the function entry, visibility, native Ion metadata, annotations, provenance and structured warnings.
The package performs no file, process, registry or engine operations. The separate
[engine adapter](../morphir-engine/moonbit/README.md) maps this output to an `IRUnit`
and the Morphir CLI registers it explicitly. A2 extension packaging remains
separate work.

IR uses the pinned SDK type `morphir/SDK:int#int-32` for source Int32 and Int.
The opaque invocation carrier keeps the runtime tag `morphir/SDK:int#int32`;
its typed owner is the canonical SDK type. A transport tag does not declare a type.

## Cumulative source conformance

Use `compile_library(..., channel=Experimental)`, or source profile
`moonbit-model-experimental-v1`, for the full implemented capability set. It combines Bool operators,
bounded String literals, concatenation, equality and shortlex ordering; signed
and unsigned integer widths, BigInt, Float and Double; UTF-16 code-unit
`String.length()`; and `String[start:end].to_owned()` with Int32 bounds.
A slice clamps each bound to 0…length, moves a split surrogate boundary inward,
and returns empty when its adjusted start is at or after its end. Combining marks
remain separate units. Float32 operations round at each operation.

Typed immutable bindings, matching-type branches and direct acyclic calls compose
these capabilities in one file. Mixed signatures preserve each scalar's ABI.
String guards also apply when a function returns another type. Unowned slices,
single-index String access, imports and the full MoonBit language are unsupported.
SDK adapter availability alone does not admit arbitrary source calls.

Stable defaults to the audited Boolean binding. Experimental defaults to the
audited numeric SDK and checked Decimal bindings. A host can supply a narrower `PinnedSourceBindings` with
`bindings=Some(...)`; source cannot register or redirect bindings.

### Pinned numeric SDK calls

The adapter freezes `finos/morphir-sdk/basics` version `0.1.0`, SDK tree
`9c83a100383570236b3d781362524008f76dd56d`, and alias `basics`.
Source aliases cannot register packages or calls. Qualified calls bind arguments
once, left to right, and retain the pin, concrete signature, canonical classic
SDK name and numerical contract on their references and applications.

| Source call | Canonical Basics value | Source / Scheme / generated consumer | Qualification contract |
| --- | --- | --- | --- |
| `@basics.sqrt(Double)` | `sqrt` | Supported | Exact reference bits, including negative zero; negative inputs produce NaN |
| `@basics.sin(Double)` | `sin` | Supported | Reference vectors within 4 ULP; signed zero exact; infinity produces NaN |
| `@basics.cos(Double)` | `cos` | Supported | Reference vectors within 4 ULP; zero returns one; infinity produces NaN |
| `@basics.power_float(Double, Double)` | `power` | Supported | Reference vectors within 4 ULP; exact integer and exceptional cases checked separately |
| `@basics.abs_float(Double)` | `abs` | Supported | Classic branch semantics preserve negative zero and NaN; other qualified values exact |
| `@basics.not_(Bool)` | `not` | Supported | Exact Boolean negation |
| SDK Integer-returning rounding and Maybe conversions | Existing classic / numeric extension names | Supported subset below | Explicit optional and error boundaries |

All five numeric calls take and return `Double`. An implicit Float32 promotion
is refused. These calls reuse classic SDK declarations and leave the 248-value
inventory unchanged. Native, JavaScript, Wasm and Wasm-GC qualification runs in
debug and release. High-precision finite references were computed with mpmath
1.3.0 at 100 decimal digits, then rounded to binary64. The 4 ULP bound applies
to those reference vectors, not a global accuracy guarantee for every input.
NaN payloads are unspecified. The receipt records the compiler/core and SDK pin.

Arbitrary `@math` calls, other SDK names, source casts and imports are unsupported.

### SDK Integer and binary64 conversions

The library admits `@integer.Integer`, `@integer.Integer?` and `Double?` as explicit
boundary types. The Integer wrapper is distinct from source `BigInt`, even though
both lower to Morphir Int. Literals, arithmetic operators and unary minus do not
construct SDK Integer values. Integer equality and ordering are exact.

| Source calls | Canonical module | Classification | Contract |
| --- | --- | --- | --- |
| `@basics.round`, `floor`, `ceiling`, `truncate` | Basics, same names | Classic | `Double -> @integer.Integer raise @sdk.SdkError`; round ties toward positive infinity; other policies follow their names; nonfinite inputs raise `InvalidNumber` |
| `@basics.abs_int` | `basics#abs` | Classic | Exact Integer absolute value |
| `@basics.to_float` | `basics#to-float` | Classic | Integer to nearest binary64, ties to even; overflow to infinity |
| `@int.from_float64_exact`, `from_float64_truncated`, `from_float64_floor`, `from_float64_ceiling`, `from_float64_rounded` | Int, names with hyphens | `morphir-sdk-moonbit-numeric-v1` | `Double -> @integer.Integer?`; nonfinite inputs return None; exact also refuses fractional values; rounded ties toward positive infinity |
| `@int.to_float64_exact` | `int#to-float64-exact` | Same numeric extension | `@integer.Integer -> Double?`; None for inexact or overflowing results |
| `@int.to_float64_rounded` | `int#to-float64-rounded` | Same numeric extension | Same rounding and overflow contract as classic `to_float` |

All packages use SDK version `0.1.0` and the tree above. Aliases are fixed:
`basics`, `int`, `integer`, and root `sdk` for `SdkError`. The pure compiler
receives the resolved environment; it performs no dependency download or host
execution. Type uses and call references retain the package pin and authored
signature. Call metadata distinguishes classic and numeric extension values.
Ion checkpoints and generated `symbols.10n` receipts preserve these facts.

`raise @sdk.SdkError` and `raise @decimal.DecimalError` are the supported error annotations. Calling a declared
raising helper or classic rounding function requires the same annotation on the
caller, including in unreachable branches. This grants no host effects. Source
throw, catch, async, imports and general error types remain unsupported.
Optional values can be passed, returned and selected, but constructors, patterns,
unwrap and general Maybe APIs are not admitted. Public Integer inputs and outputs,
including Some values, keep the 4096 decimal digit budget; None passes unchanged.

The source capability inventory is [numeric-sdk.json](conformance/numeric-sdk.json).
The SDK's historical `morphir-moonbit-source-float-v1` inventory describes its
earlier source profile, where conversions were IR-only. The library admits the binary64
subset explicitly. Float32 SDK conversion functions remain IR-only because their
Double transport signature does not match the source Float32 semantic type.
Native, JavaScript, Wasm and Wasm-GC run original and generated consumers in debug
and release, using independent exact expected integers and binary64 bits.

`mise run test:typed-source` checks the distinct Boolean, String and numeric
fixtures through `compile_library`. It compares original MoonBit, Scheme and
compiled generated consumers on all four targets in debug and release. The Ion
receipt identifies each model's profile, compiler and supplied SDK.

### String ordering

String `<`, `<=`, `>` and `>=` return Bool and use MoonBit's UTF-16 shortlex
ordering. Length wins first, so `"b" < "aa"` is true. Equal lengths use lexical
code-unit order, so `"😀" < "\u{e000}a"` is true despite Unicode scalar ordering.
No normalization or locale conversion occurs. Bool ordering and Int32-returning comparison methods remain unsupported.

Lowering binds each operand once, left to right, then compares SDK integer lengths
and uses classic SDK comparison only for equal-length ties. It adds no runtime
binding or source numeric operation. The source String guards reject malformed
UTF-16 in either operand. Comparison owners retain `moonbit-source-string-order-v1`
facts with the source operator, shortlex policy and lowering rule; synthetic integer
lengths do not claim authored Int32 type uses. Ion replay preserves these facts,
and checked JSON export refuses their loss.

### Pinned String predicates

Both channels admit four String methods from the pinned MoonBit core. They
entered experimental first and were promoted to stable after the installed
qualification below. The adapter
supplies package `moonbitlang/core/builtin`, compiler/core `0.10.15+943464bfa`
and core tree `a951c067f909286603efada85c379197d589dc61`. Another package,
compiler or tree is refused, and source text cannot add a method.

| Source call | Pinned signature | Canonical SDK value | Contract |
| --- | --- | --- | --- |
| `s.is_empty()` | `(String) -> Bool` | `morphir/SDK:string#is-empty` | True only for zero UTF-16 units |
| `s.contains(needle)` | `(String, StringView) -> Bool` | `morphir/SDK:string#contains` | UTF-16 code-unit substring; an empty needle matches |
| `s.has_prefix(prefix)` | `(String, StringView) -> Bool` | `morphir/SDK:string#starts-with` | UTF-16 code-unit prefix |
| `s.has_suffix(suffix)` | `(String, StringView) -> Bool` | `morphir/SDK:string#ends-with` | UTF-16 code-unit suffix |

The argument must be a source `String`. The pinned compiler's implicit
String-to-StringView coercion is frozen in the binding; no StringView value is
admitted. No normalization occurs: `"é".has_prefix("e")` is false, and
`"é".has_prefix("e")` is true. Because source Strings are well-formed, a
match cannot split a surrogate pair. Lowering binds the receiver and then the
argument once, in source order, and applies the SDK value needle first. Public
String guards still refuse malformed UTF-16 and oversized text in either position.

Call references and applications retain `moonbit-source-binding-v1` facts: the
core pin, source signature, `string-method` form, frozen coercion, canonical
argument order and contract. Ion replay preserves them; checked JSON export
refuses their loss. The classic 248-binding SDK inventory is unchanged.

Other methods refuse with `moonbit_frontend.unsupported_method`, including
`to_upper`, `to_lower`, `trim`, `split`, `find`, the deprecated aliases
`starts_with` and `ends_with`, and methods that take callbacks or return
Option or List values. MoonBit ASCII case conversion differs from SDK Unicode
case conversion, so case conversion stays deferred. Wrong argument counts refuse
with `binding_arity`, wrong receiver or argument types with `type_mismatch`, and
labelled arguments with `unsupported_arguments`. A qualified spelling such as
`@String.contains` or `@string.contains` cannot reach a method. A host binding
map without the pinned methods refuses them with `unknown_binding`; a same-named
library function does not replace a method.
[string-sdk.json](conformance/string-sdk.json) records the admitted calls and
their qualification scope.

`mise run test:typed-source` checks independent rows against original source,
Scheme and generated consumers on native, JavaScript, Wasm and Wasm GC in debug
and release. `mise run test:installed-lifecycle` then qualifies every stable
String type, operator and call through the packed npm CLI: 39 independent rows,
34 of them also checked by the original compiler, on each required installed
target in debug and release. The other 5 rows send malformed UTF-16 or oversized
text that source cannot spell. The installed execution helper offers JavaScript,
Wasm GC, native C and, on macOS, LLVM; it does not offer Wasm without GC, so that
lane has local typed-source evidence only.

## Supported source

The original `compile` contract remains:

- Exactly one ordinary top-level function, with default or plain `pub`
  visibility. Every positional named parameter and the return type must explicitly
  use unqualified `Bool`. Zero parameters are allowed.
- Explicit `priv fn` is rejected, matching the pinned compiler. Plain `fn` is
  unexported; `pub fn` is exported.
- Boolean literals, parameter references, grouping, explicit `Bool` constraints,
  `if` with `else`, `!`, `&&`, `||`, `==` and `!=`.
- Comments and whitespace accepted by the pinned parser.

Imports, calls, recursion, local bindings, mutation, loops, early returns, methods,
generics, attributes, effects, async functions, other types and recovered syntax
are rejected. Equality binds operands once in source order. Boolean conjunction
and disjunction lower to short-circuit conditionals. Every lowered value has a
Boolean type attribute. Source names use the readable allocation policy below, with checked allocation for generated temporary bindings.

## Typed libraries

`compile_library` accepts the same `Input` and returns `LibraryOutput`: typed IR,
the canonical public entry list, native Ion metadata, annotations and provenance.
It checks every function, including unused private helpers. Signatures are collected
before bodies, so forward references work.

```moonbit
pub fn eligible(active : Bool, vip : Bool, suspended : Bool) -> Bool {
  let allowed : Bool = ready(active, vip)
  allowed && !suspended
}

pub fn default_ready() -> Bool { ready(true, false) }

fn ready(active : Bool, vip : Bool) -> Bool { active || vip }
```

Beyond the original expression forms, this profile supports direct, unqualified,
fully applied within-file calls, including zero-argument calls, and sequential
single-name immutable `let` bindings with optional supported type annotations. An initializer
sees the preceding scope; each shadowed binding receives a distinct identity. A
binding shadowing a function name cannot be called. Call arguments, binding
values and function results must match their declared types.

Function values, partial applications, labelled or optional arguments, destructuring,
local functions and discarded expression statements are rejected. Imports, general effects and the remaining exclusions above remain unsupported. Direct
and indirect recursion are rejected across the whole unit, including calls in
constant-false branches. Calls remain references in IR; lowering never inlines or
expands the call graph. Equality binds operands once, lets are eager, and Boolean
conjunction/disjunction retain their short-circuit boundaries.

This pure API compiles a library without host access. The
[engine adapter](../morphir-engine/moonbit/README.md) offers both profiles under
language `moonbit`, with stable as the default. Select the stable library with
`frontend.profile = "moonbit-model-stable-v1"` or CLI
`--frontend-profile moonbit-model-stable-v1`. Provider identity and configured
source capabilities belong to the engine descriptor. The installed numeric gate in
`mise run test:installed-lifecycle` qualifies the experimental numeric and Decimal
capabilities. It does not promote them; promotion to stable is a separate decision.


## Strings and scalar types

Int and Int32 use signed 32-bit wraparound arithmetic; the separate
`morphir-moonbit-source-int32-v1` helper normalizes source arithmetic. Classic
SDK `to-int-32` remains checked narrowing. Authored type uses retain their source
spelling and numeric facts.

`compile_library` accepts mixed String, Boolean and numeric libraries:

```moonbit
fn prefix() -> String { "Hello, " }
pub fn greet(name : String) -> String {
  let greeting : String = prefix()
  greeting + name
}
pub fn welcome(name : String, enabled : Bool) -> String {
  if enabled { greet(name) } else { "" }
}
```

The library supports ordinary quoted literals, standard and numeric escapes,
String `+`, exact `==`/`!=`, immutable lets, explicit scalar constraints, Bool
conditions with matching branch types, and fully applied acyclic same-file calls.
Call arguments evaluate once in source order. Equality does not normalize Unicode.
Length, owned slices and shortlex ordering use the contracts above. General
methods, imports, interpolation, multiline strings and Char/StringView are unsupported.

Source Strings use classic `morphir/SDK:string#string` and SDK `Text` storage but
require well-formed UTF-16. Every public String argument is checked, even when
unused or when a branch ignores it. Results and literals are checked too.
Concatenation preflights its result before allocation. The hard bound is 1,048,576
UTF-16 units per value; `max_string_code_units` may tighten it, including to zero.
There is no aggregate allocation guarantee. Existing evaluator limits still apply.

These checks are executable references in the separately inventoried
`morphir-moonbit-source-string-v1` runtime extension. Its two bindings are
`morphir/moonbit-source:string#require-valid` and `#append-bounded`.
Length and owned slicing use `#length-int32` and `#slice-owned`
under `morphir-moonbit-source-string-index-v1`.
The classic 248-binding inventory is unchanged. Generated consumers require SDK
profile `morphir-sdk-concrete-v1+moonbit-source-string-v1`; malformed text raises
`SdkError.UnrepresentableText`, and size refusal raises `SdkError.OutOfRange`.
Generated dependencies declare `+moonbit-source-int32-v1` when signed-width
normalization is used and `+moonbit-source-string-index-v1` when length or
slicing is used.
Scheme preserves the corresponding `sdk.unrepresentable_text` and
`sdk.out_of_range` model error codes.

String type uses and literals retain `moonbit-source-string-v1` facts, including
separate authored tokens and cooked text. Literal coordinates are checked against
the pinned lexer's Unicode scalar positions, including non-ASCII comments.
Synthetic calls retain their source role. Ion preserves these facts and unknown
neighbor facts; checked Morphir JSON conversion may report `data.lossy_conversion`.
Metadata describes source facts and never grants runtime authority. String source
libraries cannot own the reserved `morphir/SDK` or `morphir/moonbit-source` packages.

`mise run test:typed-source` compiles original and generated direct consumers on
native, JS, WASM and WASM-GC in debug and release, checks Scheme results and private
access, and writes an Ion receipt under `.dev/typed-source-acceptance/`. The installed
lifecycle gate repeats the numeric rows through the packed npm CLI.


## Function documentation

The parser attaches `///` documentation to each declaration. All frontend APIs
retain it in the IR value's `doc`, including private helpers. Conventional comment
markers are removed; Markdown indentation, internal blank lines and Unicode remain.
An empty `///|` separator produces no documentation. Ordinary comments stay out of
API docs. Ion and Morphir JSON retain the documentation as semantic IR data.
MoonBit and Scheme backends render it above the corresponding generated function.

## Readable names and automatic recovery

New source compilation uses `moonbit-readable-names-v1`. Both profiles normalize
underscores and camel-case boundaries into Morphir words and retain multi-letter
initialisms. `eligible` stays `eligible`; `is_ready` and `isReady` each normalize
to `is-ready`; `readHTTP` becomes `read-HTTP` and `readHttp` becomes `read-http`.
Digits stay attached to their current word. Canonical IR parsing remains strict.
Spellings the parser accepts but the portable name grammar cannot represent retain
their source origins and receive an escape with a warning. Lexically invalid
source is rejected before parsing can discard characters. The pinned compiler
and lexer reject Greek suffixes such as `readyλ`; these are syntax failures,
not recoverable naming collisions. Unicode comments remain supported.

The allocator reserves all normalized candidates in an identity namespace before
assigning names. For a collision group, canonical snake-case spelling owns the
plain identity when present. Otherwise, exact UTF-8 spelling order decides. Other
owners receive `<base>-source-<token>`. The token starts with up to four bytes of
original UTF-8 spelling encoded as lowercase hexadecimal. If occupied, extend it
one byte at a time; after the full spelling, add a checked decimal counter.
This is a discriminator, not a digest or a security identity. Only affected names
receive it, and declaration order does not change the allocation.

For example, a library containing both `is_ready` and `isReady` keeps `is-ready`
for the first and allocates `is-ready-source-69735265` for the second. References
remain bound to distinct functions. Successful `Output` and `LibraryOutput`
values include `warnings`, with stable codes, all involved original spellings,
allocated identities, related name spans and a suggested source rename. The
suggested name is checked against reserved identities. Call either API with
`strict_naming=true` to reject recoverable naming warnings instead of returning
output. Ordinary readable names and routine lexical shadowing emit no warning.

Binder allocation reserves all user candidates before allocating locals and
synthetic operands. Shadowed locals keep a readable base, such as
`ready-shadow-2` when `ready-shadow-1` is already an authored name. Equality
operands use roles such as `ready-equality-left-1` and retain expression origins.
Original spellings and final identities remain separate in declaration,
parameter, binder and temporary receipts.

Warnings are independent of optional logs. They also appear as versioned
`morphir_warning` records in Ion provenance for engine checkpoint replay.
This provenance is an engine diagnostic contract, separate from upstream native
linked metadata or trusted `targetNames` interpretation. The engine adapter and
CLI preserve structured details and deduplicate replay within each source run.

This changes public entry IDs for newly compiled source. Update invocation suites
and entry selectors from `#source-<hex>` to the returned canonical `entry` or
`entries` values. Existing checkpoints retain their identities when loaded; the
loader never reverse-decodes or renames historical entries. The MoonBit generator
defaults to `moonbit-readable-targets-v1` and uses usable same-language source
spellings for public exports. For example, the two entries above export
`is_ready` and `isReady` while keeping distinct semantic identities. Read each
generated symbol receipt to find the allocated target name. Select
`[backends.moonbit] naming = "legacy-hex"` when an existing consumer needs the
earlier generated ABI.

The frontend represents source parameters as curried IR functions. A generated
consumer calls a two-parameter export as `eligible()(active)(vip)`. The initial
accessor returns the function; each application supplies one source argument.
This calling convention is unchanged by the naming policies.

The installed acceptance gate checks normalization collisions, initialisms,
parameter collisions and generated-looking locals against original source,
independent Boolean rows, Scheme and generated execution. It also consumes a
retained pre-change checkpoint with its original `source-<hex>` entries. Both Ion
checkpoint forms preserve origins and opaque metadata. Warnings remain available
with logs disabled, and strict rejection preserves existing publication.

Declared `targetNames` facts require an explicit authenticated-provider capability
in the library host. The installed CLI preserves these facts in checkpoints but
currently rejects generation with `metadata.provider_unavailable`. See the
[generator contract](../morphir-moonbit/README.md#naming-and-compatibility) for the
capability boundary. Qualification uses a simulated host, not a signed provider
release or upstream MCK certification.

## Diagnostics and bounds

Validation raises `FrontendError::Invalid` with a stable
`moonbit_frontend.<code>` diagnostic, detail and a source span when available.
Default hard caps are 65,536 UTF-8 source bytes, 16 parameters, expression depth
64 and 4,096 visited source expressions. Callers can lower these limits. `Limits::validate()` and
`LibraryLimits::validate()` check budgets without parsing source, allowing adapters
to validate capability claims before registration.
Cancellation runs before and after parsing and at every lowering visit.

`LibraryLimits` additionally bounds the entire library:

| Budget | Hard default | Scope |
| --- | ---: | --- |
| UTF-8 source bytes | 65,536 | Unit |
| Functions | 64 | Unit |
| Positional parameters | 16 | Function |
| Immutable lets | 256 | Function |
| Visited source expressions | 4,096 | Unit, including call identifiers |
| Call sites | 1,024 | Unit |
| Expression depth | 64 | Root at depth zero |
| Call graph depth | 32 | Edges on the longest path |

Callers can tighten these budgets, including zero parameters, lets, calls or depth,
but cannot increase them. Validation returns one primary diagnostic and no partial
library. Diagnostic order follows fixed phases: input, parse, signatures and syntax
adaptation, lexical resolution, body/call-graph checks, then lowering. Each body pass
uses declaration order and source expression order. Cancellation is polled between
phases and during bounded walks. Acyclic calls can still produce expensive runtime
evaluation; validation budgets are not an execution deadline.

These are validation and lowering limits. The parser is synchronous and does not
offer a cancellation callback or a hard internal allocation budget. Hosts that
accept untrusted source need their own execution isolation and deadline.

Spans retain parser positions under `moonbit-parser-position-v1`: lines are
one-based and columns are zero-based `cnum - bol` in the parser's native units.
Consumers must not assume those columns are UTF-8 byte offsets. Declaration,
parameter and body origins retain source spelling in native Ion values.
Provenance records the profile, parser version and logical unit identity. Host
receipts supply source and toolchain digests; the pure frontend does not claim a
filesystem identity.

Library provenance separates `language: "moonbit"` from `profile`; the original
profile's provenance shape stays unchanged. Library body metadata retains nested
binding and call origins beneath its stable body node ID, including both source
spelling and unique binding identity. Intermediate `Reference` and `Apply` values
carry the appropriate curried function types; final results carry their checked source types.

## Observations

`compile(scope=observer.scope())` accepts an optional portable observation scope.
The default is disabled and performs no clock, ID or sink work. A `frontend` span
contains `parse`, declaration/signature `profile-check`, and expression checking
`lower` spans. The latter intentionally combines body typing and IR lowering.
Cancellation ends active spans as cancelled and preserves the original frontend
diagnostic. Required diagnostics stay outside the observation channel. Typed sink
failures leave IR, source origins and provenance unchanged.

The host supplies clocks, IDs and delivery. Default records contain no source,
logical unit IDs, paths, names or diagnostic text. This package imports the portable
`finos/morphir-execution/observability` contract and no logging backend or host API.

`compile_library` has ordered children `parse`, `profile-check` (signatures and
syntax), `resolve`, `profile-check` (bodies and whole graph), and `lower`. The two
profile-check occurrences are distinguished by their fixed position around
resolution. It uses the same disabled default, sink containment and privacy rules;
the original API's stage sequence is unchanged.

## Pins and acceptance

The parser is `moonbitlang/parser@0.4.5`, lexer `moonbitlang/lexer@0.4.3`, and Ion
is `moonrockz/ion@0.5.0`. Ion remains the preferred engine representation. Current
Morphir JSON serialization remains supported and is checked in frontend tests.

Run focused tests with:

```sh
moon test -p finos/morphir-moonbit-frontend --target all
```

`MOON_HOME=/path/to/pinned/moon mise run test:moonbit-frontend` builds the original
source and generated libraries in a private workspace using supplied SDK source,
then compares their Boolean truth tables with independent expectations and Scheme
results on JS, native, Wasm and Wasm GC, in debug and release modes. It uses compiler
and core `0.10.15+943464bfa` and the SDK's pinned semantic bindings. It performs no
registry acquisition in the external workspace. The acceptance executable is a
test fixture, not an engine integration API.

The gate covers 11 stable Boolean models and six libraries with 13 public entries:
86 Boolean rows per target/mode. It also checks that every private fixture symbol
is inaccessible to a separate consumer in both original and generated libraries,
and that the pinned compiler rejects explicit `priv fn` (diagnostic 3005). The
all-private library builds without an inferred entry. Pure tests exercise rejection,
exact/tightened budgets, graph depth, Ion origins and observation behavior.

Receipts default to `.dev/frontend-acceptance/`; set `MORPHIR_FRONTEND_RECEIPTS` to
choose another directory. They retain model sources, typed JSON IR, generated
sources, binary Ion symbol files, lane logs and source/dependency/toolchain
identities. `MORPHIR_FRONTEND_SDK` can supply an explicit SDK source directory.

## Checked Decimal source calls

The library admits the SDK library type `@decimal.Decimal`. It is a concrete type,
not a built-in MoonBit scalar. The finite binding factory requires package
`finos/morphir-sdk/decimal`, version `0.1.0`, alias `decimal` and SDK tree
`642fd13ea74bc46c3f5344844c9cca4ffbae368a`. Numeric bindings retain their audited identities.

```moonbit
pub fn amount(text : String) -> @decimal.Decimal raise @decimal.DecimalError {
  let value = @decimal.from_string_exact(text)
  @decimal.divide(@decimal.mul(value, value), value)
}
```

| Admitted call | Contract |
| --- | --- |
| `from_string_exact(String)` | Exact construction using the classic lexical grammar; `InvalidLiteral` for invalid syntax or construction budgets; `PrecisionLoss` if nonzero digits would be discarded below exponent -32 |
| `add`, `sub`, `mul` | Classic exact coefficient arithmetic with normalization and truncation at exponent -32 |
| `eq`, `neq`, `lt`, `lte`, `gt`, `gte` | Exact numerical comparison, independent of original scale |
| `round` | Round to an integer, ties to even, including negative ties |
| `divide` | Truncate toward zero at exponent -32; `DivisionByZero` for any zero divisor, including 0/0; `Underflow` for a nonzero quotient truncated to zero; 0/nonzero succeeds |
| `divide_with_default(fallback, a, b)` | Explicit opt-in fallback for division failure; successful zero remains zero |

Construction is bounded to 4096 source code units and scientific exponents
-32 through 4096. Zero construction is canonical. Classic arithmetic is retained,
including a zero produced by multiplication underflow whose internal exponent
is -32, though its numerical text is `0`. Decimal-to-float conversion, general
Maybe patterns, source error handlers and other Decimal calls are excluded.

The three added calls have canonical identities under
`morphir/SDK:decimal-checked-v1#`, classified as
`morphir-sdk-decimal-checked-v1`. Classic `decimal#div` still returns Maybe and
`decimal#div-with-default` keeps its existing fallback contract. The classic
248-binding SDK inventory is unchanged. Checked source calls require
`raise @decimal.DecimalError`; direct calls propagate that requirement.

Type-use precision facts belong to Decimal type nodes. A literal construction's
binding facts retain its original decoded text, source spelling and fractional
scale on the call reference/application, separately from runtime normalization.
Dynamic construction does not invent literal facts. Ion text/binary checkpoints
and generated symbol receipts preserve those facts. Checked JSON export refuses
this enrichment rather than dropping it.

Generated functions in a library using checked Decimal calls declare `raise Error`
because Decimal errors and existing SDK boundary errors can both escape. Callers
can catch the concrete `@decimal.DecimalError` cases. Libraries without checked Decimal calls use
`raise @sdk.SdkError`; `symbols.10n` records the generated error type.

[numeric-decimal.json](conformance/numeric-decimal.json) records the admitted
calls and local qualification scope. `mise run test:typed-source` compares original
source, Scheme and generated consumers against independent exact expectations
on native, JavaScript, Wasm and Wasm GC in debug/release. The installed numeric
gate (`MORPHIR_INSTALLED_SCOPE=numeric`) runs the Decimal rows, failures and a
deliberate mismatch through the packed npm CLI.

Generated invocation drivers map the four concrete Decimal errors to the same
`sdk.decimal.*` model-error values as Scheme. Generated dependency contracts
include `+decimal-checked-v1` when executable checked calls occur. The process
build provider verifies fingerprints of the audited Decimal implementation and
its required SDK files before compiling, so an old or modified SDK cannot pass
that capability check using only the classic bindings manifest. Checkout line
endings are normalized for this source evidence.

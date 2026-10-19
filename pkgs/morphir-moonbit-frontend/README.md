# MoonBit source frontend

This pure package lowers restricted, explicitly typed MoonBit source to current typed
Morphir library IR. Its additive APIs are checked against
the MoonBit compiler, independent truth tables and the Morphir Scheme evaluator.
The source language is `moonbit`; profiles describe the supported subset.

| API | Profile | Source contract | Entry contract |
| --- | --- | --- | --- |
| `compile_supported_library_2026_10_19` | `moonbit-model-library-2026-10-19` | Cumulative Bool/String/Int32, including signed arithmetic, UTF-16 length and owned slices | Sorted public entries with String guards and Int32 wrappers |
| `compile_supported_library_2026_10_17` | `moonbit-model-library-2026-10-17` | All qualified Bool/String/Int32 capabilities, including shortlex ordering | Sorted public entries and executable String guards |
| `compile_supported_library_v2` | `moonbit-model-library-v2` | Cumulative v1 capabilities plus String shortlex comparisons | Sorted public entries and executable String guards |
| `compile_supported_library` | `moonbit-model-library-v1` | Pinned v1 source union: Bool, String basics, Int32 identity/selection/calls, including mixed signatures | Sorted public entries and executable String guards |
| `compile` | `moonbit-model-bool-v1` | One function; Boolean expressions | One `entry`, with `public` visibility |
| `compile_typed_library` | `moonbit-model-typed-library-foundation-v1` | Bool/Int32 signatures, typed lets, conditionals and direct calls; no numeric literals or arithmetic | Sorted public entries |
| `compile_int32_library` | `moonbit-model-int32-library-v1` | Signed Int32 literals, wraparound arithmetic and comparisons with Bool expressions | Sorted public entries and Int32 wrappers |
| `compile_string_library` | `moonbit-model-string-library-v1` | String/Bool signatures, literals, concatenation, equality, typed lets, conditionals and direct calls | Sorted public entries with executable String guards |
| `compile_library` | `moonbit-model-bool-library-v1` | Several functions; direct calls and immutable lets | Sorted public `entries`; all-private libraries have none |

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

Use `compile_supported_library_2026_10_19` or source profile
`moonbit-model-library-2026-10-19`
for all currently qualified source capabilities together. It combines Bool
operators, bounded String literals/concatenation/equality/ordering, signed Int32
literals/arithmetic/comparisons, UTF-16 code-unit `String.length()`, and
`String[start:end].to_owned()` with Int32 bounds. A slice clamps each bound to
0…length, moves a split surrogate boundary inward, and returns empty when its
adjusted start is at or after its end. Combining marks remain separate units.
The profile also supports Int32 identity and selection, immutable typed bindings,
matching-type branches and direct acyclic
calls. Mixed signatures preserve every scalar's ABI. String guards also apply
when the function returns Int32 or Bool.

The dated APIs stay pinned to their snapshots. The 2026-10-17, v1 and v2 APIs
retain their earlier admission rules. The current profile does not admit
unowned slices, single-index String access, imports or the full MoonBit language.
Backend SDK adapter availability alone never widens source admission.

`mise run test:typed-source` replays the existing Int32, String and Boolean
fixtures through their narrow profiles, pinned v1 and current dated snapshots. It
checks original MoonBit, Scheme and compiled generated consumers on all four targets in
debug and release. The Ion receipt identifies each model's profile, compiler
and supplied SDK.

### String ordering

String `<`, `<=`, `>` and `>=` return Bool and use MoonBit's UTF-16 shortlex
ordering. Length wins first, so `"b" < "aa"` is true. Equal lengths use lexical
code-unit order, so `"😀" < "\u{e000}a"` is true despite Unicode scalar ordering.
No normalization or locale conversion occurs. Numeric and Bool ordering remain
unavailable, as do Int32-returning comparison methods.

Lowering binds each operand once, left to right, then compares SDK integer lengths
and uses classic SDK comparison only for equal-length ties. It adds no runtime
binding or source numeric operation. The source String guards reject malformed
UTF-16 in either operand. Comparison owners retain `moonbit-source-string-order-v1`
facts with the source operator, shortlex policy and lowering rule; synthetic integer
lengths do not claim authored Int32 type uses. Ion replay preserves these facts,
and checked JSON export refuses their loss.

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

## Boolean libraries

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
single-name immutable `let` bindings with optional `Bool` annotations. An initializer
sees the preceding scope; each shadowed binding receives a distinct identity. A
Boolean binding shadowing a function name cannot be called. All call arguments,
binding values and function results must be Boolean.

Function values, partial applications, labelled or optional arguments, destructuring,
local functions and discarded expression statements are rejected. Imports, other
types, effects and the remaining exclusions above also remain unsupported. Direct
and indirect recursion are rejected across the whole unit, including calls in
constant-false branches. Calls remain references in IR; lowering never inlines or
expands the call graph. Equality binds operands once, lets are eager, and Boolean
conjunction/disjunction retain their short-circuit boundaries.

This pure API compiles a library without host access. The
[engine adapter](../morphir-engine/moonbit/README.md) offers both profiles under
language `moonbit`, preserving the seed default. Select the library with
`frontend.profile = "moonbit-model-bool-library-v1"` or CLI
`--frontend-profile moonbit-model-bool-library-v1`. Provider identity and configured
source capabilities belong to the engine descriptor. Full installed library parity
qualification and A2 extension packaging remain separate roadmap work.


## String libraries and the typed foundation

`compile_typed_library` qualifies the shared mixed-type pipeline with Bool and
SDK Int32 signatures, including MoonBit's `Int` alias. It preserves authored type
uses in `moonbit-source-scalar-v1` extensions. This narrow profile admits identity,
conditional and direct-call paths; full numeric arithmetic remains separate work.

`compile_int32_library` adds signed literals, unary negation, `+`, `-`, `*`,
equality and ordered comparisons. It widens operands to exact Morphir Int and
normalizes arithmetic results to signed 32-bit values. Authored `Int` and
`Int32` type uses retain `moonbit-source-number-v1` facts. The separate
`morphir-moonbit-source-int32-v1` helper performs signed-width conversion;
classic SDK `to-int-32` remains checked narrowing.

`compile_string_library` reuses that pipeline for String/Bool libraries:

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

The profile supports ordinary quoted literals, standard and numeric escapes,
String `+`, exact `==`/`!=`, immutable lets, explicit scalar constraints, Bool
conditions with matching branch types, and fully applied acyclic same-file calls.
Call arguments evaluate once in source order. Equality does not normalize Unicode.
Ordering, length, slices, methods, imports, interpolation, multiline strings,
Char/StringView values and numeric expressions remain outside this profile.

Source Strings use classic `morphir/SDK:string#string` and SDK `Text` storage but
require well-formed UTF-16. Every public String argument is checked, even when
unused or when a branch ignores it. Results and literals are checked too.
Concatenation preflights its result before allocation. The hard bound is 1,048,576
UTF-16 units per value; `max_string_code_units` may tighten it, including to zero.
There is no aggregate allocation guarantee. Existing evaluator limits still apply.

These checks are executable references in the separately inventoried
`morphir-moonbit-source-string-v1` runtime extension. Its two bindings are
`morphir/moonbit-source:string#require-valid` and `#append-bounded`.
The cumulative 2026-10-19 profile adds `#length-int32` and `#slice-owned`
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
access, and writes an Ion receipt under `.dev/typed-source-acceptance/`. Installed
qualification and the remaining String profiles keep their own roadmap tasks.


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
carry the appropriate curried function types; final results carry `Bool`.

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

The gate covers 11 original-profile models and six libraries with 13 public entries:
86 Boolean rows per target/mode. It also checks that every private fixture symbol
is inaccessible to a separate consumer in both original and generated libraries,
and that the pinned compiler rejects explicit `priv fn` (diagnostic 3005). The
all-private library builds without an inferred entry. Pure tests exercise rejection,
exact/tightened budgets, graph depth, Ion origins and observation behavior.

Receipts default to `.dev/frontend-acceptance/`; set `MORPHIR_FRONTEND_RECEIPTS` to
choose another directory. They retain model sources, typed JSON IR, generated
sources, binary Ion symbol files, lane logs and source/dependency/toolchain
identities. `MORPHIR_FRONTEND_SDK` can supply an explicit SDK source directory.

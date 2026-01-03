# Morphir-Go Agent Handoff (IR: Pattern + next steps)

Date: 2026-01-02

## Purpose
This doc captures the current context, what’s already implemented, the remaining work, and the strategy/patterns to follow so another coding agent can resume the Morphir IR porting effort without re-discovery.

## Repo + branch state
- Repo: `finos/morphir-go`
- Default branch: `main`
- Working branch: `feature/model-work`
- Working tree: clean at time of writing (no uncommitted changes)

Recent commits on `feature/model-work`:
- `e8665c5` feat(beads): add initial Beads configuration and documentation files
- `94068d3` feat(models): add Pattern IR + JSON codec
- `dfbc6ba` feat(models): add Morphir name parsing/formatting
- `afefbf9` test(codec): cover type definition decode/roundtrip
- `8281996` feat(models): add Literal IR and JSON codec

> Note: `AGENTS.md` was edited recently (by user/tools). Always re-check it before making process/CI assumptions.

## What’s implemented already
### Stable IR models (pkg/models)
The stable in-memory IR is in `pkg/models/ir`.

Implemented primitives + modules include:
- Naming: `Name`, `Path`, `QName`, `FQName` plus Morphir-style parsing/formatting helpers.
- `Type[A]` (generic, attribute-carrying) + traversal helpers.
- `Literal` + `Decimal`.
- `TypeSpecification`, `TypeDefinition`, constructors, `AccessControlled`.
- NEW: `Pattern[A]` (generic, attribute-carrying).

Pattern model implementation:
- File: `pkg/models/ir/pattern.go`
- Variants match Morphir-Elm (`Morphir.IR.Value.Pattern`):
  - `WildcardPattern a`
  - `AsPattern a (Pattern a) Name`
  - `TuplePattern a (List (Pattern a))`
  - `ConstructorPattern a FQName (List (Pattern a))`
  - `EmptyListPattern a`
  - `HeadTailPattern a (Pattern a) (Pattern a)`
  - `LiteralPattern a Literal`
  - `UnitPattern a`
- Provided helpers:
  - `EqualPattern(eqAttrs, left, right)` structural equality
  - `MapPatternAttributes(p, mapAttrs)` changes attribute type across the tree

### JSON codecs (versioned, Morphir-compatible)
Codecs live in `pkg/models/ir/codec/json`.

General approach used across codecs:
- Encodings are “tagged arrays” (Elm-style): `[tag, attrs, ...]`.
- `Options` includes `FormatVersion` (`FormatV1`, `FormatV2`, `FormatV3`).
- Tag casing differs between v1 and v2/v3.
- Some shapes differ by version (e.g. `Type` record field shape differs in v1 vs v2/v3).
- Decode must reject mismatched versions (tests assert that).

NEW Pattern codec:
- File: `pkg/models/ir/codec/json/pattern.go`
- Functions:
  - `EncodePattern(opts, encodeAttributes, pattern)`
  - `DecodePattern(opts, decodeAttributes, data)`
- Tag mapping:
  - v1 snake_case tags:
    - `wildcard_pattern`, `as_pattern`, `tuple_pattern`, `constructor_pattern`,
      `empty_list_pattern`, `head_tail_pattern`, `literal_pattern`, `unit_pattern`
  - v2/v3 PascalCase tags:
    - `WildcardPattern`, `AsPattern`, `TuplePattern`, `ConstructorPattern`,
      `EmptyListPattern`, `HeadTailPattern`, `LiteralPattern`, `UnitPattern`
- Array shapes match Morphir-Elm:
  - `WildcardPattern`: `[tag, attrs]`
  - `AsPattern`: `[tag, attrs, pattern, name]`
  - `TuplePattern`: `[tag, attrs, [patterns...]]`
  - `ConstructorPattern`: `[tag, attrs, fqName, [patterns...]]`
  - `EmptyListPattern`: `[tag, attrs]`
  - `HeadTailPattern`: `[tag, attrs, headPattern, tailPattern]`
  - `LiteralPattern`: `[tag, attrs, literal]`
  - `UnitPattern`: `[tag, attrs]`

Pattern codec tests:
- File: `pkg/models/ir/codec/json/pattern_test.go`
- Covers:
  - Roundtrip for v3
  - Tag assertions (v1 vs v3)
  - Wrong-version decode rejection (v1 decode on v3 payload)

## How to run tests (important: multi-module repo)
This repo uses `go.work` and multiple modules; running `go test ./...` at the repo root is not the usual workflow.

Run model tests like this:

```bash
cd pkg/models
go test ./...
```

Repo-level workflows also exist via `just` (see `Justfile`), e.g. `just test`.

## Implementation patterns to keep consistent
### Stable IR sum types in Go
Pattern used throughout stable IR:
- Model sum types as an interface plus concrete variant structs:
  - `type Pattern[A any] interface { isPattern(); Attributes() A }`
  - Each variant is a struct with unexported fields and exported accessors.
- Provide constructors like `NewXxxPattern(...) Pattern[A]`.
- Keep immutability/value semantics:
  - Copy slices on construction and when returning via accessors.

### Codec patterns
- Encode:
  - `opts = opts.withDefaults()` at entry.
  - Validate non-nil values and non-nil `encodeAttributes`.
  - Marshal as JSON arrays of raw messages.
- Decode:
  - Validate non-null payloads.
  - Decode header: at least 2 elements `[tag, attrs, ...]`.
  - Map tag -> kind using `kindFrom<Tag>(opts.FormatVersion, tag)`.
  - Dispatch by kind to per-variant decode functions.
  - Return clear errors and reject unknown tags.

Lint note:
- The repo enforces cognitive complexity; large encode/decode switches should be refactored into helper functions (as done for `Pattern`).

## Remaining work (next logical steps)
### 1) Port `Value` IR (stable model)
There is currently no `Value` implementation in Go (confirmed: no `pkg/models/ir/*value*.go` and no `EncodeValue/DecodeValue`).

Next module to port is Morphir-Elm `Morphir.IR.Value.Value ta va` plus supporting `Definition` and `Specification`.

Upstream references:
- `src/Morphir/IR/Value.elm` (defines `Value`, `Pattern`, `Definition`, `Specification`)
- `src/Morphir/IR/Value/Codec.elm` (v2/v3 JSON encoding)
- `src/Morphir/IR/Value/CodecV1.elm` (v1 JSON encoding)

`Value` variants in Elm (high-level):
- `Literal`, `Constructor`, `Tuple`, `List`, `Record`, `Variable`, `Reference`, `Field`, `FieldFunction`,
  `Apply`, `Lambda`, `LetDefinition`, `LetRecursion`, `Destructure`, `IfThenElse`, `PatternMatch`, `UpdateRecord`, `Unit`.

Recommended stable Go design:
- `type Value[TA any, VA any] interface { isValue(); TypeAttributes() TA; ValueAttributes() VA }` (or a similar split matching upstream where `ta` and `va` exist)
  - Be careful: Elm encodes type attrs for types, and value attrs for values; in codecs `encodeValue encodeTypeAttributes encodeValueAttributes`.
  - Consider matching existing patterns used for `Type[A]` and `Pattern[A]`.

### 2) Implement `EncodeValue` / `DecodeValue` with v1/v2/v3 tags
Strategy:
- Mirror the `Pattern` codec approach:
  - Tag mapping function for v1 snake_case tags vs v2/v3 PascalCase tags.
  - Strict array length checks per variant.
  - Reuse existing codecs:
    - Names: `EncodeName/DecodeName`
    - FQName: `EncodeFQName/DecodeFQName`
    - Literal: `EncodeLiteral/DecodeLiteral`
    - Type: `EncodeType/DecodeType`
    - Pattern: `EncodePattern/DecodePattern`

Where version differences exist beyond tag casing, encode/decode must branch based on `FormatVersion` (like `Type` does for record fields).

### 3) Add tests for Value codec
Follow patterns in:
- `pkg/models/ir/codec/json/type_test.go`
- `pkg/models/ir/codec/json/literal_test.go`
- `pkg/models/ir/codec/json/pattern_test.go`

Minimum expected tests:
- Roundtrip v3 of a non-trivial nested `Value` containing patterns (`Lambda`, `Destructure`, `PatternMatch`).
- Tag assertions (v1 vs v3) for at least one constructor.
- Wrong-version decode rejection.

### 4) Optional: traversal helpers for Pattern and Value
Pattern currently has:
- Structural equality
- Attribute mapping

Depending on how `Type` was done in this repo, you may also want:
- `MatchPattern`, `FoldPattern`, `MapPattern` (not just `MapPatternAttributes`)

Do this only if it’s needed by the next ports/codegen.

## Practical “resume” checklist
1. Pull latest and confirm branch:
   ```bash
   git pull --rebase
   git status
   git log -5 --oneline
   ```
2. Run model tests:
   ```bash
   cd pkg/models
   go test ./...
   ```
3. For the next port (`Value`), keep implementation consistent with:
   - `pkg/models/ir/type.go` and `pkg/models/ir/codec/json/type.go`
   - `pkg/models/ir/pattern.go` and `pkg/models/ir/codec/json/pattern.go`
4. When done, commit and push (see process rules in `AGENTS.md`).

## Key files to open first
- Stable IR:
  - `pkg/models/ir/type.go`
  - `pkg/models/ir/literal.go`
  - `pkg/models/ir/pattern.go`
- JSON codecs:
  - `pkg/models/ir/codec/json/options.go`
  - `pkg/models/ir/codec/json/format_version.go`
  - `pkg/models/ir/codec/json/type.go`
  - `pkg/models/ir/codec/json/literal.go`
  - `pkg/models/ir/codec/json/pattern.go`
- Tests:
  - `pkg/models/ir/codec/json/type_test.go`
  - `pkg/models/ir/codec/json/literal_test.go`
  - `pkg/models/ir/codec/json/pattern_test.go`


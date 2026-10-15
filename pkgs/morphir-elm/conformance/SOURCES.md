# Elm parity projects

Each directory under `projects/` is an Elm project with a `morphir.json`, its Elm sources in `src/` and
`expected/morphir-ir.json`, the output of `morphir-elm make` from npm `morphir-elm` 2.100.0 (pinned in
`pkgs/morphir-elm/scripts/package.json`).

Do not edit `expected/` or `parity_data_wbtest.mbt` by hand. After you change a project, run
`mise run elm:parity-refresh` from the repository root. It runs `morphir-elm make` on every project and
regenerates `parity_data_wbtest.mbt`.

| Project | Package | Covers | Origin | License |
| --- | --- | --- | --- | --- |
| `custom-types` | `Parity.Custom` | custom types with parameters and `comparable`, `T` and `T(..)` exports, a private type, constructor argument names, `case` on a custom type | own | Apache-2.0, this repository |
| `elm-attribute-model` | `Morphir.Attribute.Model` | the attribute model of the morphir-elm reference model: a `Bool` alias and an enumeration | finos/morphir-elm `71ca7ee`, `tests-integration/reference-model/attributemodel` | Apache-2.0, finos/morphir-elm |
| `elm-business-terms` | `Morphir.Remote.App` | the business terms of the morphir-elm CLI tests: aliases of `String`, `Int`, `Float` and `Bool` and an enumeration | finos/morphir-elm `71ca7ee`, `tests-integration/cli2-qa-test/test-data/business-terms` | Apache-2.0, finos/morphir-elm |
| `elm-decoration-model` | `Morphir.Decoration.Model` | the decoration model of the morphir-elm tests: record aliases, custom types with arguments, aliases across six modules | finos/morphir-elm `71ca7ee`, `tests-integration/decoration-model` | Apache-2.0, finos/morphir-elm |
| `elm-json-schema` | `TestModel` | the JSON Schema model of the morphir-elm tests: `Dict`, `Set`, `Result`, tuple, `Maybe` and record types, `Decimal`, `LocalDate`, `LocalTime` and `Month`, and aliases across modules | finos/morphir-elm `71ca7ee`, `tests-integration/json-schema/model` | Apache-2.0, finos/morphir-elm |
| `elm-reference-model` | `Morphir.Reference.Model` | the reference model of the morphir-elm tests, 50 modules: the widest SDK use (`Dict`, `Set`, `Result`, `String`, `Tuple`, `Morphir.SDK` `Aggregate`, `Decimal`, `List`, `LocalDate`, `Rule`, `StatefulApp` and `UUID`), records, custom types, `case`, `let`, lambdas, unannotated values, decision tables and long module names | finos/morphir-elm `71ca7ee`, `tests-integration/reference-model` | Apache-2.0, finos/morphir-elm |
| `elm-rentals` | `Morphir.Example.App` | the rentals model of the morphir-elm CLI tests: `if`, a comparison and `Result` constructors | finos/morphir-elm `71ca7ee`, `tests-integration/cli/test-data/rentals` | Apache-2.0, finos/morphir-elm |
| `elm-snowpark` | `CompanyAssets` | the Snowpark model of the morphir-elm tests: records, enumerations, `List.map` and `List.filter` with lambdas, `case` on tuples with `Maybe` patterns, a generic value and a module that exposes some of its names | finos/morphir-elm `71ca7ee`, `tests-integration/snowpark/model` | Apache-2.0, finos/morphir-elm |
| `elm-spark` | `SparkTests` | the Spark model of the morphir-elm tests, 24 modules: `Morphir.SDK.Aggregate`, `List` functions with lambdas and field accessors, `Maybe` pipelines, `case` on custom types, record results and aliases across modules | finos/morphir-elm `71ca7ee`, `tests-integration/spark/model` | Apache-2.0, finos/morphir-elm |
| `elm-typespec` | `TestModel` | the TypeSpec model of the morphir-elm tests: Dict, Set, Decimal, LocalDate and LocalTime types, custom types and aliases across modules | finos/morphir-elm `71ca7ee`, `tests-integration/typespec/model` | Apache-2.0, finos/morphir-elm |
| `examples-sample` | `Morphir.Sample` | 22 modules of the sample project of finos/morphir-examples: the liquidity coverage ratio rules (`Reg.LCR`): record aliases across modules, extensible-record arguments, a list of rule records, `Dict` and `LocalDate`; enumerations of countries and currencies; decision tables as nested `case` and as `case` on a constructor with `Maybe` patterns (`Rules.Direct`); `Morphir.SDK.Rule` and `String` (`Rules.RuleSet`); lambdas, `let` and `List` pipelines (`Apps.Trader.Logic`); a module outside the package that no module imports | finos/morphir-examples `74db4db`, `src/` of the root project | Apache-2.0, finos/morphir-examples |
| `examples-tutorial` | `Morphir.Example.App` | the last step of the morphir-examples tutorial, six modules: business-term aliases, enumerations, a record with nested records, `if` chains, `case` on a tuple with wildcards, `let`, `Result` and a module that no `exposedModules` entry names | finos/morphir-examples `74db4db`, `tutorial/step_3_catching_bugs` | Apache-2.0, finos/morphir-examples |
| `lambdas` | `Parity.Lambdas` | `\x y ->`, a lambda with a tuple argument, `wild _ y`, `mixed z ( a, b ) w`, `partial a = \b ->`, `paren a = (\x -> a)`, `prefix = (+)`, a value of a function alias (`handler : Handler`), a lambda passed to `List.map`: which arguments morphir-elm lifts into inputs | own | Apache-2.0, this repository |
| `lets` | `Parity.Lets` | let blocks in dependency order (`inOrder`, `reordered`, `x = 1; y = z; z = x`), a let function with and without an annotation, a destructuring let, a self-recursive let function, the `p q r s` cycle (`LetRecursion`) and a let value in a `Float` context (`scaled`) | own | Apache-2.0, this repository |
| `modules` | `Parity.Modules` | an exposed module that imports a module with an alias and `exposing` and uses a qualified name and an exposed type; a module reached only through a value body (kept, `Private`); a module named only in a value signature and a module used only as a constructor in a body (both dropped); an imported-but-unused module; an unreferenced module; module docs | own | Apache-2.0, this repository |
| `operators` | `Parity.Operators` | every operator that morphir-elm maps, on `Int`, `Float`, `Bool`, `String` and `List`; `\|>`, `<\|`, `>>`, `<<`; `(+)` and `(+) 1`; `-x`, `-1`, `-(f x)`, `-x ^ 2`; precedence and associativity; whole numbers in a `Float` context; hex, char and string literals with escapes | own | Apache-2.0, this repository |
| `patterns` | `Parity.Patterns` | `case` with wildcard, variable, int, hex, char, string, tuple, `[]`, `[ a ]`, `[ a, b ]`, `x :: xs`, constructor, nested and qualified (`Maybe.Just`) constructor, `as`, `()` and `True`/`False` patterns; `if` with `else if` | own | Apache-2.0, this repository |
| `records` | `Parity.Records` | a record alias, a record literal with its fields out of order, the alias constructor (`Point 1 2`, partial `Point 1`), `p.x`, `.x` passed to `List.map`, a record update of an argument and of a top-level value, a function on an extensible record | own | Apache-2.0, this repository |
| `sdk-modules` | `Parity.Sdk` | `Morphir.SDK.Decimal` and `Morphir.SDK.LocalDate` types in signatures | own | Apache-2.0, this repository |
| `signatures` | `Parity.Signatures` | variable, tuple, wildcard and unit arguments, leading lambdas (also in parentheses), a lambda with a tuple argument, partial arity, constrained variables (`number`, `comparable`, `appendable`) | own | Apache-2.0, this repository |
| `types-and-aliases` | `Parity.Types` | aliases of every type form and of the SDK types, declaration and module docs, and three doc placements: a doc directly above the first declaration of a module without imports, a `{-|` comment one blank row above a declaration, and a `{-|` comment between two declarations | own | Apache-2.0, this repository |
| `unannotated` | `Parity.Unannotated` | top-level values without an annotation (`un = 1`, `unannot a b = a`, `unannot2 a = a + 1`, `unFloat = 1.5 + 1`, `unRec r = r.x`, `useUn = unannot 1 2`) and an annotated value that uses them | own | Apache-2.0, this repository |

## Round-trip inputs

The round-trip test (`round_trip_wbtest.mbt`) uses the `expected/morphir-ir.json` of every project above and the
three classic fixtures of `pkgs/morphir-elm/fixtures`: `classic-greeting` (`v3-greeting.json`, from finos/morphir
`spec/ir/mck/node-address-fixtures`), and `classic-rentals-v1` and `classic-rentals-v2` (`v1-rentals.json` and
`v2-rentals.json`, from finos/morphir-elm `tests-integration/cli/test-data/rentals`). Their origin and license are in
`pkgs/morphir-ir/conformance/fixtures/README.md`.

## Changes to the projects

The projects from finos/morphir-elm keep their Elm sources as upstream has them, except for the edit listed for
`elm-decoration-model` and the file name listed for `elm-reference-model`. Their `morphir.json` has
`"sourceDirectory": "src"`, and `exposedModules` lists every module when upstream has none, because the frontend needs
at least one exposed module:

- `elm-rentals` and `elm-business-terms`: no change (the copies of rentals in `cli2/` and `cli2-qa-test/` are the
  same).
- `elm-typespec`: `exposedModules` added with all six modules.
- `elm-json-schema`: `decorations` removed; `exposedModules` added with all eight modules. The `attributemodel/`
  directory of the upstream project, which only the decoration uses, is not copied.
- `elm-snowpark`: `decorations` removed; `exposedModules` added with all four modules.
- `elm-decoration-model`: `exposedModules` added with all six modules. In `Database.elm`, `type alias Table = Table
  TableName` is changed to `type Table = Table TableName`. Upstream has a recursive type alias, which Elm 0.19.1
  refuses ("This type alias is recursive") and morphir-elm accepts; upstream should make the same change.
- `elm-attribute-model`: `exposedModules` added with both modules.
- `elm-reference-model`: `decorations` removed; `exposedModules` added with all 50 modules. The upstream
  `attributemodel/` directory and the other files beside `src/` are not copied. `TestModel/testing.elm` is renamed
  to `TestModel/Testing.elm`, the name of its module `Morphir.Reference.Model.TestModel.Testing`, as Elm requires.
- `elm-spark`: `exposedModules` added with all 24 modules.

`elm-typespec` declares the constructor `Bar` twice in `UnionTypes`, which Elm refuses and morphir-elm accepts. The
project keeps it; `round_trip_gaps` pins the result.

`elm-reference-model` has two inputs that Elm 0.19.1 refuses and morphir-elm accepts. The missing SDK modules stop
the frontend before them, so the project keeps them as upstream has them (bead morphir-ukvn.5.22.3.25). Upstream
should make these changes:

- `Values.elm`: `listFoldl2` and `listFoldr2` are annotated `List Int -> List Int -> List number`, but their body
  is `List Int` ("TYPE MISMATCH"). Annotate them `List Int -> List Int -> List Int`.
- `Insight/UseCase2.elm`: the `case departmentProcessName of` in `getDepartmentCode` has no branch for a `Just`
  other than `Just "SCIENCE"` ("MISSING PATTERNS"). Add `_ -> departmentCode`.

The projects from finos/morphir-examples keep their Elm sources as upstream has them, with their paths below `src/`:

- `examples-tutorial`: no change, except a final newline in `morphir.json`. Its `exposedModules` lists five of the
  six modules (`BusinessTerms` is not listed). Steps 1 and 2 of the tutorial are earlier versions of the same model,
  and step 1 is the same as `elm-rentals`, so they are not imported.
- `examples-sample`: a subset of the root project, which morphir-elm 2.100.0 cannot build (see the next section).
  The copy has these modules of `src/Morphir/Sample/`: `Reg/LCR/` `Basics`, `CentralBank`, `Counterparty`, `Product`,
  `MaturityBucket`, `Flows`, `Rules`, `FedCodeRules`, `FedCode` and `Inflows`; `Reg/Country` and `Reg/Currency`;
  `Rules/Direct` and `Rules/RuleSet`; every module of `Apps/Shared/`, `Apps/BooksAndRecords/Deal` and
  `Apps/Trader/Logic`. It also has `src/Company/Operations/BooksAndRecords.elm`, at its upstream path. Its module
  `Company.Operations.BooksAndRecords` is outside the package and no module imports it, so neither morphir-elm nor
  the frontend puts it in the output, and its `Morphir.SDK.StatefulApp` import gives no diagnostic. The
  `morphir.json` is new: the package is `Morphir.Sample` (upstream writes `Morphir/Sample`) and `exposedModules`
  lists the 22 modules of the package. Of the 13 upstream entries, only `Reg.LCR.FedCodeRules` and
  `Reg.LCR.Calculations` name a module. morphir-elm 2.100.0 built the subset at the first try, so no module was
  removed from it.

morphir-elm 2.100.0 refuses some Elm forms, so the own projects leave them out:

- `patterns` has no negative literal pattern (`-1 ->`). morphir-elm stops with a `ParserError` at the minus sign,
  and Elm 0.19.1 refuses it too ("It is not possible to pattern match on negative numbers").
- No project has a record pattern, a recursive destructuring, let-polymorphism, top-level mutual recursion or a
  tuple of more than three items. morphir-elm refuses the first four, and Elm refuses the last.

To keep `Cases.elm` under 60 lines, `patterns` matches char and string literals in one `case` on a tuple
(`textual`), and `()` and `True`/`False` in another (`flags`).

## Proposed upstream changes (not opened)

morphir-elm 2.100.0 cannot build the root project of finos/morphir-examples (`74db4db`): it overflows the stack
(item 6), with or without the `exposedModules` of the project. Items 2 to 4 each stop a build of the modules that
they name. Item 5 is not confirmed to stop a build: its module, `Apps/Trader/App.elm`, is also in item 3, which stops
the build first. Item 1 does not stop the build. The paths in items 2 to 6 are below `src/Morphir/Sample/`. The
changes are proposals only: PRs on finos/morphir-examples and issues on finos/morphir-elm wait for the maintainer's
approval.

1. finos/morphir-examples, `morphir.json`: 11 of the 13 `exposedModules` entries name no module (`LCR/Basics`,
   `Rules/Direct`, … while the modules are `Morphir.Sample.Reg.LCR.Basics`, `Morphir.Sample.Rules.Direct`, …), so
   morphir-elm exposes only `Reg.LCR.FedCodeRules` and `Reg.LCR.Calculations`. List the real names relative to the
   package (`Reg.LCR.Basics`), or remove the key.
2. finos/morphir-examples: `Morphir.SDK.App`, `Morphir.SDK.Average` and `Morphir.SDK.DictExtra` are not in the
   morphir-elm 2.100.0 SDK. `Apps/Approvals/Inventory/App.elm`, `Apps/Approvals/LocateList/App.elm` and `ACL.elm`,
   `Apps/Order/ACL.elm`, `Apps/Rates/App.elm`, `Apps/Upstream/Market/App.elm` and `Apps/Upstream/Product/App.elm`
   import them. Remove those modules or move them to the current SDK API.
3. finos/morphir-examples: `Apps/BooksAndRecords/App.elm`, `Apps/Order/App.elm` and `Apps/Trader/App.elm` use
   `statefulApp`, `cmdNone` and `Cmd`; `Morphir.SDK.StatefulApp` exposes only the type `StatefulApp(..)`.
4. finos/morphir-examples: `Reg/CDM/MiFIR/RTS22.elm` and `RTS22Alt.elm` import `List.Nonempty`, a third-party
   package.
5. finos/morphir-examples: `Apps/Trader/App.elm` uses `Debug.todo`.
6. finos/morphir-elm (issue): `morphir-elm make` overflows the stack (`RangeError`) on `Apps/Order/Order.elm`
   (`processBuy`, lines 213–241) and on `Reg/LCR/Outflows.elm`.

The projects from finos/morphir-elm (`71ca7ee`, `tests-integration/`) have inputs that Elm 0.19.1 refuses and
morphir-elm accepts. The corpus records them in "Changes to the projects". Upstream should make these changes:

7. finos/morphir-elm, `tests-integration/decoration-model/src/Morphir/Decoration/Model/Database.elm`:
   `type alias Table = Table TableName` is a recursive type alias. Write `type Table = Table TableName` (the corpus
   has this edit).
8. finos/morphir-elm, `tests-integration/reference-model/src/Morphir/Reference/Model/TestModel/testing.elm`: rename
   the file to `Testing.elm`, the name of its module `Morphir.Reference.Model.TestModel.Testing` (the corpus has
   this edit).
9. finos/morphir-elm, `tests-integration/reference-model/src/Morphir/Reference/Model/Values.elm`: annotate
   `listFoldl2` and `listFoldr2` as `List Int -> List Int -> List Int`, not `… -> List number`.
10. finos/morphir-elm, `tests-integration/reference-model/src/Morphir/Reference/Model/Insight/UseCase2.elm`: give
    the `case departmentProcessName of` in `getDepartmentCode` a branch `_ -> departmentCode`.
11. finos/morphir-elm, `tests-integration/typespec/model/src/TestModel/UnionTypes.elm`: the constructor `Bar` is
    declared twice, in `FooBarBaz` and in `Reference`. Rename one of them.

## Notices

Apache-2.0 section 4(d) asks a redistributed work to carry the `NOTICE` file of its origin. Both origin repositories
have a `NOTICE` file in their root, with the same text. No directory that the corpus copies has a `NOTICE` file of
its own.

The `NOTICE` file of finos/morphir-elm (`71ca7ee`) applies to `elm-attribute-model`, `elm-business-terms`,
`elm-decoration-model`, `elm-json-schema`, `elm-reference-model`, `elm-rentals`, `elm-snowpark`, `elm-spark` and
`elm-typespec`, and to the round-trip fixtures `classic-rentals-v1` and `classic-rentals-v2`:

```text
Morphir - FINOS
Copyright 2014 - 2020 Morgan Stanley

This product includes software developed at the Fintech Open Source Foundation (https://www.finos.org/).
This product includes software developed at Morgan Stanley.
```

The `NOTICE` file of finos/morphir-examples (`74db4db`) applies to `examples-sample` and `examples-tutorial`:

```text
Morphir - FINOS
Copyright 2014 - 2020 Morgan Stanley

This product includes software developed at the Fintech Open Source Foundation (https://www.finos.org/).
This product includes software developed at Morgan Stanley.
```

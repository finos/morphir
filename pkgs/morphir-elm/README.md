# Morphir Elm

## Purpose

`finos/morphir-elm` generates Elm source from current Morphir IR. The package `finos/morphir-elm/backend` lowers
IR to the [elm-syntax](https://package.elm-lang.org/packages/stil4m/elm-syntax/7.3.9/) AST of
[moonrockz/krueger](https://github.com/moonrockz/krueger) and prints it in the elm-format layout.

The backend has no engine, host, filesystem, process or network imports. It takes an `IRFile` and options, and it
returns the generated files as text. The same input and options give the same output bytes. The engine registers
the backend as the generation backend `elm`.

## Use from the engine

Set the backend in `morphir.toml`. The table `[backends.elm]` holds the options. All keys are optional.

```toml
[pipeline]
backend = "elm"

[backends.elm]
profile = "model"            # "model" (default) | "literal"
placeholders = "refuse"      # "refuse" (default) | "debug-todo"
width = 120
elm_package = "finos/morphir-elm 22.0.2"

[backends.elm.mapping]
"morphir/SDK:basics#add" = { operator = "+" }
"morphir/SDK:list#map" = { function = "List.map" }
"morphir/SDK:decimal#decimal" = { type = "Decimal.Decimal", import = "MyCo.Decimal as Decimal" }
"morphir/SDK:basics#max" = {}

[backends.elm.packages]
"acme/common" = { package = "acme/common 1.0.0" }
```

- `profile` selects the profile. See [Profiles](#profiles).
- `placeholders` tells the backend what to do with a value that has no body. `refuse` stops generation with
  `elm.placeholder`. `debug-todo` writes `Debug.todo "<reason>"`.
- `width` is the line width of the printer. It must be an integer from 1 to 1000.
- `elm_package` is the Elm package that supplies unmapped `Morphir.SDK` modules. The value is
  `"author/name major.minor.patch"`. The default is `finos/morphir-elm 22.0.2`.
- `mapping` adds, replaces or removes mapping entries. See [Mapping](#mapping).
- `packages` maps a Morphir dependency package to an Elm package. An entry has only the form
  `{ package = "author/name 1.2.3" }`.

The engine checks the table before it runs the backend. An unknown key or a bad value gives `elm.invalid_option`.
A bad mapping entry gives `elm.invalid_mapping`.

The `elm` backend declares no build targets. The engine uses `pipeline.validation = "source-only"` for it, and it
refuses `"required"` with `build.unsupported_target`.

## Profiles

There are two profiles.

The `model` profile (the default) writes idiomatic Elm. A reference that has a mapping entry uses that entry. The
IR for `a + b` becomes:

```elm
add : Int -> Int -> Int
add a b =
    a + b
```

The `literal` profile ignores the mapping. Every reference stays qualified. Use it as a debug view of the IR. The
same IR becomes:

```elm
add : Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Int -> Morphir.SDK.Basics.Int
add a b =
    Morphir.SDK.Basics.add a b
```

If you set `mapping` with the `literal` profile, the backend gives a warning and ignores the entries.

## Mapping

A mapping entry tells the `model` profile how to write a Morphir reference in Elm. An entry is one of these:

- `{ operator = "+" }`: an Elm operator. With two arguments it becomes `a + b`. With fewer arguments it becomes a
  prefix operator, for example `(+) a`. An operator entry takes no `import`.
- `{ function = "List.map" }`: an Elm value or constructor, qualified or not.
- `{ type = "Dict.Dict" }`: an Elm type, qualified or not.
- `{}`: removes the entry. The reference falls back to the qualified form.

A `function` or `type` entry can have an `import`, for example `import = "MyCo.Decimal as Decimal"`. The backend
adds that line to the imports of the module. With no `import`, the backend imports the qualifier of the name, unless
Elm imports that module by default.

### The built-in table

`scripts/generate-builtin-mapping.py` writes `backend/mapping_builtin.mbt` from
`pkgs/morphir-sdk/conformance/bindings.json`. The script maps every binding whose `semanticSource` is
`elm/core 1.0.5` to the elm/core function of the same name. It adds a hand-written list of types, constructors and
operators. The table has elm/core semantics only. Other SDK references stay qualified, for example
`Morphir.SDK.LocalDate.addDays`. Do not edit `mapping_builtin.mbt` by hand. Run the script again.

Every built-in entry is fully qualified, for example `Basics.max`, `Maybe.Just` or `Basics.Int`. The backend writes
the name bare (`max`, `Just`, `Int`) only when a default import exposes it and nothing can capture it. A lower-case
name must not be a top-level value of the module or a binder in the declaration. An upper-case name must not be a type
or constructor of the module. In Elm, a module's own names win over a default import. A user entry keeps its text as
written, so a bare entry such as `{ function = "max" }` always prints bare.

The script writes each key in the canonical form that migration gives for legacy IR. It splits the Elm name at
camelCase boundaries and digit runs, and joins a run of single letters into one initialism. For example, `map2` has the
key `morphir/SDK:list#map-2` and `LT` has the key `morphir/SDK:basics#LT`.

### Namespaces

Types and values have separate namespaces in the mapping. One FQName can be a type and a function, for example
`morphir/SDK:basics#never`. A type reference looks only at type entries. A value or constructor reference looks only
at value entries.

An override goes to the namespace of its kind. A `type` entry replaces the type entry for its key. An `operator` or
`function` entry replaces the value entry for its key. An empty entry `{}` removes the key from both namespaces.

### Keys

A key is any IR FQName in canonical text form, for example `morphir/SDK:basics#add`. The key does not have to be an
SDK reference. You can map references in your own packages to existing Elm code. A key that is not a canonical FQName gives
`elm.invalid_mapping`. If the key parses but has a different spelling, the detail gives the canonical spelling.

## Output

The backend writes one Elm package project:

```
elm.json
morphir.json
src/<Package>/<Module>.elm
```

- Each IR module becomes one file in `src/`. The Elm module name is the package path followed by the module path,
  for example `Acme.Shapes.Geometry` for package `acme/shapes` and module `geometry`.
- `elm.json` has `"type": "package"`. Its name is the first part of the Morphir package path, `/`, and the other
  parts joined with `-`, for example `acme/shapes`. It exposes the public modules. If no module is public, it exposes
  all modules.
- `morphir.json` has the Morphir package name, `"sourceDirectory": "src"` and the exposed modules.

The `elm.json` is a package, not an application. An application `elm.json` must list every indirect dependency with
an exact version, and that needs a dependency solver. A package `elm.json` takes version ranges. The dependencies
are:

- `elm/core` `1.0.5 <= v < 2.0.0`, always.
- The `elm_package`, only when the code uses an unmapped `Morphir.SDK` reference.
- One entry for each dependency package that has an entry in `packages`. A dependency package with no entry gives a
  warning, not an error. `elm make` then reports the missing modules.

### Declarations

- Declarations keep the IR order. Imports are sorted.
- Public types and values are exposed. Private ones are not. A custom type with public constructors is exposed as
  `T(..)`. A custom type with private constructors is exposed as `T`.
- An opaque type specification becomes a custom type with one hidden constructor, `<Type>Opaque`.
- Module documentation becomes the module doc comment. Member documentation becomes the doc comment of the
  declaration. An empty doc gives no doc comment.
- An Elm reserved word as a name gets the suffix `_`, for example `type_`.
- Elm updates only a record with a bare name. A record update of a local or of a value that prints without a
  qualifier names it: `{ origin | x = 1 }`. Any other record is first bound in a `let`, as `record_<n>`.
- A type variable with a `typeclass` constraint gets the Elm prefix of that class: `number`, `comparable`,
  `appendable` or `compappend`. An unconstrained variable whose name starts with one of these prefixes gets the
  prefix `t`, so Elm does not read it as constrained.

### Attributes

Elm has no place for some IR data. The backend writes that data as attributes in an `attributes` code block in the
doc comment. The attribute value is Elm data, so krueger can read it back.

```attributes
@morphir.entry { kind = "main", name = "run" }
@morphir.annotation { fqname = "acme/api:tags#stable" }
@morphir.external { platform = "js", name = "Math.max" }
```

- `@morphir.entry` marks the target value of an entry point in an `Application`.
- `@morphir.annotation` holds an annotation of a value specification. A compact annotation has `fqname` and an
  optional `text`. A structured annotation has `fqname` and `arguments`.
- `@morphir.external` holds one binding of an `ExternalBody`.

The arguments of a structured annotation must be data: literals, unit, lists, tuples, records, constructors and
constructor applications of data. Any other value, for example a function application or a variable, gives
`elm.annotation_argument`.

### Local names

Elm rejects a local name that shadows another name in scope. The backend renames such a name with a numeric suffix,
for example `x` becomes `x_1`.

Before each top-level value, the backend resets the set of used local names to the top-level value names of the
module. Locals in different top-level values do not affect each other. A local goes out of scope at the end of its
lambda, case branch, function or let block, so two branches or two lambdas can both use a name. Elm sees every name
of a let block in each definition of the block, so a name bound inside a definition that is also a name of the
block gets the suffix, and the let name keeps its name. The suffix counter does not reset, so the numbers increase
through the module.

A `let` function takes the patterns of the leading lambdas of its body as arguments: `loop n = loop n`, not
`loop = \n -> loop n`, which Elm refuses as a cyclic value.

A `let` function has a type signature only when its type has no type variable. Elm reads type variables in a
`let` signature as new rigid variables, so a signature with one could make valid code fail.

## Refusals

The backend raises `ElmGenerationError`. `Refused` holds one `Problem`. `Failed` holds the problems of all failing
modules. A `Problem` has a `code`, a `node_path` and a `detail`. The `node_path` is the canonical FQName of the IR
node, or the option key.

Generation of a module stops at its first problem. The backend tries all modules, so one run reports every failing
module.

| Code | Cause |
| --- | --- |
| `elm.tuple_arity` | A tuple with fewer than two or more than three elements. Elm tuples have two or three. |
| `elm.derived_type` | A derived type. |
| `elm.decimal_literal` | A decimal literal. There is no decimal construction mapping yet. |
| `elm.placeholder` | A construct with no body while `placeholders = "refuse"`, a custom type with no constructors, or an incomplete type definition. |
| `elm.invalid_mapping` | A mapping entry that is not valid, for example a bad key or a constructor that maps to an operator. |
| `elm.print` | krueger could not print the AST. The path names the IR declaration. This is a backend defect. |
| `elm.int_literal` | An integer lexeme outside the Int64 range. |
| `elm.document_literal` | A document literal. Elm has no document literal. |
| `elm.literal_pattern` | A float or decimal pattern. Elm rejects these patterns. |
| `elm.unsupported_constraint` | A `typeclass` constraint that has no Elm class, or that is not text or a list of text. |
| `elm.name_collision` | Two IR names in one module give the same Elm name. |
| `elm.annotation_argument` | A structured annotation argument that is not data. |
| `elm.invalid_option` | An unknown option key or a bad option value. |
| `elm.cancelled` | The caller cancelled the generation. |

## Limits

- The backend does not write regular comments. krueger prints doc comments only.
- Derived types and decimal literals are refused (`elm.derived_type` and `elm.decimal_literal`).
- `elm make --optimize` rejects `Debug.todo`. Code generated with `placeholders = "debug-todo"` compiles only
  without `--optimize`.
- The `finos/morphir-elm` Elm package has no `Morphir.SDK.Maybe` module. An unmapped `morphir/SDK:maybe` reference,
  for example `morphir/SDK:maybe#has-value`, gives code that `elm make` rejects. Add a mapping entry for it.
- `packages` takes only Elm packages. Dependency source directories are not supported.

## Frontend

The frontend reads an Elm project and gives the v4 Morphir IR of it. The output is the same as the output of
`morphir-elm make` 2.100.0, with these differences: the shared IR inference (`finos/morphir-typing`) gives the
types, so some types differ from those of morphir-elm (rule 22), and top-level mutual recursion is accepted
(rule 21).

```moonbit
pub fn compile_project(
  sources : Array[ElmSource],   // every .elm file: path relative to the source directory, and content
  package_name : String,        // the dotted package name, for example "My.Pkg"
  exposed : Array[String],      // the exposed modules relative to the package, as in morphir.json
  output? : OutputModules = Parity,  // Parity: the modules of morphir-elm; Referenced: also every module the output names
) -> @ir.IRFile raise ElmFailed
```

The result is a `Library` with no dependencies. `ElmFailed` holds the problems of the first pass that failed. Each
pass reports all of its problems together. An empty `exposed` list stops the compile before any source is parsed.
Then the passes are: parse, module rules (module name, port and effect modules), import cycles, exposed modules,
exports and imports, name references, lowering and inference. As in morphir-elm,
the parse and import cycle passes check every source. The other passes check only the modules that morphir-elm
processes (rule 2), also when such a module is not in the output. A problem of these kinds in a module that nothing
imports does not stop the compile. An `ElmProblem` has a `code`, a `message`, the source `path` and the `location`
in the file when it is known. An empty `exposed` list gives a problem with an empty path. A missing exposed module
gives a problem at the source path where the module must be.

`output` chooses the output modules. `Parity`, the default, keeps the modules that morphir-elm keeps (rule 2), so the
output can name a type of a module that it drops: a module named only in a value signature or used only as a
constructor. `Referenced` also keeps every processed module that an output module names, transitively, in type
definitions, value signatures, value bodies, patterns and inferred types. An added module keeps the access of
rule 2. The engine's Elm provider uses `Referenced`, because generated Elm and MoonBit must not name a missing module.

There are four packages:

- `finos/morphir-elm/mapping`: Elm names to Morphir names, and the elm/core table.
- `finos/morphir-elm/frontend`: parsing, module rules, module selection, access, docs and `compile_project`.
- `finos/morphir-elm/frontend/resolve`: the project symbol table, exports, imports and name resolution.
- `finos/morphir-elm/frontend/lower`: type definitions and value definitions (signatures and bodies) to IR.

| Code | Cause |
| --- | --- |
| `elm.parse` | A file does not parse. |
| `elm.module_name` | The module name does not match the file path, or does not start with the package name. |
| `elm.import_cycle` | The imports form a cycle. The problem is at the import that closes the cycle. |
| `elm.exposed_module` | The exposed list is empty, or an exposed module has no source file. |
| `elm.unresolved_name` | A name, or an entry of an exposing list, that does not resolve. |
| `elm.ambiguous_name` | A name used in the code that two imports give with different meanings. |
| `elm.unsupported_module` | An import of a module that is not a project, elm/core, platform or `Morphir.SDK` module. |
| `elm.unsupported_value` | A reference to an elm/core value or operator that has no Morphir SDK binding, or an operator that is not in the operator table (rule 13). |
| `elm.unsupported` | A port, an effect module, an infix declaration, top-level destructuring, a record pattern, a recursive destructuring in a let block, GLSL, an operator in the exposing list of a module, or a name from `Debug`, `Platform`, `Platform.Cmd` or `Platform.Sub` (for example `Debug.log`, `Cmd` or `Program`). |
| `elm.unbound_type_variable` | A type variable that the type alias or custom type does not declare. |
| `elm.type` | A type error that inference finds. The message is the inference problem (`<code> at <logical path>: <message>`), the path is the source of its module and the location is the source of its node, when it is known. |

The frontend follows these morphir-elm rules (probes of `morphir-elm make` 2.100.0):

1. The `morphir.json` `exposedModules` entries are module names relative to the package name (`"Types"` for
   `My.Pkg.Types`).
2. morphir-elm processes the exposed modules and the project modules that they import, transitively. The output
   keeps the exposed modules and the processed modules that they reach in the module graph, transitively. A module
   depends on the modules of the names in its type definitions (the constructors of a custom type count, whatever
   their access) and of the value references in its value bodies: values, operators other than `<|` and `|>`, and
   `Basics.negate` for a negation of anything but a number literal. A module that is named only in value
   signatures, used only through constructors in bodies, imported and not used, or not imported, is not in the
   output. The graph compares module paths without the package, so a project module with the path of an SDK module
   that is used (for example `My.Pkg.Basics` and `Int`) is kept. Every output module keeps all of its declarations.
3. The exposed modules are `Public`. A module that is not exposed is `Public` when an exposed module shows one of
   its types: as the target of a public type alias, as a constructor argument of a public type with public
   constructors, or in the signature of a public value. This continues through the public definitions of the types
   that it reaches. morphir-elm takes the names in Elm order and follows only the first name that it finds in each
   module. All other output modules are `Private`.
4. A type exported as `T` is `Public` with `Private` constructors. `T(..)` gives `Public` constructors. A type or
   value that the module does not export is `Private`.
5. The module path is the module name without the package prefix (`My.Pkg.Types` in package `My.Pkg` is
   `["types"]`).
6. A declaration doc keeps the raw text between `{-|` and `-}`: `{-| A point. -}` gives `" A point. "` and
   `{-| D.-}` gives `" D."`. A declaration without a doc gets `""`. The module doc is the first `{-|` comment in the
   file that is not a declaration doc, without its first 3 and its last 3 characters. Thus the character before
   `-}` goes too, whatever it is: `{-| Doc. -}` gives `" Doc."`, `{-| Doc.-}` gives `" Doc"`, `{-| Doc.  -}` gives
   `" Doc. "` and `{-| Doc.\n\n-}` gives `" Doc.\n"`. A module without one has no doc.
7. A `{-|` comment is the doc of a declaration only when the declaration starts on the row directly after the row
   where the comment ends. A blank line between them makes the comment an ordinary comment. Thus a `{-|` comment
   directly above the first declaration is the doc of that declaration, not the module doc.
8. The arguments of a top-level value are the declaration arguments, then the arguments of the leading lambdas in
   the body, looking through parentheses. Inputs are lifted from the front of this list while the lowered pattern
   is a variable (`x`, `(x)` and `_ as x`) and, when the value has an annotation, the rest of the annotation is a
   function type (also in parentheses). Anything else, also a type alias of a function type, stops the inputs. An
   unannotated value lifts every leading variable, each with a placeholder type. The output type is the rest of the
   annotation. The arguments that are not lifted stay in the body as one `Lambda` each. Thus `wild _ y = y` has no
   inputs and the body `Lambda(_, Lambda(y, y))`. `f : Handler` with `type alias Handler = Int -> Int` and
   `f x = x` has no inputs, the output `Handler` and the body `Lambda(x, x)`. `h : Int -> Handler` with
   `h a b = a` has the input `a : Int`, the output `Handler` and the body `Lambda(b, a)`.
9. A record pattern fails in morphir-elm, in every position. The frontend gives `elm.unsupported` for it.
10. Literals: `1` and `0xFF` are `IntegerLiteral` (`"1"`, `"255"`). `-1` and `-2.5` fold into the literal.
    `-(1)` and `-x` are `Apply(Reference basics#negate, …)`. `1.5` is `FloatLiteral`. Char and string literals are
    decoded (`"\u{0041}"` is `"A"`). Unqualified `True` and `False` are `BoolLiteral`.
11. Names: a local name is `Variable`. A lower-case global name is `Reference`. An upper-case global name is
    `Constructor`, also a record alias constructor such as `Point 1 2`, with the alias name.
12. `f a b` is `Apply(Apply(f, a), b)`. `a |> f` and `f <| a` are `Apply(f, a)`. `(+)` is the `Reference` of the
    operator function.
13. Every other binary operator `a op b` is `Apply(Apply(Reference op, a), b)`, with this fixed table (all in
    `basics`, except `::`). An operator that is not in the table gives `elm.unsupported_value`.

    | Operator | Function | Operator | Function | Operator | Function |
    | --- | --- | --- | --- | --- | --- |
    | `\|\|` | `or` | `<=` | `lessThanOrEqual` | `/` | `divide` |
    | `&&` | `and` | `>=` | `greaterThanOrEqual` | `//` | `integerDivide` |
    | `==` | `equal` | `++` | `append` | `^` | `power` |
    | `/=` | `notEqual` | `+` | `add` | `<<` | `composeLeft` |
    | `<` | `lessThan` | `-` | `subtract` | `>>` | `composeRight` |
    | `>` | `greaterThan` | `*` | `multiply` | `::` | `list#cons` |

14. `if` is `IfThenElse`. `case` is `PatternMatch`, with the cases in source order.
15. Patterns: `_` is `WildcardPattern`. `x` is `AsPattern(WildcardPattern, x)`. Integer, hex, char and string
    literal patterns are `LiteralPattern`. `True` and `False` are `LiteralPattern(BoolLiteral)`. Tuples are
    `TuplePattern`. `[]` is `EmptyListPattern`. `[a, b]` is `HeadTailPattern(a, HeadTailPattern(b,
    EmptyListPattern))`. `x :: xs` is `HeadTailPattern`. A constructor has its argument patterns. `p as n` is
    `AsPattern`. `()` is `UnitPattern`. A pattern in parentheses is its inner pattern.
16. `\x y -> b` is `Lambda(x, Lambda(y, b))`, one `Lambda` for each argument.
17. Records: `{ y = 2, x = 1 }` is `Record`. `p.x` is `Field`. `.x` is `FieldFunction`. `{ p | x = 1 }` is
    `UpdateRecord`, with the target as `Variable` (a local name) or `Reference` (a global name). Tuples, lists and
    unit are `Tuple`, `List` and `Unit`.
18. Let: a let function or value is `LetDefinition(name, definition, in)`. The definition has no inputs. Its output
    is the let annotation or, when there is no annotation, a placeholder. Its body is the `Lambda` chain of its
    arguments. Let definitions are never lifted. A destructuring let is `Destructure(pattern, value, in)`. A group
    of let definitions that refer to each other (or one that refers to itself) is `LetRecursion`. A recursive
    destructuring gives `elm.unsupported`.
19. The let chain is in dependency order, not in source order, as morphir-elm builds it with
    elm-community/graph 6.0.0. The dependencies are the unqualified names that each right-hand side mentions. When
    there is no cycle, the chain is the depth-first post-order of the declarations, outermost first. When there is
    a cycle, the chain is the reverse of the Kosaraju components, outermost first.
20. Each value node and each pattern node has the source location of its Elm code.
21. morphir-elm refuses top-level mutual recursion (`ValueCycleDetected`). Elm accepts it, and the frontend accepts
    it too.
22. The last pass is `@typing.infer(file, sdk, Fill)` with the Morphir SDK specification. It gives every value and
    pattern node an `inferred_type`, and it replaces each placeholder of an unannotated value or let definition with
    its solution. It sees every processed module, also one that the output drops (rule 2), because a value
    signature can name a type of such a module. The types can differ from those of morphir-elm: inference
    generalizes a let definition (morphir-elm does not), and morphir-elm types an unannotated top-level value in a
    first pass without the other values.
23. After inference, a whole-number literal of type `Float` becomes a `FloatLiteral`, as morphir-elm
    `Infer.fixNumberLiterals` does: `fi : Float` with `fi = 2` gives `FloatLiteral(2.0)`. An alias of `Float` counts,
    with one alias resolved only (`Distribution.resolveType`): an alias of an alias of `Float` keeps the whole
    number. The rewrite reaches the values of every body and let definition, not the patterns. A literal that
    nothing fixes keeps its `number` type variable. Because inference generalizes a let definition (rule 22), a let
    value can keep a whole number where morphir-elm writes a float: in `scaled price = let rate = 2 in price * rate`
    with `scaled : Float -> Float`, `rate` stays `IntegerLiteral "2"` of type `number`. The parity test then finds a
    body difference, and a body difference hides the type comparison of that value (bead morphir-ukvn.5.22.7.1).

`Tuple.*` values are not supported yet, because the Morphir SDK spec has no Tuple module (bead
morphir-ukvn.5.22.3.4).

## Tests

```shell
moon test pkgs/morphir-elm/backend       # unit and generation tests
moon test pkgs/morphir-elm/conformance   # frontend parity with morphir-elm make and the IR round trip
mise run test:elm                        # elm make on the generated fixture projects
mise run elm:parity-refresh              # regenerate the parity corpus after a project change
```

The parity test compiles each Elm project in `pkgs/morphir-elm/conformance/projects` with `compile_project` and
compares the result with `expected/morphir-ir.json`, the output of the pinned npm `morphir-elm` 2.100.0. It
compares the modules, types and values, with their access and docs, the type definitions, the value inputs and
output, and the shape of each value body. The declared input, output and let signature types compare exactly,
without alias expansion, because morphir-elm writes them from the source (`value <module>#<name>: inputs`,
`output` or `let signatures`). A position where morphir-elm wrote a placeholder (`t<n>`) is not compared. The shape is the body with every value attribute removed and every let
signature type set to `()`; a `Record` and a `LetRecursion` compare as maps. A body with another shape is one
`value <module>#<name>: body` line. When the shapes are the same, `@typing.compare_types` compares every node type
and signature type of the value, after alias expansion and with one variable renaming per declaration. Each
difference is one `type <path>: expected <t1>, found <t2>` line. The comparison masks the morphir-elm placeholders
(`t<n>`) in signatures (`mask_signatures=true`), because morphir-elm writes the signature of an unannotated value
from a first inference pass; the node types are compared everywhere. Type attributes do not count, and a doc of
`None` is the same as `""`. When the frontend fails, each problem is a `compile: <code> <path> <message>` line.

A known difference goes in `parity_gaps` (in `parity_gaps_wbtest.mbt`) with its reason and a bead. The test fails
when a pinned difference goes away, so remove the line when the gap closes. The pinned inference differences today:
`@typing` generalizes let definitions and morphir-elm does not (morphir-ukvn.5.22.7.1); morphir-elm prints the row
variable of an open record as `t<n>` (morphir-ukvn.5.22.7.2); morphir-elm writes node types with aliases expanded,
which shows when the alias's module is not in the output (morphir-ukvn.5.22.7.3); morphir-elm prints a number-class
variable as `t<n>`, without its class (morphir-ukvn.5.22.7.4); morphir-elm types a reference to an unannotated value
with its first-pass declared type (morphir-ukvn.5.22.7.5); the definitions of a morphir-elm `LetRecursion` do not see
each other, so their nodes can keep free variables (morphir-ukvn.5.22.7.6).

The round-trip test (`round_trip_wbtest.mbt`) checks IR to Elm to IR. It generates Elm from an IR with the backend
and `Options::default()`, compiles the generated `src/` files with `compile_project`, with the package name and the
exposed modules of the generated `morphir.json`, and compares the result with the input IR by the same rules as the
parity test. The inputs are the expected IR of every parity project (`parity-<project>`) and the three classic
fixtures of `finos/morphir-elm/fixtures` (`classic-greeting`, `classic-rentals-v1`, `classic-rentals-v2`). When the
backend refuses an input, each problem is a `generate: <code> <detail>` line; when the frontend fails, a `compile:`
line. A known difference goes in `round_trip_gaps` (in `round_trip_gaps_wbtest.mbt`) with its reason and a bead, and
the test fails when a pinned difference goes away. The pinned differences today: the inference gaps of the parity
test come back, because the frontend infers the generated Elm as it infers the project source; the printer trims the
whitespace at the ends of a doc (morphir-ukvn.5.22.3.7); the morphir-elm output of `modules` names modules that it
drops, so the generated Elm imports modules that do not exist (morphir-ukvn.5.22.3.8); and the morphir-elm
first-pass signatures of unannotated values (`un : t0`) are annotations that Elm and the frontend refuse
(morphir-ukvn.5.22.3.9).

After you change a project, run `mise run elm:parity-refresh` from the repository root. It needs network access
for `bun install --frozen-lockfile`. It runs `morphir-elm make` on every project and writes `expected/morphir-ir.json` and
`parity_data_wbtest.mbt`, both with the IR as compact JSON. Commit both. CI runs the refresh in the native build job and fails when `pkgs/morphir-elm/conformance` changes.

`mise run test:elm` installs the pinned npm `elm` 0.19.1 package in `scripts/` and runs
`scripts/test-elm-make.mts`. The script runs `pkgs/morphir-elm/acceptance`, which prints the generated projects for
the fixtures `rentals`, `shapes` and `specs` as JSON. It writes each project to a temporary directory and runs
`elm make` on its modules. The `specs` project uses `placeholders = "debug-todo"`. The first run needs network access,
because `elm make` downloads its packages. CI runs this task in the native build job.

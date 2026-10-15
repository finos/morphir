///|
/// Known differences from morphir-elm make, by project. Each line needs a comment with the reason and a bead.
/// The parity test fails when a pinned difference disappears, so remove the line when the gap closes.
fn parity_gaps() -> Map[String, Array[String]] {
  Map([
    (
      "elm-json-schema",
      [
        // The SDK specification has no `Morphir.SDK.LocalTime`. Bead morphir-ukvn.5.22.3.15. The missing
        // `Morphir.SDK.LocalDate.Month` comes next. Bead morphir-ukvn.5.22.3.16.
        "compile: elm.unsupported_module TestModel/AdvancedTypes.elm the package of Morphir.SDK.LocalTime is not supported",
      ],
    ),
    (
      "elm-reference-model",
      [
        // The SDK specification has no `Morphir.SDK.StatefulApp` (bead morphir-ukvn.5.22.3.21), `Aggregate`
        // (morphir-ukvn.5.22.3.19), `Rule` (morphir-ukvn.5.22.3.20) or `UUID` (morphir-ukvn.5.22.3.22). Behind them,
        // a probe found the `LocalDate` values (morphir-ukvn.5.22.3.23 and .16), `Tuple` (morphir-ukvn.5.22.3.4),
        // two inputs that Elm refuses (morphir-ukvn.5.22.3.25) and inference gaps (morphir-ukvn.5.22.7.1 and .4).
        "compile: elm.unsupported_module Morphir/Reference/Model/BooksAndRecords.elm the package of Morphir.SDK.StatefulApp is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue364.elm the package of Morphir.SDK.Aggregate is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue409.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue448.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/PatternModel/BasicRule.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/SDK/UUID.elm the package of Morphir.SDK.UUID is not supported",
      ],
    ),
    (
      "elm-spark",
      [
        // The SDK specification has no `Morphir.SDK.Aggregate`. Bead morphir-ukvn.5.22.3.19. Behind it, a probe found
        // the let generalization of `rules/income/antique` (bodies of is-item-antique and is-item-vintage). Bead
        // morphir-ukvn.5.22.7.1.
        "compile: elm.unsupported_module SparkTests/AggregationTests.elm the package of Morphir.SDK.Aggregate is not supported",
      ],
    ),
    (
      "elm-typespec",
      [
        // As in elm-json-schema. Beads morphir-ukvn.5.22.3.15 and morphir-ukvn.5.22.3.16.
        "compile: elm.unsupported_module TestModel/AdvancedTypes.elm the package of Morphir.SDK.LocalTime is not supported",
      ],
    ),
    (
      "examples-sample",
      [
        // The SDK specification has no `Morphir.SDK.Rule`. Bead morphir-ukvn.5.22.3.20. Behind it, a probe found the
        // `LocalDate` values `diffInDays` and `diffInYears` (morphir-ukvn.5.22.3.23), then inference gaps: let
        // generalization in `processPriceChange` (morphir-ukvn.5.22.7.1), row variable names (morphir-ukvn.5.22.7.2)
        // and the open records of `inflowRules` (morphir-ukvn.5.22.7.7).
        "compile: elm.unsupported_module Morphir/Sample/Rules/RuleSet.elm the package of Morphir.SDK.Rule is not supported",
      ],
    ),
    (
      "lets",
      [
        // morphir-elm has no let-polymorphism: the let values of inOrder and chain get the type of their use, Int.
        // @typing generalizes them to number. Bead morphir-ukvn.5.22.7.1. The unused `b = 2` keeps an unsolved
        // number variable, which morphir-elm prints as `t<n>` without its class. Bead morphir-ukvn.5.22.7.4.
        "type value:parity/lets:blocks#in-order/body/definition/body: expected morphir/SDK:basics#int, found number-a",
        "type value:parity/lets:blocks#in-order/body/in/definition/body: expected t-4, found number-b",
        // The self-recursive `loop` is generalized by @typing (`a -> b`) and instantiated with a number literal;
        // morphir-elm types it once, `t1 -> Int`, and prints the literal's number variable without its class. Beads
        // morphir-ukvn.5.22.7.1 and morphir-ukvn.5.22.7.4.
         "type value:parity/lets:blocks#self-recursive/body/definitions/loop/body: expected (t-1 -> morphir/SDK:basics#int), found (a -> b)",
        "type value:parity/lets:blocks#self-recursive/body/definitions/loop/body/body: expected morphir/SDK:basics#int, found b",
        "type value:parity/lets:blocks#self-recursive/body/definitions/loop/body/body/function: expected (t-1 -> morphir/SDK:basics#int), found (a -> b)",
        "type value:parity/lets:blocks#self-recursive/body/in/function: expected (t-1 -> morphir/SDK:basics#int), found (number-a -> morphir/SDK:basics#int)",
        "type value:parity/lets:blocks#self-recursive/body/in/argument: expected t-1, found number-a",
        // Let generalization: x, z and y get the type of their use, Int, in morphir-elm. Bead morphir-ukvn.5.22.7.1.
         "type value:parity/lets:blocks#chain/body/definition/body: expected morphir/SDK:basics#int, found number-a",
        "type value:parity/lets:blocks#chain/body/in/definition/body: expected morphir/SDK:basics#int, found number-b",
        "type value:parity/lets:blocks#chain/body/in/in/definition/body: expected morphir/SDK:basics#int, found number-c",
        // The definitions of a LetRecursion do not see each other in morphir-elm, so `r`, which the in-value does not
        // use, keeps the free variables `t1 -> t0`. @typing solves the group together and generalizes it, so q, r, p
        // and s get variables where morphir-elm has Int, and the literal prints its class. Beads
        // morphir-ukvn.5.22.7.6, morphir-ukvn.5.22.7.1 and morphir-ukvn.5.22.7.4.
         "type value:parity/lets:blocks#mutual/body/definitions/q/body: expected (t-10 -> morphir/SDK:basics#int), found (a -> b)",
        "type value:parity/lets:blocks#mutual/body/definitions/q/body/body: expected morphir/SDK:basics#int, found b",
        "type value:parity/lets:blocks#mutual/body/definitions/q/body/body/function: expected (t-10 -> morphir/SDK:basics#int), found (a -> b)",
        "type value:parity/lets:blocks#mutual/body/definitions/r/body: expected (t-1 -> t-0), found (a -> b)",
        "type value:parity/lets:blocks#mutual/body/definitions/r/body/pattern: expected t-1, found a",
        "type value:parity/lets:blocks#mutual/body/definitions/r/body/pattern/pattern: expected t-1, found a",
        "type value:parity/lets:blocks#mutual/body/definitions/r/body/body/function: expected (t-1 -> t-0), found (a -> b)",
        "type value:parity/lets:blocks#mutual/body/definitions/r/body/body/argument: expected t-1, found a",
        "type value:parity/lets:blocks#mutual/body/in/definition/body: expected morphir/SDK:basics#int, found c",
        "type value:parity/lets:blocks#mutual/body/in/definition/body/function: expected (t-10 -> morphir/SDK:basics#int), found (number-a -> c)",
        "type value:parity/lets:blocks#mutual/body/in/definition/body/argument: expected t-10, found number-a",
        "type value:parity/lets:blocks#mutual/body/in/in/definition/body: expected morphir/SDK:basics#int, found d",
        // morphir-elm types `rate = 2` from its use in `price * rate`, Float, and writes `FloatLiteral 2`. @typing
        // generalizes the let value to `number`, so the literal stays `IntegerLiteral "2"`. The body difference
        // also turns off the type comparison of `scaled`. Bead morphir-ukvn.5.22.7.1.
         "value blocks#scaled: body",
        // Let generalization: `f x = x` is `Int -> Int` in morphir-elm, from its use. Bead morphir-ukvn.5.22.7.1.
         "type value:parity/lets:blocks#function/body/definition/body: expected (morphir/SDK:basics#int -> morphir/SDK:basics#int), found (a -> a)",
        "type value:parity/lets:blocks#function/body/definition/body/pattern: expected morphir/SDK:basics#int, found a",
        "type value:parity/lets:blocks#function/body/definition/body/pattern/pattern: expected morphir/SDK:basics#int, found a",
        "type value:parity/lets:blocks#function/body/definition/body/body: expected morphir/SDK:basics#int, found a",
        // The unused `b = 1` and `a = b` keep one unsolved number variable, printed `t0` by morphir-elm; @typing
        // generalizes `b` and keeps the class. `c = 2` is Int from its use in morphir-elm. Beads
        // morphir-ukvn.5.22.7.4 and morphir-ukvn.5.22.7.1.
         "type value:parity/lets:blocks#reordered/body/definition/body: expected t-0, found number-a",
        "type value:parity/lets:blocks#reordered/body/in/definition/body: expected t-0, found number-b",
        "type value:parity/lets:blocks#reordered/body/in/in/definition/body: expected morphir/SDK:basics#int, found number-c",
      ],
    ),
    (
      "modules",
      [
        // morphir-elm writes node types with their aliases expanded; @typing keeps alias names. morphir-elm drops
        // module Sig, so neither output defines `sig#code` and the comparison cannot expand it. Bead
        // morphir-ukvn.5.22.7.3.
        "type value:parity/modules:api#is-blank/body/function: expected (morphir/SDK:string#string -> morphir/SDK:basics#bool), found (parity/modules:sig#code -> morphir/SDK:basics#bool)",
        "type value:parity/modules:api#is-blank/body/function/function: expected (morphir/SDK:string#string -> (morphir/SDK:string#string -> morphir/SDK:basics#bool)), found (parity/modules:sig#code -> (parity/modules:sig#code -> morphir/SDK:basics#bool))",
        "type value:parity/modules:api#is-blank/body/function/argument: expected morphir/SDK:string#string, found parity/modules:sig#code",
      ],
    ),
    (
      "records",
      [
        // morphir-elm prints the row variable of an open record as `t<n>`, not as the declared `a`. Bead
        // morphir-ukvn.5.22.7.2.
        "type value:parity/records:points#read-x/body/record: expected { t-0 | x : morphir/SDK:basics#int }, found { a | x : morphir/SDK:basics#int }",
      ],
    ),
    (
      "signatures",
      [
        // @typing generalizes the let function `mark`; morphir-elm has no let-polymorphism and gives it the type
        // of its use, `a -> ( a, Bool )`. Bead morphir-ukvn.5.22.7.1.
        "type value:parity/signatures:constrained#pairs/body/definition/body: expected (a -> (tuple a morphir/SDK:basics#bool)), found (b -> (tuple b morphir/SDK:basics#bool))",
        "type value:parity/signatures:constrained#pairs/body/definition/body/pattern: expected a, found b",
        "type value:parity/signatures:constrained#pairs/body/definition/body/pattern/pattern: expected a, found b",
        "type value:parity/signatures:constrained#pairs/body/definition/body/body: expected (tuple a morphir/SDK:basics#bool), found (tuple b morphir/SDK:basics#bool)",
        "type value:parity/signatures:constrained#pairs/body/definition/body/body/items/0: expected a, found b",
      ],
    ),
    (
      "types-and-aliases",
      [
        // morphir-elm prints the row variable of an open record as `t<n>`, not as the declared `a`. Bead
        // morphir-ukvn.5.22.7.2.
        "type value:parity/types:aliases#label/body/record: expected { t-5 | label : morphir/SDK:string#string }, found (parity/types:aliases#labeled a)",
      ],
    ),
    (
      "unannotated",
      [
        // An unsolved number variable: morphir-elm prints it as `t<n>` without its class; @typing keeps `number`.
        // Bead morphir-ukvn.5.22.7.4.
        "type value:parity/unannotated:free#un/body: expected t-0, found number-a",
        "type value:parity/unannotated:free#use-un/body: expected t-4, found number-a",
        "type value:parity/unannotated:free#use-un/body/function: expected (t-2 -> t-4), found (number-b -> number-a)",
        "type value:parity/unannotated:free#use-un/body/function/function: expected (t-4 -> (t-2 -> t-4)), found (number-a -> (number-b -> number-a))",
        "type value:parity/unannotated:free#use-un/body/function/argument: expected t-4, found number-a",
        "type value:parity/unannotated:free#use-un/body/argument: expected t-2, found number-b",
        // morphir-elm types the reference `unannot2 3` with the first-pass declared type of unannot2, `t0 -> t4`, so
        // the argument stays a free variable; @typing uses the solved `number -> number`. Bead morphir-ukvn.5.22.7.5.
         "type value:parity/unannotated:free#total/body/function/argument/argument/function: expected (t-25 -> morphir/SDK:basics#int), found (morphir/SDK:basics#int -> morphir/SDK:basics#int)",
        "type value:parity/unannotated:free#total/body/function/argument/argument/argument: expected t-25, found morphir/SDK:basics#int",
        // The number variable of unannot2 prints as `t<n>` in morphir-elm. Bead morphir-ukvn.5.22.7.4.
         "type value:parity/unannotated:free#unannot-2/body: expected t-4, found number-a",
        "type value:parity/unannotated:free#unannot-2/body/function: expected (t-4 -> t-4), found (number-a -> number-a)",
        "type value:parity/unannotated:free#unannot-2/body/function/function: expected (t-4 -> (t-4 -> t-4)), found (number-a -> (number-a -> number-a))",
        "type value:parity/unannotated:free#unannot-2/body/function/argument: expected t-4, found number-a",
        "type value:parity/unannotated:free#unannot-2/body/argument: expected t-4, found number-a",
      ],
    ),
  ])
}

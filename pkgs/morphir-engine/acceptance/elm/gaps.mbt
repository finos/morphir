///|
/// Corpus projects that do not generate yet, by `<project>/<backend>`, with the start of the first engine
/// diagnostic. `moon build` and `elm make` do not check them. Each entry has a comment with its reason and bead;
/// MoonBit generic values wait for `morphir-ukvn.5.22.11`.
let gaps : Map[String, String] = Map::from_array([
  // Generic custom type `Tree a` (morphir-ukvn.5.22.11).
  ("custom-types/moonbit", "moonbit.unsupported_type"),
  // The SDK specification has no `Morphir.SDK.LocalTime` (morphir-ukvn.5.22.3.15), then no
  // `Morphir.SDK.LocalDate.Month` (morphir-ukvn.5.22.3.16). After them, elm-typespec/elm meets the constructor `Bar`
  // that upstream declares twice (morphir-ukvn.5.22.3.18).
  ("elm-json-schema/elm", "elm.unsupported_module"),
  ("elm-json-schema/moonbit", "elm.unsupported_module"),
  ("elm-typespec/elm", "elm.unsupported_module"),
  ("elm-typespec/moonbit", "elm.unsupported_module"),
  // The SDK specification has no `Morphir.SDK.StatefulApp`, `Aggregate`, `Rule` or `UUID` (morphir-ukvn.5.22.3.19
  // to .22). Behind them, a probe found the identity limit of 100000 nodes (morphir-ukvn.5.22.3.24), then a generic
  // alias for MoonBit (morphir-ukvn.5.22.11) and a `case` that Elm refuses (morphir-ukvn.5.22.3.25).
  ("elm-reference-model/elm", "elm.unsupported_module"),
  ("elm-reference-model/moonbit", "elm.unsupported_module"),
  // Generic value `compare_maybe_value : Maybe a -> a -> Bool` (morphir-ukvn.5.22.11).
  ("elm-snowpark/moonbit", "moonbit.ambiguous_type"),
  // The SDK specification has no `Morphir.SDK.Aggregate` (morphir-ukvn.5.22.3.19). Behind it, a probe found
  // `String.isEmpty`, which has no MoonBit adapter (morphir-ukvn.5.22.9); elm make accepts the other 23 modules.
  ("elm-spark/elm", "elm.unsupported_module"),
  ("elm-spark/moonbit", "elm.unsupported_module"),
  // The SDK specification has no `Morphir.SDK.Rule` (morphir-ukvn.5.22.3.20). Behind it, a probe found the
  // `LocalDate` values `diffInDays` and `diffInYears` (morphir-ukvn.5.22.3.23), then the generic custom type `Money`
  // for MoonBit (morphir-ukvn.5.22.11). elm make accepts the other 21 modules, with the two `LocalDate` calls
  // replaced.
  ("examples-sample/elm", "elm.unsupported_module"),
  ("examples-sample/moonbit", "elm.unsupported_module"),
  // The unused let value `b = 2` keeps the `number` type of its literal (morphir-ukvn.5.22.11).
  ("lets/moonbit", "moonbit.unsupported_constraint"),
  // `++` is `basics#append`, which has no MoonBit adapter (morphir-ukvn.5.22.3.12).
  ("operators/moonbit", "moonbit.unsupported_sdk"),
  // Literal and list patterns have no MoonBit lowering (morphir-ukvn.5.22.3.13).
  ("patterns/moonbit", "moonbit.unsupported_pattern"),
  // Extensible record argument `{ a | x : Int }` (morphir-ukvn.5.22.11).
  ("records/moonbit", "moonbit.unsupported_type"),
  // `Morphir.SDK.LocalDate` has no MoonBit type (morphir-ukvn.5.22.3.14).
  ("sdk-modules/moonbit", "moonbit.unsupported_type"),
  // Generic value `swap : ( a, b ) -> ( b, a )` (morphir-ukvn.5.22.11).
  ("signatures/moonbit", "moonbit.ambiguous_type"),
  // Generic type alias `Box a` (morphir-ukvn.5.22.11).
  ("types-and-aliases/moonbit", "moonbit.unsupported_type"),
  // The unannotated value `un = 1` has the `number` type of its literal (morphir-ukvn.5.22.11).
  ("unannotated/moonbit", "moonbit.unsupported_constraint"),
])

///|
/// Corpus projects that generate but that `moon build` or `elm make` refuses, by `<project>/<backend>`, with the
/// reason. The executable leaves them out of its output, so the check script cannot see when one closes: check
/// each entry again when its bead closes. Each entry has a comment with its bead.
let build_gaps : Map[String, String] = Map::from_array([])

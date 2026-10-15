///|
/// Known differences of the round trip, by input. Each line needs a comment with the reason and a bead.
/// The round-trip test fails when a pinned difference disappears, so remove the line when the gap closes.
fn round_trip_gaps() -> Map[String, Array[String]] {
  // The frontend infers the generated Elm of a parity project as it infers the project source, so the inference
  // gaps of the parity test come back. See `parity_gaps` for the reasons: beads morphir-ukvn.5.22.7.1 (let
  // generalization), morphir-ukvn.5.22.7.2 (row variable names), morphir-ukvn.5.22.7.4 (number variables) and
  // morphir-ukvn.5.22.7.6 (LetRecursion).
  let parity = (name : String) => parity_gaps().get(name).unwrap_or([])
  Map([
    (
      "parity-custom-types",
      [
        // The backend prints a doc as `{-| <doc>\n-}` and the printer trims the doc, so the whitespace at its
        // ends changes: " A shape. " comes back as " A shape.\n". Bead morphir-ukvn.5.22.3.7.
        "type shapes#shape: doc",
      ],
    ),
    // The missing `Morphir.SDK.LocalTime` comes back, as in the parity test. Bead morphir-ukvn.5.22.3.15.
    ("parity-elm-json-schema", parity("elm-json-schema")),
    (
      "parity-elm-reference-model",
      [
        // The missing SDK modules of the parity test come back (beads morphir-ukvn.5.22.3.19 to .22). The backend
        // writes the `morphir/SDK:tuple` references of morphir-elm with `Morphir.SDK.Tuple`, which the SDK
        // specification does not have. Bead morphir-ukvn.5.22.3.4. Behind them, a probe found two first-pass
        // signatures of unannotated values (bead morphir-ukvn.5.22.3.9).
        "compile: elm.unsupported_module Morphir/Reference/Model/BooksAndRecords.elm the package of Morphir.SDK.StatefulApp is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue364.elm the package of Morphir.SDK.Aggregate is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue409.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/Issue448.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/Issues/PatternModel/BasicRule.elm the package of Morphir.SDK.Rule is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/SDK/Tuple.elm the package of Morphir.SDK.Tuple is not supported",
        "compile: elm.unsupported_module Morphir/Reference/Model/SDK/UUID.elm the package of Morphir.SDK.UUID is not supported",
      ],
    ),
    // The missing `Morphir.SDK.Aggregate` comes back, as in the parity test. Bead morphir-ukvn.5.22.3.19.
    ("parity-elm-spark", parity("elm-spark")),
    (
      "parity-elm-typespec",
      [
        // Upstream declares the constructor `Bar` twice in one module, which Elm refuses and morphir-elm and the
        // frontend accept. The backend refuses to write it. Bead morphir-ukvn.5.22.3.18.
        "generate: elm.name_collision another constructor in this module is also Bar",
      ],
    ),
    // The missing `Morphir.SDK.Rule` comes back, as in the parity test. Bead morphir-ukvn.5.22.3.20.
    ("parity-examples-sample", parity("examples-sample")),
    (
      "parity-lets",
      // The backend writes the `FloatLiteral 2` of `scaled` as an Elm float, and the frontend reads it back as a
      // `FloatLiteral`, so the round trip does not show the parity body gap of `scaled`.
      parity("lets").filter(line => line != "value blocks#scaled: body"),
    ),
    (
      "parity-modules",
      [
        // morphir-elm drops the modules Sig and Tag but module Api still names them, so the generated Elm
        // imports modules that do not exist. Bead morphir-ukvn.5.22.3.8.
        "compile: elm.unsupported_module Parity/Modules/Api.elm the package of Parity.Modules.Sig is not supported",
        "compile: elm.unsupported_module Parity/Modules/Api.elm the package of Parity.Modules.Tag is not supported",
      ],
    ),
    ("parity-records", parity("records")),
    ("parity-signatures", parity("signatures")),
    (
      "parity-types-and-aliases",
      [
        // The whitespace at the ends of a doc changes, as in parity-custom-types. Bead morphir-ukvn.5.22.3.7.
        "type doc-no-imports#flag: doc", "module doc-blank: doc", "value doc-tight#tight: doc",
        "module aliases: doc", "type aliases#point: doc",
      ] +
      parity("types-and-aliases"),
    ),
    (
      "parity-unannotated",
      [
        // morphir-elm writes the signature of an unannotated value from a first inference pass, with `t<n>`
        // variables and no number class. The backend writes it as an annotation (`un : t0`), which Elm and the
        // frontend refuse. Bead morphir-ukvn.5.22.3.9.
        "compile: elm.type Parity/Unannotated/Free.elm rigid_variable at value:parity/unannotated:free#un-float/body: the variable `t4` is annotated as any type, but the body needs Float (19:5-19:14)",
        "compile: elm.type Parity/Unannotated/Free.elm rigid_variable at value:parity/unannotated:free#un/body: the variable `t0` is annotated as any type, but the body needs number (14:5-14:6)",
        "compile: elm.type Parity/Unannotated/Free.elm rigid_variable at value:parity/unannotated:free#unannot-2/body/function/argument: the variable `t0` is annotated as any type, but the body needs number (34:5-34:6)",
        "compile: elm.type Parity/Unannotated/Free.elm rigid_variable at value:parity/unannotated:free#use-un/body: the variable `t4` is annotated as any type, but the body needs number (39:5-39:16)",
      ],
    ),
  ])
}

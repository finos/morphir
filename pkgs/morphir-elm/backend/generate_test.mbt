///|
fn file(output : @elm.Output, path : String) -> String {
  match output.files.search_by(f => f.path == path) {
    Some(i) => output.files[i].content
    None => abort("no file " + path)
  }
}

///|
fn parses(source : String) -> Bool {
  @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty()
}

///|
test "Union pattern annotations cannot disappear during Elm generation" {
  let ir = @fixtures.rentals()
  guard ir.distribution is Library(_, _, d) else { fail("library") }
  let m = d.modules.values().next().unwrap().value
  let scalar : @ir.Type = Unit(Default::default())
  let union : @ir.Type = Union(Default::default(), [scalar, scalar])
  let body : @ir.Value = Lambda(
    Default::default(),
    WildcardPattern({
      ..@ir.ValueAttributes::default(),
      inferred_type: Some(union),
    }),
    Unit(Default::default()),
  )
  m.values[@ir.Name::parse("union-witness")] = {
    access: Public,
    value: { doc: None, value: ExpressionBody([], scalar, body), },
  }
  try @elm.generate("union", ir, @elm.Options::default()) catch {
    Failed(problems) =>
      assert_eq(problems.map(p => p.code), ["elm.unsupported_type"])
    _ => fail("wrong error")
  } noraise {
    _ => fail("Union annotation emitted")
  }
}

///|
fn string_of(json : Json, key : String) -> String? {
  guard json is Object(obj) else { return None }
  if obj.get(key) is Some(String(s)) {
    Some(s)
  } else {
    None
  }
}

///|
test "rentals generate a package project" {
  let output = @elm.generate(
    "rentals",
    @fixtures.rentals(),
    @elm.Options::default(),
  )
  assert_eq(output.package_name, "morphir/example-app")
  assert_eq(output.files.map(f => f.path), [
    "src/Morphir/Example/App/Rentals.elm", "elm.json", "morphir.json",
  ])
  let source = file(output, "src/Morphir/Example/App/Rentals.elm")
  assert_true(source.contains("request : Int -> Int -> Result String Int"))
  assert_true(source.contains("if requestedQuantity <= availability then"))
  assert_true(source.contains("Ok requestedQuantity"))
  assert_true(parses(source))
  let elm_json = @json.parse(file(output, "elm.json")) catch { _ => panic() }
  assert_eq(string_of(elm_json, "type"), Some("package"))
  assert_eq(string_of(elm_json, "name"), Some("morphir/example-app"))
  assert_eq(output.dependencies, [
    { name: "elm/core", range: "1.0.5 <= v < 2.0.0", },
  ])
  let morphir_json = @json.parse(file(output, "morphir.json")) catch {
    _ => panic()
  }
  assert_eq(string_of(morphir_json, "name"), Some("Morphir.Example.App"))
  assert_eq(string_of(morphir_json, "sourceDirectory"), Some("src"))
}

///|
test "both profiles parse back for every fixture" {
  for
    ir in [
      @fixtures.rentals(),
      @fixtures.shapes(),
      @fixtures.classic_greeting(),
      @fixtures.classic_rentals_v1(),
      @fixtures.classic_rentals_v2(),
      @fixtures.sdk_tour(),
    ] {
    for profile in [@elm.Profile::Model, Literal] {
      let output = @elm.generate("corpus", ir, {
        ..@elm.Options::default(),
        profile,
      })
      for f in output.files {
        if f.role is Source {
          assert_true(parses(f.content), msg=f.path)
        }
      }
    }
  }
}

///|
test "unmapped SDK references add the SDK Elm package" {
  let output = @elm.generate("rentals", @fixtures.rentals(), {
    ..@elm.Options::default(),
    profile: Literal,
  })
  assert_true(
    output.dependencies.contains({
      name: "finos/morphir-elm",
      range: "22.0.2 <= v < 23.0.0",
    }),
  )
}

///|
test "output is deterministic" {
  let first = @elm.generate(
    "shapes",
    @fixtures.shapes(),
    @elm.Options::default(),
  )
  let second = @elm.generate(
    "shapes",
    @fixtures.shapes(),
    @elm.Options::default(),
  )
  assert_eq(first.files, second.files)
}

///|
test "specifications need the debug-todo policy" {
  let refused = try {
    ignore(@elm.generate("specs", @fixtures.specs(), @elm.Options::default()))
    []
  } catch {
    Failed(problems) => problems.map(p => p.code)
    _ => ["other"]
  }
  assert_eq(refused, ["elm.placeholder"])
  let output = @elm.generate("specs", @fixtures.specs(), {
    ..@elm.Options::default(),
    placeholders: DebugTodo,
  })
  let source = file(output, "src/Acme/Api/Limits.elm")
  assert_true(
    source.contains("@morphir.annotation { fqname = \"acme/api:tags#stable\" }"),
  )
  assert_true(source.contains("type Token\n    = TokenOpaque"))
  assert_true(parses(source))
}

///|
test "every failing module is reported" {
  let refused = try {
    ignore(@elm.generate("rates", @fixtures.refused(), @elm.Options::default()))
    []
  } catch {
    Failed(problems) => problems.map(p => p.code + " " + p.node_path)
    _ => ["other"]
  }
  assert_eq(refused, [
    "elm.decimal_literal acme/rates:first#rate", "elm.decimal_literal acme/rates:second#rate",
  ])
}

///|
test "cancellation stops generation" {
  let refused = try {
    ignore(
      @elm.generate("shapes", @fixtures.shapes(), @elm.Options::default(), cancelled=fn() {
        true
      }),
    )
    ""
  } catch {
    Failed(problems) => problems[0].code
    _ => "other"
  }
  assert_eq(refused, "elm.cancelled")
}

///|
test "the elm.json summary is shorter than 80 bytes" {
  // "Morphir model " is 14 bytes, so these names give summaries of 80 and 95 bytes.
  for package_text in ["acme/" + "a".repeat(61), "acme/" + "b".repeat(76)] {
    let ir = @ir.IRFile::new(
      Library(@ir.Path::parse(package_text), Map([]), { modules: Map([]), }),
    )
    let output = @elm.generate("long", ir, @elm.Options::default())
    guard @json.parse(file(output, "elm.json")) is Object(fields) &&
      fields.get("summary") is Some(String(summary)) else {
      fail("no summary")
    }
    assert_true(summary.length() < 80, msg=summary)
    assert_true(summary.has_prefix("Morphir model acme/"))
  }
}

///|
test "the SDK tour qualifies captured names and uses the SDK Elm package" {
  let output = @elm.generate(
    "sdk-tour",
    @fixtures.sdk_tour(),
    @elm.Options::default(),
  )
  let source = file(output, "src/Acme/SdkTour/Tour.elm")
  for
    expected in [
      "biggest =\n    Basics.max 1 2", "case compare a b of\n        LT ->", "Maybe.map2 (+) x y",
      "type alias Ranked comparableK =", "best : comparableK -> comparableK -> comparableK",
      "Morphir.SDK.Decimal.fromInt 100", "due : Morphir.SDK.LocalDate.LocalDate -> Morphir.SDK.LocalDate.LocalDate",
    ] {
    assert_true(source.contains(expected), msg=expected + "\n" + source)
  }
  assert_true(
    output.dependencies.contains({
      name: "finos/morphir-elm",
      range: "22.0.2 <= v < 23.0.0",
    }),
  )
}

///|
test "classic fixtures generate after migration" {
  for
    ir in [
      @fixtures.classic_greeting(),
      @fixtures.classic_rentals_v1(),
      @fixtures.classic_rentals_v2(),
    ] {
    let output = @elm.generate("classic", ir, @elm.Options::default())
    assert_true(output.files.any(f => f.role is Source))
  }
}

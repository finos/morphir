///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
test "built-in table maps elm/core semantics and leaves the rest" {
  let mapping = Mapping::builtin()
  assert_eq(
    mapping.lookup(fq("morphir/SDK:basics#add"), ValueSpace),
    Some(Operator("+")),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:list#cons"), ValueSpace),
    Some(Operator("::")),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:list#map"), ValueSpace),
    Some(Function("List.map", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:basics#max"), ValueSpace),
    Some(Function("Basics.max", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:dict#insert"), ValueSpace),
    Some(Function("Dict.insert", Some("Dict"))),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:maybe#just"), ValueSpace),
    Some(Function("Maybe.Just", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:basics#int"), TypeSpace),
    Some(Type("Basics.Int", None)),
  )
  // Decimal semantics are not elm/core, so the reference stays qualified.
  assert_eq(mapping.lookup(fq("morphir/SDK:decimal#add"), ValueSpace), None)
}

///|
test "overrides replace, extend and remove entries" {
  let mapping = Mapping::builtin().with_overrides(
    Map::from_array([
      ("morphir/SDK:basics#max", Removed),
      ("acme/app:money#add", Function("Money.plus", Some("Money"))),
      ("morphir/SDK:list#map", Function("Array.map", Some("Array"))),
    ]),
  )
  assert_eq(mapping.lookup(fq("morphir/SDK:basics#max"), ValueSpace), None)
  assert_eq(
    mapping.lookup(fq("acme/app:money#add"), ValueSpace),
    Some(Function("Money.plus", Some("Money"))),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:list#map"), ValueSpace),
    Some(Function("Array.map", Some("Array"))),
  )
  assert_eq(
    Mapping::builtin().lookup(fq("morphir/SDK:basics#max"), ValueSpace),
    Some(Function("Basics.max", None)),
  )
}

///|
test "a type and a value can share one key" {
  let mapping = Mapping::builtin()
  let never = fq("morphir/SDK:basics#never")
  assert_eq(mapping.lookup(never, TypeSpace), Some(Type("Basics.Never", None)))
  assert_eq(
    mapping.lookup(never, ValueSpace),
    Some(Function("Basics.never", None)),
  )
}

///|
test "built-in entries have no duplicate key within a namespace" {
  let types : Map[String, Bool] = Map([])
  let values : Map[String, Bool] = Map([])
  for entry in @mapping.builtin_entries() {
    let table = match entry.1 {
      Type(_, _) => types
      _ => values
    }
    assert_false(table.contains(entry.0))
    table[entry.0] = true
  }
}

///|
test "a removed override hides both namespaces" {
  let mapping = Mapping::builtin().with_overrides(
    Map::from_array([("morphir/SDK:basics#never", Removed)]),
  )
  let never = fq("morphir/SDK:basics#never")
  assert_eq(mapping.lookup(never, TypeSpace), None)
  assert_eq(mapping.lookup(never, ValueSpace), None)
}

///|
test "mapping entries parse from JSON" {
  assert_eq(
    parse_mapping_entry(
      "morphir/SDK:basics#add",
      Json::object(Map::from_array([("operator", Json::string("+"))])),
    ),
    Operator("+"),
  )
  assert_eq(
    parse_mapping_entry(
      "morphir/SDK:decimal#decimal",
      Json::object(
        Map::from_array([
          ("type", Json::string("Decimal.Decimal")),
          ("import", Json::string("MyCo.Decimal as Decimal")),
        ]),
      ),
    ),
    Type("Decimal.Decimal", Some("MyCo.Decimal as Decimal")),
  )
  assert_eq(
    parse_mapping_entry("morphir/SDK:basics#max", Json::object(Map([]))),
    Removed,
  )
  for
    bad in [
      (
        "not a name",
        Json::object(Map::from_array([("function", Json::string("f"))])),
      ),
      (
        "a:b#c",
        Json::object(
          Map::from_array([
            ("function", Json::string("f")),
            ("type", Json::string("T")),
          ]),
        ),
      ),
      (
        "a:b#c",
        Json::object(Map::from_array([("colour", Json::string("red"))])),
      ),
      ("a:b#c", Json::string("f")),
    ] {
    let code = try {
      ignore(parse_mapping_entry(bad.0, bad.1))
      ""
    } catch {
      Refused(problem) => problem.code
      _ => "other"
    }
    assert_eq(code, "elm.invalid_mapping")
  }
}

///|
/// Migration decodes legacy names with `Name::from_words`, as morphir-elm wrote them.
fn migrated(module_text : String, words : Array[String]) -> @ir.FQName {
  {
    package_name: @ir.Path::from_names([
      @ir.Name::from_words(["morphir"]),
      @ir.Name::from_words(["s", "d", "k"]),
    ]),
    module_name: @ir.Path::from_names([@ir.Name::from_words([module_text])]),
    local_name: @ir.Name::from_words(words),
  }
}

///|
test "built-in keys match names decoded from legacy IR" {
  let mapping = Mapping::builtin()
  assert_eq(
    mapping.lookup(migrated("list", ["map", "2"]), ValueSpace),
    Some(Function("List.map2", None)),
  )
  assert_eq(
    mapping.lookup(migrated("result", ["map", "5"]), ValueSpace),
    Some(Function("Result.map5", None)),
  )
  assert_true(
    mapping.lookup(migrated("basics", ["atan", "2"]), ValueSpace)
    is Some(Function(_, None)),
  )
  for words in [["l", "t"], ["e", "q"], ["g", "t"]] {
    assert_true(
      mapping.lookup(migrated("basics", words), ValueSpace)
      is Some(Function(_, None)),
      msg=words.join(""),
    )
  }
}

///|
test "built-in keys are canonical FQNames" {
  for entry in @mapping.builtin_entries() {
    let parsed = @ir.FQName::parse(entry.0) catch { _ => fail(entry.0) }
    assert_eq(parsed.to_canonical(), entry.0)
  }
}

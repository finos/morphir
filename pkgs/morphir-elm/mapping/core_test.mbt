///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
test "Elm core names map to the Morphir SDK" {
  let core = @mapping.ElmCore::builtin()
  assert_eq(core.type_of("Basics", "Int"), Some(fq("morphir/SDK:basics#int")))
  assert_eq(core.type_of("Maybe", "Maybe"), Some(fq("morphir/SDK:maybe#maybe")))
  assert_eq(core.type_of("Dict", "Dict"), Some(fq("morphir/SDK:dict#dict")))
  assert_eq(core.value_of("List", "map"), Some(fq("morphir/SDK:list#map")))
  assert_eq(core.value_of("Maybe", "Just"), Some(fq("morphir/SDK:maybe#just")))
  assert_eq(core.value_of("List", "noSuchFunction"), None)
  assert_true(core.is_core_module("Basics"))
  assert_true(core.is_core_module("Tuple"))
  assert_false(core.is_core_module("Html"))
}

///|
test "builtin entries keep the backend lookups" {
  // The backend reads the same table; one entry of each kind is enough here.
  let entries = Map::from_array(@mapping.builtin_entries())
  assert_eq(entries.get("morphir/SDK:basics#add"), Some(@mapping.Operator("+")))
  assert_eq(
    entries.get("morphir/SDK:maybe#just"),
    Some(@mapping.Function("Maybe.Just", None)),
  )
}

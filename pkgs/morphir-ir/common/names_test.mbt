///|
test "legacy SDK identity agrees with canonical spelling" {
  let legacy = @common.Name::from_words(["s", "d", "k"])
  assert_eq(legacy, @common.Name::parse("SDK"))
  assert_true(legacy != @common.Name::parse("sdk"))
  assert_eq(@common.Name::from_words(["a"]).to_canonical(), "a")
  assert_eq(
    @common.Name::from_words(["f", "r", "2052", "a"]).to_canonical(),
    "FR-2052-a",
  )
  assert_eq(
    @common.FQName::parse("morphir/SDK:list#map").to_canonical(),
    "morphir/SDK:list#map",
  )
}

///|
test "name map identity survives mutation of input and returned arrays" {
  let words = ["user", "name"]
  let name = @common.Name::from_words(words)
  let index : Map[@common.Name, Int32] = Map::from_array([(name, 42)])
  words[0] = "changed"
  let returned = name.to_words()
  returned[0] = "changed"
  assert_eq(index.get(@common.Name::parse("user-name")), Some(42))
}

///|
test "canonical name parsing does not merge distinct initialism boundaries" {
  assert_true(@common.Name::parse("a-b") != @common.Name::parse("AB"))
  assert_eq(@common.Name::parse("FR2052A").to_canonical(), "FR2052A")
  for
    invalid in [
      "", "value-in-(usd)", "value-in-Usd", "bad--name", "name/part", "-name",
    ] {
    let refused = try {
      ignore(@common.Name::parse(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

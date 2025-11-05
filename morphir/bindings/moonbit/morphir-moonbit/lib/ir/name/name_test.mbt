///|
test "Name::from_string" {
  let name = Name::from_string("Morphir.IR.Name")
  let actualJson = name.to_json(Default::default())
  @json.inspect(actualJson, content=["morphir", "i", "r", "name"])
}

///|
test "Name:from_string many" {
  let test_cases = [
    ("fooBar_baz 123", ["foo", "bar", "baz", "123"]),
    ("valueInUSD", ["value", "in", "u", "s", "d"]),
    ("ValueInUSD", ["value", "in", "u", "s", "d"]),
    ("value_in_USD", ["value", "in", "u", "s", "d"]),
    ("Hello.World.Test", ["hello", "world", "test"]),
    ("simple-name", ["simple", "name"]),
    ("Mixed.Case-Example_456", ["mixed", "case", "example", "456"]),
  ]
  for i = 0; i < test_cases.length(); i = i + 1 {
    let (input, expected_parts) = test_cases[i]
    let name = Name::from_string(input)
    let actual_parts = name.0
    assert_eq(actual_parts, @list.from_array(expected_parts))
  }
}

///|
test "Name::to_title_case" {
  let test_cases = [
    (Name::from_list(@list.of(["foo", "bar", "baz", "123"])), "FooBarBaz123"),
    (Name::from_list(@list.of(["value", "in", "u", "s", "d"])), "ValueInUSD"),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_title_case(t.0))
  assert_eq(actual, expected)
}

///|
test "Name to_title_case as method" {
  let test_cases = [
    (Name::from_list(@list.of(["foo", "bar", "baz", "123"])), "FooBarBaz123"),
    (Name::from_list(@list.of(["value", "in", "u", "s", "d"])), "ValueInUSD"),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => t.0.to_title_case())
  assert_eq(actual, expected)
}

///|
test "Name::to_human_words" {
  let test_cases = [
    (
      Name::from_list(@list.of(["value", "in", "u", "s", "d"])),
      @list.of(["value", "in", "USD"]),
    ),
    (
      Name::from_list(@list.of(["simple", "name"])),
      @list.of(["simple", "name"]),
    ),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_human_words(t.0))
  assert_eq(actual, expected)
}

///|
test "Name::to_human_words_title" {
  let test_cases = [
    (
      Name::from_list(@list.of(["value", "in", "u", "s", "d"])),
      @list.of(["Value", "in", "USD"]),
    ),
    (
      Name::from_list(@list.of(["simple", "name"])),
      @list.of(["Simple", "name"]),
    ),
    (Name::from_list(@list.default()), @list.default()),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_human_words_title(t.0))
  assert_eq(actual, expected)
}

///|
test "Name::to_camel_case" {
  let test_cases = [
    (Name::from_list(@list.of(["foo", "bar", "baz", "123"])), "fooBarBaz123"),
    (Name::from_list(@list.of(["value", "in", "u", "s", "d"])), "valueInUSD"),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_camel_case(t.0))
  assert_eq(actual, expected)
}

///|
test "Name::to_snake_case" {
  let test_cases = [
    (Name::from_list(@list.of(["foo", "bar", "baz", "123"])), "foo_bar_baz_123"),
    (Name::from_list(@list.of(["value", "in", "u", "s", "d"])), "value_in_USD"),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_snake_case(t.0))
  assert_eq(actual, expected)
}

///|
test "Name::to_kebab_case" {
  let test_cases = [
    (Name::from_list(@list.of(["foo", "bar", "baz", "123"])), "foo-bar-baz-123"),
    (Name::from_list(@list.of(["value", "in", "u", "s", "d"])), "value-in-usd"),
  ]
  let expected = test_cases.map(t => t.1)
  let actual = test_cases.map(t => Name::to_kebab_case(t.0))
  assert_eq(actual, expected)
}

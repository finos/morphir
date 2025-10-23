///|
test "Path::from_list creates a Path from a list of Names" {
  let name1 = @name.Name::from_string("Module")
  let name2 = @name.Name::from_string("SubModule")
  let name3 = @name.Name::from_string("Function")
  let name_list = @list.of([name1, name2, name3])
  let path = @path.Path::from_list(name_list)
  assert_eq(path.0, name_list)
}

///|
test "Path::to_string converts a Path to a string with custom renderer and separator" {
  let name1 = @name.from_string("Module")
  let name2 = @name.from_string("SubModule")
  let name3 = @name.from_string("Function")
  let path = @path.Path::from_list(@list.of([name1, name2, name3]))
  let renderer : @name.NameRenderer = (name : @name.Name) => name.to_snake_case()
  let result = path.to_string(renderer, "::")
  assert_eq(result, "module::sub_module::function")
}

///|
test "from_string | fooBar.Baz" {
  let input = "fooBar.Baz"
  let path = @path.from_string(input)
  let expected_names = @list.of([
    @name.of(["foo", "bar"]),
    @name.of(["baz"]),
  ])
  assert_eq(path.0, expected_names)
}

///|
test "from_string | foo bar/baz" {
  let input = "foo bar/baz"
  let path = @path.from_string(input)
  let expected_names = @list.of([
    @name.of(["foo", "bar"]),
    @name.of(["baz"]),
  ])
  assert_eq(path.0, expected_names)
}

///|
test "to_list" {
  let name1 = @name.from_string("Module")
  let name2 = @name.from_string("SubModule")
  let name3 = @name.from_string("Function")
  let path = @path.Path::from_list(@list.of([name1, name2, name3]))
  let name_list = path.to_list()
  assert_eq(name_list, @list.of([name1, name2, name3]))
}

///|
test "Path::is_prefix_of | 1 ]" {
  let path = @path.Path::from_list(
    @list.of([@name.of(["foo"]), @name.of(["bar"])]),
  )
  let prefix = @path.Path::from_list(@list.of([@name.of(["foo"])]))
  assert_true(prefix.is_prefix_of(path))
}

///|
test "Path::is_prefix_of | 2 ]" {
  let path : @path.Path = @path.of([@name.of(["foo"])])
  let prefix : @path.Path = @path.of([@name.of(["foo"]), @name.of(["bar"])])
  assert_false(prefix.is_prefix_of(path))
}

///|
test "Path::is_prefix_of | 3" {
  let prefix = @path.of(
    [@name.of(["foo"]), @name.of(["bar"])],
  )
  let path = @path.Path::from_list(
    @list.of([@name.of(["foo"]), @name.of(["bar"])]),
  )
  assert_true(prefix.is_prefix_of(path))
}

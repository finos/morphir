///|
test "Variable to_string | valueInUSD" {
  let name = @name.from_string("valueInUSD")
  let sut = Type::variable((), name)
  inspect(sut.to_string(), content="valueInUSD")
}

///|
test "Variable to_string | kebab-cased-input" {
  let name = @name.from_string("kebab-cased-input")
  let sut = Type::variable("inconsequential", name)
  inspect(sut.to_string(), content="kebabCasedInput")
}

///|
test "Unit to_string" {
  let sut = Type::unit(())
  inspect(sut.to_string(), content="()")
}

test "Tuple to_string | Given a list of Variables" {
  let var_a = Type::variable((), @name.from_string("a"))
  let var_b = Type::variable((), @name.from_string("b"))
  let var_c = Type::variable((), @name.from_string("c"))
  let sut = Type::tuple((), @list.of([var_a, var_b, var_c]))
  inspect(sut.to_string(), content="( a, b, c )")
}

test "Function to_string | Given a single arg function" {
  let arg1 = Type::variable((), @name.from_string("a"))
  let return_type = Type::unit(())
  let sut = Type::function((), arg1, return_type)
  inspect(sut.to_string(), content = "a -> ()")
}

test "Reference to_string | Given a reference type with no params" {
  let fq_name = @fqname.fq_name(
    @package.PackageName::from_list(
      @list.of([@name.Name::from_string("MyPackage")]),
    ),
    @module.ModulePath::from_list(
      @list.of([@name.Name::from_string("MyModule")]),
    ),
    @name.Name::from_string("MyType"),
  )
  let sut = Type::reference((), fq_name, @list.of([]))
  inspect(sut.to_string(), content="MyPackage.MyModule.MyType")
}

test "Reference to_string | Given a reference type with params" {
  let fq_name = @fqname.fq_name(
    @package.PackageName::from_list(
      @list.of([@name.Name::from_string("MyPackage")]),
    ),
    @module.ModulePath::from_list(
      @list.of([@name.Name::from_string("MyModule")]),
    ),
    @name.Name::from_string("MyType"),
  )
  let type_arg1 = Type::variable((), @name.Name::from_string("Arg1"))
  let type_arg2 = Type::unit(())
  let sut = Type::reference((), fq_name, @list.of([type_arg1, type_arg2]))
  inspect(sut.to_string(), content="MyPackage.MyModule.MyType arg1 ()")
}
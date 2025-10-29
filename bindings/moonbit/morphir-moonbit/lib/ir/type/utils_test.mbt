///|
test "iter over Unit type" {
  let unit_type = Type::unit("Unit")
  let iter = unit_type.iter()
  let res = iter.map(t => t.attributes()).to_array()
  assert_eq(iter.to_array(), [unit_type])
  assert_eq(res, ["Unit"])
}

///|
test "iter can be used to collect a Variable type" {
  let var_name = @name.Name::from_string("MyVar")
  let variable_type = Type::variable("VarAttr", var_name)
  let iter = variable_type.iter()
  let collected = iter.collect()
  assert_eq(collected.length(), 1)
  assert_eq(collected[0], variable_type)
}

///|
test "iter over Reference type with type arguments" {
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
  let reference_type = Type::reference(
    (),
    fq_name,
    @list.of([type_arg1, type_arg2]),
  )
  let iter = reference_type.iter()
  let collected = iter.to_array()
  assert_eq(collected.length(), 3)
  assert_eq(collected[0], reference_type)
  assert_eq(collected[1], type_arg1)
  assert_eq(collected[2], type_arg2)
}

///|
test "iter over Tuple type" {
  let element_type1 = Type::variable((), @name.Name::from_string("ElemType1"))
  let element_type2 = Type::unit(())
  let tuple_type = Type::tuple((), @list.of([element_type1, element_type2]))
  let iter = tuple_type.iter()
  let collected = iter.to_array()
  assert_eq(collected.length(), 3)
  assert_eq(collected[0], tuple_type)
  assert_eq(collected[1], element_type1)
  assert_eq(collected[2], element_type2)
}

///|
test "iter over Function type" {
  let param_type = Type::variable((), @name.Name::from_string("ParamType"))
  let return_type = Type::unit(())
  let function_type = Type::function((), param_type, return_type)
  let iter = function_type.iter()
  let collected = iter.to_array()
  assert_eq(collected.length(), 3)
  assert_eq(collected[0], function_type)
  assert_eq(collected[1], param_type)
  assert_eq(collected[2], return_type)

}


///|
test "Unit type encoding" {
  let unit_type = Type::unit(())
  let json : Json = unit_type.to_json(Default::default())
  @json.inspect(json, content=["Unit", {}])
}

///|
test "Unit type encoding with String attributes" {
  let unit_type = Type::unit("attribute")
  let json : Json = unit_type.to_json(Default::default())
  @json.inspect(json, content=["Unit", "attribute"])
}

///|
test "Variable type encoding" {
  let var_name = @name.Name::from_string("MyTypeVar")
  let variable_type = Type::variable((), var_name)
  let json : Json = variable_type.to_json(Default::default())
  @json.inspect(json, content=["Variable", {}, ["my", "type", "var"]])
}

///|
test "Function type encoding" {
  let param_type = Type::variable((), @name.Name::from_string("ParamType"))
  let return_type = Type::unit(())
  let function_type = Type::function((), param_type, return_type)
  let json : Json = function_type.to_json(Default::default())
  @json.inspect(json, content=[
    "Function",
    {},
    ["Variable", {}, ["param", "type"]],
    ["Unit", {}],
  ])
}

///|
test "Tuple type encoding" {
  let element_type1 = Type::variable((), @name.Name::from_string("ElemType1"))
  let element_type2 = Type::unit(())
  let tuple_type = Type::tuple((), @list.of([element_type1, element_type2]))
  let json : Json = tuple_type.to_json(Default::default())
  @json.inspect(json, content=[
    "Tuple",
    {},
    [["Variable", {}, ["elem", "type", "1"]], ["Unit", {}]],
  ])
}

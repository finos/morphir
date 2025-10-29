///|
let string_type_ref : Type[Unit] = Type::reference(
  (),
  @fqname.fq_name(
    @package.PackageName::from_string("Morphir.Sdk"),
    @module.ModulePath::from_string("Basics"),
    @name.Name::from_string("string"),
  ),
  @list.of([]),
)

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

///|
test "Reference type encoding" {
  let fq_name = @fqname.fq_name(
    @package.PackageName::from_list(
      @list.of([@name.Name::from_string("MyPackage")]),
    ),
    @module.ModulePath::from_list(
      @list.of([
        @name.Name::from_string("MyModule"),
        @name.Name::from_string("Path"),
      ]),
    ),
    @name.Name::from_string("MyType"),
  )
  let type_arg = Type::unit(())
  let reference_type = Type::reference((), fq_name, @list.of([type_arg]))
  let json : Json = reference_type.to_json(Default::default())
  @json.inspect(json, content=[
    "Reference",
    {},
    [[["my", "package"]], [["my", "module"], ["path"]], ["my", "type"]],
    [["Unit", {}]],
  ])
}

///|
test "Record type encoding" {
  let field1 = @type.field(
    @name.Name::from_string("fieldOne"),
    Type::variable((), @name.Name::from_string("FieldType1")),
  )
  let field2 = @type.field(@name.Name::from_string("fieldTwo"), Type::unit(()))
  let record_type = Type::record((), @list.of([field1, field2]))
  let json : Json = record_type.to_json(Default::default())
  @json.inspect(json, content=[
    "Record",
    {},
    [
      {
        "name": ["field", "one"],
        "tpe": ["Variable", {}, ["field", "type", "1"]],
      },
      { "name": ["field", "two"], "tpe": ["Unit", {}] },
    ],
  ])
}

///|
test "ExtensibleRecord type encoding" {
  let name = @name.Name::from_string("A")
  let firstNameField = @type.field(
    @name.Name::from_string("FirstName"),
    string_type_ref,
  )
  let lastNameField = @type.field(
    @name.Name::from_string("LastName"),
    string_type_ref,
  )
  let extensible_record_type = Type::extensible_record(
    (),
    name,
    @list.of([firstNameField, lastNameField]),
  )
  let json : Json = extensible_record_type.to_json(Default::default())
  @json.inspect(json, content=[
    "ExtensibleRecord",
    {},
    ["a"],
    [
      {
        "name": ["first", "name"],
        "tpe": [
          "Reference",
          {},
          [[["morphir"], ["sdk"]], [["basics"]], ["string"]],
          [],
        ],
      },
      {
        "name": ["last", "name"],
        "tpe": [
          "Reference",
          {},
          [[["morphir"], ["sdk"]], [["basics"]], ["string"]],
          [],
        ],
      },
    ],
  ])
}

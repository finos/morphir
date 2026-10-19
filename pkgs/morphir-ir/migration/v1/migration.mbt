///|
fn up_type(value : @old.Type[Unit]) -> @current.Type raise {
  match value {
    Variable(a, p0) => @current.Type::Variable(up_ta(a), p0)
    Reference(a, p0, p1) =>
      @current.Type::Reference(up_ta(a), p0, p1.map(up_type))
    Tuple(a, p0) => @current.Type::Tuple(up_ta(a), p0.map(up_type))
    Record(a, p0) => @current.Type::Record(up_ta(a), up_fields(p0))
    ExtensibleRecord(a, p0, p1) =>
      @current.Type::ExtensibleRecord(up_ta(a), p0, up_fields(p1))
    Function(a, p0, p1) =>
      @current.Type::Function(up_ta(a), up_type(p0), up_type(p1))
    Unit(a) => @current.Type::Unit(up_ta(a))
  }
}

///|
fn up_pattern(value : @old.Pattern[@old.Type[Unit]]) -> @current.Pattern raise {
  match value {
    WildcardPattern(a) => @current.Pattern::WildcardPattern(up_va(a))
    AsPattern(a, p0, p1) =>
      @current.Pattern::AsPattern(up_va(a), up_pattern(p0), p1)
    TuplePattern(a, p0) =>
      @current.Pattern::TuplePattern(up_va(a), p0.map(up_pattern))
    ConstructorPattern(a, p0, p1) =>
      @current.Pattern::ConstructorPattern(up_va(a), p0, p1.map(up_pattern))
    EmptyListPattern(a) => @current.Pattern::EmptyListPattern(up_va(a))
    HeadTailPattern(a, p0, p1) =>
      @current.Pattern::HeadTailPattern(
        up_va(a),
        up_pattern(p0),
        up_pattern(p1),
      )
    LiteralPattern(a, p0) =>
      @current.Pattern::LiteralPattern(up_va(a), up_pattern_literal(p0))
    UnitPattern(a) => @current.Pattern::UnitPattern(up_va(a))
  }
}

///|
fn up_value(value : @old.Value[Unit, @old.Type[Unit]]) -> @current.Value raise {
  match value {
    Literal(a, p0) => @current.Value::Literal(up_va(a), up_literal(p0))
    Constructor(a, p0) => @current.Value::Constructor(up_va(a), p0)
    Tuple(a, p0) => @current.Value::Tuple(up_va(a), p0.map(up_value))
    List(a, p0) => @current.Value::List(up_va(a), p0.map(up_value))
    Record(a, p0) =>
      @current.Value::Record(
        up_va(a),
        @wire.map_values(p0, value => up_value(value)),
      )
    Variable(a, p0) => @current.Value::Variable(up_va(a), p0)
    Reference(a, p0) => @current.Value::Reference(up_va(a), p0)
    Field(a, p0, p1) => @current.Value::Field(up_va(a), up_value(p0), p1)
    FieldFunction(a, p0) => @current.Value::FieldFunction(up_va(a), p0)
    Apply(a, p0, p1) =>
      @current.Value::Apply(up_va(a), up_value(p0), up_value(p1))
    Lambda(a, p0, p1) =>
      @current.Value::Lambda(up_va(a), up_pattern(p0), up_value(p1))
    LetDefinition(a, p0, p1, p2) =>
      @current.Value::LetDefinition(
        up_va(a),
        p0,
        up_definition(p1),
        up_value(p2),
      )
    LetRecursion(a, p0, p1) =>
      @current.Value::LetRecursion(
        up_va(a),
        @wire.map_values(p0, value => up_definition(value)),
        up_value(p1),
      )
    Destructure(a, p0, p1, p2) =>
      @current.Value::Destructure(
        up_va(a),
        up_pattern(p0),
        up_value(p1),
        up_value(p2),
      )
    IfThenElse(a, p0, p1, p2) =>
      @current.Value::IfThenElse(
        up_va(a),
        up_value(p0),
        up_value(p1),
        up_value(p2),
      )
    PatternMatch(a, p0, p1) =>
      @current.Value::PatternMatch(
        up_va(a),
        up_value(p0),
        p1.map(pair => (up_pattern(pair.0), up_value(pair.1))),
      )
    UpdateRecord(a, p0, p1) =>
      @current.Value::UpdateRecord(
        up_va(a),
        up_value(p0),
        @wire.map_values(p1, value => up_value(value)),
      )
    Unit(a) => @current.Value::Unit(up_va(a))
  }
}

///|
fn up_literal(value : @old.Literal) -> @current.Literal {
  match value {
    BoolLiteral(value) => @current.Literal::BoolLiteral(value)
    CharLiteral(value) => @current.Literal::CharLiteral(value)
    StringLiteral(value) => @current.Literal::StringLiteral(value)
    WholeNumberLiteral(value) => @current.Literal::IntegerLiteral(value)
    FloatLiteral(value) => @current.Literal::FloatLiteral(value)
    DecimalLiteral(value) => @current.Literal::DecimalLiteral(value)
  }
}

///|
fn up_pattern_literal(value : @old.Literal) -> @current.PatternLiteral {
  match value {
    BoolLiteral(value) => @current.PatternLiteral::BoolLiteral(value)
    CharLiteral(value) => @current.PatternLiteral::CharLiteral(value)
    StringLiteral(value) => @current.PatternLiteral::StringLiteral(value)
    WholeNumberLiteral(value) => @current.PatternLiteral::IntegerLiteral(value)
    FloatLiteral(value) => @current.PatternLiteral::FloatLiteral(value)
    DecimalLiteral(value) => @current.PatternLiteral::DecimalLiteral(value)
  }
}

///|
fn up_ta(_value : Unit) -> @current.TypeAttributes {
  @current.TypeAttributes::default()
}

///|
fn up_va(value : @old.Type[Unit]) -> @current.ValueAttributes raise {
  { source: None, inferred_type: Some(up_type(value)), extensions: Map([]), }
}

///|
fn up_fields(
  fields : Array[@old.Field[Unit]],
) -> Map[@current.Name, @current.Type] raise {
  let result : Map[@current.Name, @current.Type] = Map([])
  for field in fields {
    if result.contains(field.name) {
      raise @wire.Invalid("duplicate_member", field.name.to_canonical())
    }
    result[field.name] = up_type(field.tpe)
  }
  result
}

///|
fn up_definition(
  value : @old.ValueDefinition[Unit, @old.Type[Unit]],
) -> @current.ValueDefinition raise {
  let inputs = value.input_types.map(input => {
    if input.1 != input.2 {
      raise @wire.Invalid(
        "unsupported_attributes_migration", "Input annotation differs from its declared type",
      )
    }
    (input.0, up_type(input.2))
  })
  @current.ExpressionBody(
    inputs,
    up_type(value.output_type),
    up_value(value.body),
  )
}

///|
fn up_constructors(
  value : @old.Constructors[Unit],
) -> @current.Constructors raise {
  @wire.map_values(value, args => args.map(arg => (arg.0, up_type(arg.1))))
}

///|
fn up_type_definition(
  value : @old.TypeDefinition[Unit],
) -> @current.TypeDefinition raise {
  match value {
    TypeAliasDefinition(params, body) =>
      @current.TypeAliasDefinition(params, up_type(body))
    CustomTypeDefinition(params, constructors) =>
      @current.CustomTypeDefinition(params, {
        access: constructors.access,
        value: up_constructors(constructors.value),
      })
  }
}

///|
fn up_type_specification(
  value : @old.TypeSpecification[Unit],
) -> @current.TypeSpecification raise {
  let body = match value {
    TypeAliasSpecification(params, body) =>
      @current.TypeAliasSpecification(params, up_type(body))
    OpaqueTypeSpecification(params) => @current.OpaqueTypeSpecification(params)
    CustomTypeSpecification(params, body) =>
      @current.CustomTypeSpecification(params, up_constructors(body))
    DerivedTypeSpecification(params, body) =>
      @current.DerivedTypeSpecification(params, {
        base_type: up_type(body.base_type),
        from_base_type: body.from_base_type,
        to_base_type: body.to_base_type,
      })
  }
  { annotations: [], body, }
}

///|
fn up_value_specification(
  value : @old.ValueSpecification[Unit],
) -> @current.ValueSpecification raise {
  {
    annotations: [],
    inputs: value.inputs.map(input => (input.0, up_type(input.1))),
    output: up_type(value.output),
  }
}

///|
fn up_module_definition(
  value : @old.ModuleDefinition[Unit, @old.Type[Unit]],
) -> @current.ModuleDefinition raise {
  {
    types: @wire.map_values(value.types, item => {
      access: item.access,
      value: {
        doc: Some(item.value.doc),
        value: up_type_definition(item.value.value),
      },
    }),
    values: @wire.map_values(value.values, item => {
      access: item.access,
      value: {
        doc: Some(item.value.doc),
        value: up_definition(item.value.value),
      },
    }),
    doc: value.doc,
  }
}

///|
fn up_package_definition(
  value : @old.PackageDefinition[Unit, @old.Type[Unit]],
) -> @current.PackageDefinition raise {
  {
    modules: @wire.map_values(value.modules, item => {
      access: item.access,
      value: up_module_definition(item.value),
    }),
  }
}

///|
fn up_module_specification(
  value : @old.ModuleSpecification[Unit],
) -> @current.ModuleSpecification raise {
  {
    annotations: [],
    types: @wire.map_values(value.types, item => {
      doc: Some(item.doc),
      value: up_type_specification(item.value),
    }),
    values: @wire.map_values(value.values, item => {
      doc: Some(item.doc),
      value: up_value_specification(item.value),
    }),
    doc: value.doc,
  }
}

///|
fn up_package_specification(
  value : @old.PackageSpecification[Unit],
) -> @current.PackageSpecification raise {
  {
    modules: @wire.map_values(value.modules, item => {
      up_module_specification(item)
    }),
  }
}

///|
fn down_type(value : @current.Type) -> @old.Type[Unit] raise {
  match value {
    Union(_, _) => raise @wire.Invalid("unsupported_v4_downgrade", "Union")
    Variable(a, p0) => @old.Type::Variable(down_variable_ta(a, p0), p0)
    Reference(a, p0, p1) =>
      @old.Type::Reference(down_ta(a), p0, p1.map(down_type))
    Tuple(a, p0) => @old.Type::Tuple(down_ta(a), p0.map(down_type))
    Record(a, p0) => @old.Type::Record(down_ta(a), down_fields(p0))
    ExtensibleRecord(a, p0, p1) =>
      @old.Type::ExtensibleRecord(down_variable_ta(a, p0), p0, down_fields(p1))
    Function(a, p0, p1) =>
      @old.Type::Function(down_ta(a), down_type(p0), down_type(p1))
    Unit(a) => @old.Type::Unit(down_ta(a))
  }
}

///|
fn down_pattern(
  value : @current.Pattern,
) -> @old.Pattern[@old.Type[Unit]] raise {
  match value {
    WildcardPattern(a) => @old.Pattern::WildcardPattern(down_va(a))
    AsPattern(a, p0, p1) =>
      @old.Pattern::AsPattern(down_va(a), down_pattern(p0), p1)
    TuplePattern(a, p0) =>
      @old.Pattern::TuplePattern(down_va(a), p0.map(down_pattern))
    ConstructorPattern(a, p0, p1) =>
      @old.Pattern::ConstructorPattern(down_va(a), p0, p1.map(down_pattern))
    EmptyListPattern(a) => @old.Pattern::EmptyListPattern(down_va(a))
    HeadTailPattern(a, p0, p1) =>
      @old.Pattern::HeadTailPattern(
        down_va(a),
        down_pattern(p0),
        down_pattern(p1),
      )
    LiteralPattern(a, p0) =>
      @old.Pattern::LiteralPattern(down_va(a), down_pattern_literal(p0))
    UnitPattern(a) => @old.Pattern::UnitPattern(down_va(a))
  }
}

///|
fn down_value(
  value : @current.Value,
) -> @old.Value[Unit, @old.Type[Unit]] raise {
  match value {
    Literal(a, p0) => @old.Value::Literal(down_va(a), down_literal(p0))
    Constructor(a, p0) => @old.Value::Constructor(down_va(a), p0)
    Tuple(a, p0) => @old.Value::Tuple(down_va(a), p0.map(down_value))
    List(a, p0) => @old.Value::List(down_va(a), p0.map(down_value))
    Record(a, p0) =>
      @old.Value::Record(
        down_va(a),
        @wire.map_values(p0, value => down_value(value)),
      )
    Variable(a, p0) => @old.Value::Variable(down_va(a), p0)
    Reference(a, p0) => @old.Value::Reference(down_va(a), p0)
    Field(a, p0, p1) => @old.Value::Field(down_va(a), down_value(p0), p1)
    FieldFunction(a, p0) => @old.Value::FieldFunction(down_va(a), p0)
    Apply(a, p0, p1) =>
      @old.Value::Apply(down_va(a), down_value(p0), down_value(p1))
    Lambda(a, p0, p1) =>
      @old.Value::Lambda(down_va(a), down_pattern(p0), down_value(p1))
    LetDefinition(a, p0, p1, p2) =>
      @old.Value::LetDefinition(
        down_va(a),
        p0,
        down_definition(p1),
        down_value(p2),
      )
    LetRecursion(a, p0, p1) =>
      @old.Value::LetRecursion(
        down_va(a),
        @wire.map_values(p0, value => down_definition(value)),
        down_value(p1),
      )
    Destructure(a, p0, p1, p2) =>
      @old.Value::Destructure(
        down_va(a),
        down_pattern(p0),
        down_value(p1),
        down_value(p2),
      )
    IfThenElse(a, p0, p1, p2) =>
      @old.Value::IfThenElse(
        down_va(a),
        down_value(p0),
        down_value(p1),
        down_value(p2),
      )
    PatternMatch(a, p0, p1) =>
      @old.Value::PatternMatch(
        down_va(a),
        down_value(p0),
        p1.map(pair => (down_pattern(pair.0), down_value(pair.1))),
      )
    UpdateRecord(a, p0, p1) =>
      @old.Value::UpdateRecord(
        down_va(a),
        down_value(p0),
        @wire.map_values(p1, value => down_value(value)),
      )
    Unit(a) => @old.Value::Unit(down_va(a))
    Hole(_, _, _) => raise @wire.Invalid("unsupported_v4_downgrade", "Hole")
  }
}

///|
fn down_literal(value : @current.Literal) -> @old.Literal raise {
  match value {
    BoolLiteral(value) => @old.Literal::BoolLiteral(value)
    CharLiteral(value) => @old.Literal::CharLiteral(value)
    StringLiteral(value) => @old.Literal::StringLiteral(value)
    IntegerLiteral(value) => @old.Literal::WholeNumberLiteral(value)
    FloatLiteral(value) => @old.Literal::FloatLiteral(value)
    DecimalLiteral(value) => @old.Literal::DecimalLiteral(value)
    DocumentLiteral(_) =>
      raise @wire.Invalid("unsupported_v4_downgrade", "DocumentLiteral")
  }
}

///|
fn down_pattern_literal(value : @current.PatternLiteral) -> @old.Literal {
  match value {
    BoolLiteral(value) => @old.Literal::BoolLiteral(value)
    CharLiteral(value) => @old.Literal::CharLiteral(value)
    StringLiteral(value) => @old.Literal::StringLiteral(value)
    IntegerLiteral(value) => @old.Literal::WholeNumberLiteral(value)
    FloatLiteral(value) => @old.Literal::FloatLiteral(value)
    DecimalLiteral(value) => @old.Literal::DecimalLiteral(value)
  }
}

///|
fn down_ta(value : @current.TypeAttributes) -> Unit raise {
  if value != @current.TypeAttributes::default() {
    raise @wire.Invalid("unsupported_attributes_downgrade", "Type attributes")
  }
}

///|
/// The attributes of a type variable, or of an extensible record, whose variable is `name`. Classic IR has no type
/// attributes. The unknown marker alone is dropped only when `name` is a classic placeholder (`t-<digits>`): the
/// name carries the same meaning. Other attributes are refused as in `down_ta`.
fn down_variable_ta(
  value : @current.TypeAttributes,
  name : @current.Name,
) -> Unit raise {
  let marker_only = value.source is None &&
    value.constraints.is_empty() &&
    value.extensions.length() == 1 &&
    value.is_unknown()
  if !(marker_only && @current.is_classic_placeholder_name(name)) {
    down_ta(value)
  }
}

///|
fn down_va(value : @current.ValueAttributes) -> @old.Type[Unit] raise {
  if value.source != None || !value.extensions.is_empty() {
    raise @wire.Invalid("unsupported_attributes_downgrade", "Value attributes")
  }
  match value.inferred_type {
    Some(tpe) => down_type(tpe)
    None =>
      raise @wire.Invalid(
        "missing_inferred_type", "Classic distributions require typed value and pattern attributes",
      )
  }
}

///|
fn down_fields(
  fields : Map[@current.Name, @current.Type],
) -> Array[@old.Field[Unit]] raise {
  fields
  .iter()
  .collect()
  .map(pair => @old.Field::{ name: pair.0, tpe: down_type(pair.1), })
}

///|
fn down_definition(
  value : @current.ValueDefinition,
) -> @old.ValueDefinition[Unit, @old.Type[Unit]] raise {
  match value {
    ExpressionBody(inputs, output, body) =>
      {
        input_types: inputs.map(input => {
          let tpe = down_type(input.1)
          (input.0, tpe, tpe)
        }),
        output_type: down_type(output),
        body: down_value(body),
      }
    _ =>
      raise @wire.Invalid(
        "unsupported_v4_downgrade", "Non-expression definition body",
      )
  }
}

///|
fn down_constructors(
  value : @current.Constructors,
) -> @old.Constructors[Unit] raise {
  @wire.map_values(value, args => args.map(arg => (arg.0, down_type(arg.1))))
}

///|
fn down_type_definition(
  value : @current.TypeDefinition,
) -> @old.TypeDefinition[Unit] raise {
  match value {
    TypeAliasDefinition(params, body) =>
      @old.TypeAliasDefinition(params, down_type(body))
    CustomTypeDefinition(params, constructors) =>
      @old.CustomTypeDefinition(params, {
        access: constructors.access,
        value: down_constructors(constructors.value),
      })
    IncompleteTypeDefinition(_, _, _) =>
      raise @wire.Invalid(
        "unsupported_v4_downgrade", "IncompleteTypeDefinition",
      )
  }
}

///|
fn down_type_specification(
  value : @current.TypeSpecification,
) -> @old.TypeSpecification[Unit] raise {
  if !value.annotations.is_empty() {
    raise @wire.Invalid("unsupported_v4_downgrade", "Type annotations")
  }
  match value.body {
    TypeAliasSpecification(params, body) =>
      @old.TypeAliasSpecification(params, down_type(body))
    OpaqueTypeSpecification(params) => @old.OpaqueTypeSpecification(params)
    CustomTypeSpecification(params, body) =>
      @old.CustomTypeSpecification(params, down_constructors(body))
    DerivedTypeSpecification(params, body) =>
      @old.DerivedTypeSpecification(params, {
        base_type: down_type(body.base_type),
        from_base_type: body.from_base_type,
        to_base_type: body.to_base_type,
      })
  }
}

///|
fn down_value_specification(
  value : @current.ValueSpecification,
) -> @old.ValueSpecification[Unit] raise {
  if !value.annotations.is_empty() {
    raise @wire.Invalid("unsupported_v4_downgrade", "Value annotations")
  }
  {
    inputs: value.inputs.map(input => (input.0, down_type(input.1))),
    output: down_type(value.output),
  }
}

///|
fn down_documentation(doc : String?) -> String raise {
  match doc {
    Some(text) => text
    None =>
      raise @wire.Invalid(
        "unsupported_documentation_downgrade", "Classic member documentation cannot represent absence",
      )
  }
}

///|
fn down_module_definition(
  value : @current.ModuleDefinition,
) -> @old.ModuleDefinition[Unit, @old.Type[Unit]] raise {
  {
    types: @wire.map_values(value.types, item => {
      access: item.access,
      value: {
        doc: down_documentation(item.value.doc),
        value: down_type_definition(item.value.value),
      },
    }),
    values: @wire.map_values(value.values, item => {
      access: item.access,
      value: {
        doc: down_documentation(item.value.doc),
        value: down_definition(item.value.value),
      },
    }),
    doc: value.doc,
  }
}

///|
fn down_package_definition(
  value : @current.PackageDefinition,
) -> @old.PackageDefinition[Unit, @old.Type[Unit]] raise {
  {
    modules: @wire.map_values(value.modules, item => {
      access: item.access,
      value: down_module_definition(item.value),
    }),
  }
}

///|
fn down_module_specification(
  value : @current.ModuleSpecification,
) -> @old.ModuleSpecification[Unit] raise {
  if !value.annotations.is_empty() {
    raise @wire.Invalid("unsupported_v4_downgrade", "Module annotations")
  }
  {
    types: @wire.map_values(value.types, item => {
      doc: down_documentation(item.doc),
      value: down_type_specification(item.value),
    }),
    values: @wire.map_values(value.values, item => {
      doc: down_documentation(item.doc),
      value: down_value_specification(item.value),
    }),
    doc: value.doc,
  }
}

///|
fn down_package_specification(
  value : @current.PackageSpecification,
) -> @old.PackageSpecification[Unit] raise {
  {
    modules: @wire.map_values(value.modules, item => {
      down_module_specification(item)
    }),
  }
}

///|
pub fn to_current(file : @old.IRFile) -> @current.IRFile raise {
  let distribution = match file.distribution {
    Library(name, dependencies, body) =>
      @current.Library(
        name,
        @wire.map_values(dependencies, up_package_specification),
        up_package_definition(body),
      )
  }
  let result = @current.IRFile::new(distribution)
  ignore(@current_json.from_json(@current_json.to_json(result)))
  result
}

///|
pub fn from_current(
  file : @current.IRFile,
  target : @version.FormatVersion,
) -> @old.IRFile raise {
  target.check_family(1U)
  let distribution = match file.distribution {
    Library(name, dependencies, body) =>
      @old.Library(
        name,
        @wire.map_values(dependencies, down_package_specification),
        down_package_definition(body),
      )
    Specs(_, _, _) =>
      raise @wire.Invalid(
        "unsupported_distribution_downgrade", "Specs needs 3.1 or v4",
      )
    Application(_, _, _, _) =>
      raise @wire.Invalid("unsupported_v4_downgrade", "Application")
  }
  let result = @old.IRFile::new(distribution, format_version=target)
  ignore(@old_json.from_json(@old_json.to_json(result)))
  result
}

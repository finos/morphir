///|
fn LibraryLowerer::integer_scalar(
  self : LibraryLowerer,
  expr : ResolvedExpr,
) -> LibraryScalar? raise {
  guard self.expr_type(expr) is @ir.Type::Reference(_, name, []) else {
    return None
  }
  match name.to_canonical() {
    "morphir/SDK:int#int-16" => Some(SignedInt16)
    "morphir/SDK:int#int-32" => Some(SignedInt32)
    "morphir/SDK:int#int-64" => Some(SignedInt64)
    "morphir/SDK:int#byte" => Some(UnsignedByte)
    "morphir/SDK:int#uint-16" => Some(UnsignedInt16)
    "morphir/SDK:int#uint-32" => Some(UnsignedInt32)
    "morphir/SDK:int#uint-64" => Some(UnsignedInt64)
    "morphir/SDK:basics#int" => Some(UnboundedInteger)
    _ => None
  }
}

///|
fn LibraryLowerer::integer_invoke(
  self : LibraryLowerer,
  name : String,
  arguments : Array[(@ir.Value, @ir.Type)],
  result : @ir.Type,
  source : @ir.SourceLocation,
  role : String,
) -> @ir.Value raise {
  self.invoke(
    name,
    arguments,
    result,
    source,
    role,
    metadata_key="moonbit-source-number-v1",
    runtime_extension=if name.has_prefix("morphir/moonbit-source:") {
      "morphir-moonbit-source-integer-v1"
    } else {
      ""
    },
  )
}

///|
fn LibraryLowerer::integer_conversion(
  self : LibraryLowerer,
  name : String,
  arguments : Array[(@ir.Value, @ir.Type)],
  result : @ir.Type,
  source : @ir.SourceLocation,
  role : String,
  policy : String,
  input_representation : String,
  output_representation : String,
) -> @ir.Value raise {
  let value = self.integer_invoke(name, arguments, result, source, role)
  let facts = @ir.Data::Object(
    Map::from_array([
      ("kind", @ir.Data::Text("conversion")),
      ("role", @ir.Data::Text(role)),
      ("policy", @ir.Data::Text(policy)),
      ("input_representation", @ir.Data::Text(input_representation)),
      ("output_representation", @ir.Data::Text(output_representation)),
      ("binding", @ir.Data::Text(name)),
      ("source_start_line", @ir.Data::Number(source.start_line.to_string())),
      ("source_start_column", @ir.Data::Number(source.start_column.to_string())),
    ]),
  )
  match value {
    @ir.Value::Apply(attrs, _, _) =>
      attrs.extensions["moonbit-source-number-v1"] = facts
    _ => abort("numeric conversion must apply a binding")
  }
  value
}

///|
fn LibraryLowerer::require_integer_budget(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
  role : String,
) -> @ir.Value raise {
  let exact = library_integer_type()
  self.integer_invoke(
    "morphir/moonbit-source:integer#require-budget",
    [(value, exact)],
    exact,
    source,
    role,
  )
}

///|
fn LibraryLowerer::integer_widen(
  self : LibraryLowerer,
  value : @ir.Value,
  scalar : LibraryScalar,
  source : @ir.SourceLocation,
  role : String,
) -> @ir.Value raise {
  if scalar == UnboundedInteger {
    return value
  }
  let bounded = LibraryTypeUse::{
    scalar,
    spelling: scalar.source_name(),
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let sdk_name = match scalar {
    SignedInt16 => "int-16"
    SignedInt64 => "int-64"
    UnsignedByte => "byte"
    UnsignedInt16 => "uint-16"
    UnsignedInt32 => "uint-32"
    UnsignedInt64 => "uint-64"
    _ => abort("unsupported integer width")
  }
  self.integer_conversion(
    "morphir/SDK:int#from-" + sdk_name,
    [(value, bounded)],
    library_integer_type(),
    source,
    role,
    "exact-widening",
    scalar.source_name(),
    "Morphir.Int",
  )
}

///|
fn LibraryLowerer::integer_normalize(
  self : LibraryLowerer,
  value : @ir.Value,
  scalar : LibraryScalar,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  if scalar == UnboundedInteger {
    return value
  }
  let bounded = LibraryTypeUse::{
    scalar,
    spelling: scalar.source_name(),
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  self.integer_conversion(
    "morphir/moonbit-source:" + scalar.source_module() + "#normalize",
    [(value, library_integer_type())],
    bounded,
    source,
    "source-width-normalization",
    "source-width-wrap",
    "Morphir.Int",
    scalar.source_name(),
  )
}

///|
fn LibraryLowerer::integer_binary(
  self : LibraryLowerer,
  op : String,
  left : @ir.Value,
  right : @ir.Value,
  scalar : LibraryScalar,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let bounded = LibraryTypeUse::{
    scalar,
    spelling: scalar.source_name(),
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let exact = library_integer_type()
  let left_name = self.fresh(left, "integer-left", source)
  let right_name = self.fresh(right, "integer-right", source)
  let left_value = @ir.Value::Variable(
    library_attributes(source, bounded),
    left_name,
  )
  let right_value = @ir.Value::Variable(
    library_attributes(source, bounded),
    right_name,
  )
  let operation = match op {
    "+" => "add"
    "-" => "subtract"
    "*" => "multiply"
    "==" => "equal"
    "!=" => "not-equal"
    "<" => "less-than"
    "<=" => "less-than-or-equal"
    ">" => "greater-than"
    ">=" => "greater-than-or-equal"
    _ => abort("checked integer operator")
  }
  let arithmetic = ["+", "-", "*"].contains(op)
  let result_type = if arithmetic { exact } else { self.boolean }
  let calculated = self.integer_invoke(
    "morphir/moonbit-source:integer#" + operation,
    [
      (self.integer_widen(left_value, scalar, source, "widen-left"), exact),
      (self.integer_widen(right_value, scalar, source, "widen-right"), exact),
    ],
    result_type,
    source,
    "integer-" + operation,
  )
  let result = if arithmetic {
    self.integer_normalize(calculated, scalar, source)
  } else {
    calculated
  }
  let output = if arithmetic { bounded } else { self.boolean }
  @ir.Value::LetDefinition(
    library_attributes(source, output),
    left_name,
    @ir.ValueDefinition::ExpressionBody([], bounded, left),
    @ir.Value::LetDefinition(
      library_attributes(source, output),
      right_name,
      @ir.ValueDefinition::ExpressionBody([], bounded, right),
      result,
    ),
  )
}

///|
fn LibraryLowerer::integer_negate(
  self : LibraryLowerer,
  value : @ir.Value,
  scalar : LibraryScalar,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let exact = library_integer_type()
  let widened = self.integer_widen(value, scalar, source, "widen-negated")
  let negated = self.integer_invoke(
    "morphir/moonbit-source:integer#negate",
    [(widened, exact)],
    exact,
    source,
    "negate-exact",
  )
  self.integer_normalize(negated, scalar, source)
}

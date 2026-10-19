///|
fn LibraryLowerer::int32_invoke(
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
      "morphir-moonbit-source-int32-v1"
    } else {
      ""
    },
  )
}

///|
/// Bind source operands once, widen to exact Int, then normalize only arithmetic
/// results. A comparison observes the exact values of the bounded operands.
fn LibraryLowerer::int32_binary(
  self : LibraryLowerer,
  op : String,
  left : @ir.Value,
  right : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let int32 = LibraryTypeUse::{
    scalar: SignedInt32,
    spelling: "Int32",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let exact = library_integer_type()
  let left_name = self.fresh(left, "int32-left", source)
  let right_name = self.fresh(right, "int32-right", source)
  let left_value = @ir.Value::Variable(
    library_attributes(source, int32),
    left_name,
  )
  let right_value = @ir.Value::Variable(
    library_attributes(source, int32),
    right_name,
  )
  let left_exact = self.int32_invoke(
    "morphir/SDK:int#from-int-32",
    [(left_value, int32)],
    exact,
    source,
    "widen-left",
  )
  let right_exact = self.int32_invoke(
    "morphir/SDK:int#from-int-32",
    [(right_value, int32)],
    exact,
    source,
    "widen-right",
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
    _ => abort("checked Int32 operator")
  }
  let arithmetic = ["+", "-", "*"].contains(op)
  let operation_type = if arithmetic { exact } else { self.boolean }
  let calculation = self.int32_invoke(
    "morphir/SDK:basics#" + operation,
    [(left_exact, exact), (right_exact, exact)],
    operation_type,
    source,
    "int32-" + operation,
  )
  let result = if arithmetic {
    self.int32_invoke(
      "morphir/moonbit-source:int32#normalize",
      [(calculation, exact)],
      int32,
      source,
      "signed-width-normalization",
    )
  } else {
    calculation
  }
  let output = if arithmetic { int32 } else { self.boolean }
  @ir.Value::LetDefinition(
    library_attributes(source, output),
    left_name,
    @ir.ValueDefinition::ExpressionBody([], int32, left),
    @ir.Value::LetDefinition(
      library_attributes(source, output),
      right_name,
      @ir.ValueDefinition::ExpressionBody([], int32, right),
      result,
    ),
  )
}

///|
fn LibraryLowerer::int32_negate(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let int32 = LibraryTypeUse::{
    scalar: SignedInt32,
    spelling: "Int32",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let exact = library_integer_type()
  let widened = self.int32_invoke(
    "morphir/SDK:int#from-int-32",
    [(value, int32)],
    exact,
    source,
    "widen-negated",
  )
  let negated = self.int32_invoke(
    "morphir/SDK:basics#negate",
    [(widened, exact)],
    exact,
    source,
    "negate-exact",
  )
  self.int32_invoke(
    "morphir/moonbit-source:int32#normalize",
    [(negated, exact)],
    int32,
    source,
    "signed-width-normalization",
  )
}

///|
priv enum ErrorContract {
  Sdk
  CheckedDecimal
}

///|
fn ErrorContract::source(self : ErrorContract) -> String {
  match self {
    Sdk => "@sdk.SdkError"
    CheckedDecimal => "Error"
  }
}

///|
/// Checked Decimal and ordinary SDK boundary errors can both escape. Select
/// the ABI from executable references, independently of optional metadata.
fn checked_decimal_errors(value : @ir.Value) -> Bool {
  match value {
    Reference(_, name) =>
      name.to_canonical().has_prefix("morphir/SDK:decimal-checked-v1#")
    Tuple(_, xs) | List(_, xs) => xs.any(checked_decimal_errors)
    Record(_, fields) => fields.values().any(checked_decimal_errors)
    Field(_, value, _) | Lambda(_, _, value) => checked_decimal_errors(value)
    Apply(_, a, b) | Destructure(_, _, a, b) =>
      checked_decimal_errors(a) || checked_decimal_errors(b)
    LetDefinition(_, _, definition, body) =>
      checked_decimal_definition_errors(definition) ||
      checked_decimal_errors(body)
    LetRecursion(_, definitions, body) =>
      definitions.values().any(checked_decimal_definition_errors) ||
      checked_decimal_errors(body)
    IfThenElse(_, a, b, c) =>
      checked_decimal_errors(a) ||
      checked_decimal_errors(b) ||
      checked_decimal_errors(c)
    PatternMatch(_, value, cases) =>
      checked_decimal_errors(value) ||
      cases.any(c => checked_decimal_errors(c.1))
    UpdateRecord(_, value, fields) =>
      checked_decimal_errors(value) ||
      fields.values().any(checked_decimal_errors)
    Literal(_, _)
    | Constructor(_, _)
    | Variable(_, _)
    | FieldFunction(_, _)
    | Unit(_)
    | Hole(_, _, _) => false
  }
}

///|
fn checked_decimal_definition_errors(definition : @ir.ValueDefinition) -> Bool {
  match definition {
    ExpressionBody(_, _, value) => checked_decimal_errors(value)
    ExternalBody(_, _, _, Some(value)) | IncompleteBody(_, _, _, Some(value)) =>
      checked_decimal_errors(value)
    NativeBody(_, _, _)
    | ExternalBody(_, _, _, None)
    | IncompleteBody(_, _, _, None) => false
  }
}

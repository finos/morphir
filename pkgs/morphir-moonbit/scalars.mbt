///|
fn scalar_type(tpe : @ir.Type, context : String) -> Scalar raise {
  match tpe {
    Unit(attrs) => {
      if !attrs.constraints.is_empty() {
        raise Invalid(
          "moonbit.unsupported_constraint", context, "Scalar constraints are not implemented",
        )
      }
      Unit
    }
    Reference(attrs, name, args) => {
      ignore(value_name(name))
      if !attrs.constraints.is_empty() || !args.is_empty() {
        raise Invalid(
          "moonbit.unsupported_type", context, "Constrained or parameterized scalar type",
        )
      }
      match name.to_canonical() {
        "morphir/SDK:basics#int" => Integer
        "morphir/SDK:int#int-32" => SignedInt32
        "morphir/SDK:int#int-16" => BoundedInteger("int-16")
        "morphir/SDK:int#int-64" => BoundedInteger("int-64")
        "morphir/SDK:int#byte" => BoundedInteger("byte")
        "morphir/SDK:int#uint-16" => BoundedInteger("uint-16")
        "morphir/SDK:int#uint-32" => BoundedInteger("uint-32")
        "morphir/SDK:int#uint-64" => BoundedInteger("uint-64")
        "morphir/SDK:basics#float" => Float
        "morphir/moonbit-source:float32#float32" => Float32
        "morphir/SDK:basics#bool" => Boolean
        "morphir/SDK:string#string" => Text
        "morphir/SDK:char#char" => Character
        "morphir/SDK:decimal#decimal" => Decimal
        _ =>
          raise Invalid(
            "moonbit.unsupported_type",
            context,
            name.to_canonical(),
          )
      }
    }
    Variable(_, _) =>
      raise Invalid(
        "moonbit.ambiguous_type", context, "A concrete scalar type is required",
      )
    _ =>
      raise Invalid(
        "moonbit.unsupported_type", context, "This slice supports scalar types only",
      )
  }
}

///|
fn moon_type(scalar : Scalar, imports : Map[String, Bool]) -> String {
  match scalar {
    SignedInt32 => {
      imports["int"] = true
      "@int.Int32Value"
    }
    BoundedInteger(name) => {
      imports["int"] = true
      match name {
        "int-16" => "@int.Int16Value"
        "int-64" => "@int.Int64Value"
        "byte" => "@int.ByteValue"
        "uint-16" => "@int.UInt16Value"
        "uint-32" => "@int.UInt32Value"
        "uint-64" => "@int.UInt64Value"
        _ => abort("admitted integer boundary")
      }
    }
    Integer => {
      imports["integer"] = true
      "@integer.Integer"
    }
    Decimal => {
      imports["decimal"] = true
      "@decimal.Decimal"
    }
    Text => "@sdk.Text"
    Character => "@sdk.Character"
    Float | Float32 => "Double"
    Boolean => "Bool"
    Unit => "Unit"
  }
}

///|
fn units(text : String) -> String {
  "[" +
  text
  .code_units()
  .iter()
  .map(unit => "(" + unit.to_int().to_string() + ").to_uint16()")
  .collect()
  .join(", ") +
  "]"
}

///|
/// Normalize only at numerical SDK construction; the source lexeme stays in Ion metadata.
fn decimal_constant(text : String, context : String) -> String raise {
  ignore(@wire.decimal(Json::string(text)))
  let scientific = text
    .to_lower()
    .split("e")
    .map(StringView::to_owned)
    .collect()
  let exponent = if scientific.length() == 2 {
    @bigint.BigInt::from_string(scientific[1].replace(old="+", new=""))
  } else {
    @bigint.BigInt::from_int(0)
  }
  if exponent.compare_int(-10000) < 0 || exponent.compare_int(10000) > 0 {
    raise Invalid(
      "moonbit.literal_out_of_range", context, "Decimal exponent exceeds construction budget",
    )
  }
  let components = scientific[0].split(".").map(StringView::to_owned).collect()
  let fraction = if components.length() == 2 { components[1] } else { "" }
  let coefficient = @bigint.BigInt::from_string(
    (components[0] + fraction).replace(old="+", new=""),
  )
  if coefficient.is_zero() {
    return "0"
  }
  let negative = coefficient.compare_int(0) < 0
  let digits = (if negative { -coefficient } else { coefficient }).to_string()
  let mut end = digits.length()
  let mut scale = exponent.to_int() - fraction.length()
  while end > 1 && digits.code_unit_at(end - 1).to_int() == 48 {
    end -= 1
    scale += 1
  }
  if scale < -32 {
    raise Invalid(
      "moonbit.literal_precision_loss", context, "SDK Decimal would truncate digits below exponent -32",
    )
  }
  let significant = digits[:end].to_owned()
  let canonical = (if negative { "-" } else { "" }) +
    significant[:1].to_owned() +
    (if end > 1 { "." + significant[1:].to_owned() } else { "" }) +
    "e" +
    (scale + end - 1).to_string()
  let number = match @decimal.from_string(canonical) {
    Some(value) => value
    None =>
      raise Invalid(
        "moonbit.literal_out_of_range", context, "SDK Decimal rejected normalized construction",
      )
  }
  let normalized_coefficient = @bigint.BigInt::from_string(
    (if negative { "-" } else { "" }) + significant,
  )
  if number.coefficient != normalized_coefficient || number.exponent != scale {
    raise Invalid(
      "moonbit.literal_precision_loss", context, "SDK Decimal changed the exact coefficient or exponent",
    )
  }
  canonical
}

///|
fn check_annotation(
  attrs : @ir.ValueAttributes,
  expected : Scalar,
  context : String,
) -> Unit raise {
  if attrs.inferred_type is Some(tpe) {
    if scalar_type(tpe, context) != expected {
      raise Invalid(
        "moonbit.type_mismatch", context, "Inferred type contradicts the declared type",
      )
    }
  }
}

///|
fn scalar_literal(
  body : @ir.Value,
  expected : Scalar,
  imports : Map[String, Bool],
  context : String,
) -> String raise {
  match body {
    Literal(attrs, literal) => {
      check_annotation(attrs, expected, context)
      let (actual, source) = match literal {
        BoolLiteral(value) => (Scalar::Boolean, value.to_string())
        IntegerLiteral(text) => {
          ignore(@integer.parse(text))
          imports["integer"] = true
          (Scalar::Integer, "@integer.parse(" + quote(text) + ")")
        }
        DecimalLiteral(text) => {
          imports["decimal"] = true
          let construction = quote(decimal_constant(text, context))
          (
            Scalar::Decimal,
            "match @decimal.from_string(" +
            construction +
            ") { Some(value) => value; None => raise @sdk.InvalidNumber(" +
            construction +
            ") }",
          )
        }
        StringLiteral(text) =>
          (Scalar::Text, "@sdk.Text::from_units(" + units(text) + ")")
        CharLiteral(character) =>
          (
            Scalar::Character,
            "@sdk.Character::from_units(" + units(character.to_string()) + ")",
          )
        FloatLiteral(value) => {
          if value.is_nan() || value.is_inf() {
            raise Invalid("moonbit.invalid_literal", context, "Nonfinite Float")
          }
          let literal = "(" +
            value.reinterpret_as_uint64().to_string() +
            "UL).reinterpret_as_double()"
          if expected == Scalar::Float32 {
            imports["source_float"] = true
            (Scalar::Float32, "@source_float.round32(" + literal + ")")
          } else {
            (Scalar::Float, literal)
          }
        }
        DocumentLiteral(_) =>
          raise Invalid(
            "moonbit.unsupported_literal", context, "Document literals are not implemented",
          )
      }
      if actual != expected {
        raise Invalid(
          "moonbit.type_mismatch", context, "Literal and declared output types differ",
        )
      }
      source
    }
    Unit(attrs) => {
      check_annotation(attrs, expected, context)
      if expected != Scalar::Unit {
        raise Invalid(
          "moonbit.type_mismatch", context, "Unit body has a non-Unit declaration",
        )
      }
      "()"
    }
    Hole(_, _, _) =>
      raise Invalid("moonbit.incomplete_body", context, "Hole expression")
    _ =>
      raise Invalid(
        "moonbit.unsupported_expression", context, "Expected a scalar literal or Unit",
      )
  }
}

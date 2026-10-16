///|
fn sdk_integer(
  value : @scheme.Value,
) -> @integer.Integer raise @scheme.SchemeError {
  match value {
    @scheme.Number(@scheme.Number::Integer(n)) => @integer.from_bigint(n)
    _ => raise @scheme.Invalid("Expected Morphir Integer")
  }
}

///|
fn sdk_int(value : @scheme.Value) -> Int32 raise @scheme.SchemeError {
  match @integer.to_int(sdk_integer(value)) {
    Some(n) => n
    None => raise @scheme.Invalid("Integer is outside the host Int range")
  }
}

///|
fn sdk_float(value : @scheme.Value) -> Double raise @scheme.SchemeError {
  match value {
    @scheme.Number(@scheme.Number::Real(n)) => n
    @scheme.Number(@scheme.Number::Integer(n)) =>
      @integer.to_float(@integer.from_bigint(n))
    _ => raise @scheme.Invalid("Expected Morphir Float")
  }
}

///|
fn sdk_bool(value : @scheme.Value) -> Bool raise @scheme.SchemeError {
  match value {
    @scheme.Boolean(n) => n
    _ => raise @scheme.Invalid("Expected Morphir Bool")
  }
}

///|
fn sdk_text_units(
  value : @scheme.Value,
) -> Array[UInt16] raise @scheme.SchemeError {
  let items = match value {
    @scheme.Tagged("sdk-text", [@scheme.Vector(items)]) => items
    @scheme.Tagged("sdk-character", [@scheme.Vector(items)]) => items
    _ => raise @scheme.Invalid("Expected UTF-16 code units")
  }
  let units : Array[UInt16] = []
  for item in items {
    let code = sdk_int(item)
    if code < 0 || code > 65535 {
      raise @scheme.Invalid("Invalid UTF-16 code unit")
    }
    units.push(code.to_uint16())
  }
  units
}

///|
fn sdk_text(value : @scheme.Value) -> @sdk.Text raise @scheme.SchemeError {
  match value {
    @scheme.Text(source) => @sdk.Text::from_string(source)
    @scheme.Tagged("sdk-text", _) =>
      @sdk.Text::from_units(sdk_text_units(value))
    _ => raise @scheme.Invalid("Expected Morphir Text")
  }
}

///|
fn sdk_text_value(value : @sdk.Text) -> @scheme.Value {
  let source = Some(value.to_string()) catch { _ => None }
  match source {
    Some(source) => @scheme.Text(source)
    None => {
      let units = value
        .to_units()
        .map(unit => exact_integer(@integer.from_int(unit.to_int())))
      @scheme.Tagged("sdk-text", [@scheme.Vector(units)])
    }
  }
}

///|
fn sdk_character(
  value : @scheme.Value,
) -> @sdk.Character raise @scheme.SchemeError {
  match value {
    @scheme.Character(character) => @sdk.Character::from_char(character)
    @scheme.Tagged("sdk-character", _) =>
      @sdk.Character::from_units(sdk_text_units(value))
    _ => raise @scheme.Invalid("Expected Morphir Character")
  }
}

///|
fn sdk_character_value(value : @sdk.Character) -> @scheme.Value {
  let source = Some(value.to_string()) catch { _ => None }
  match source {
    Some(source) => {
      let chars = source.to_array()
      if chars.length() == 1 {
        return @scheme.Character(chars[0])
      }
    }
    None => ()
  }
  let units = value
    .to_units()
    .map(unit => exact_integer(@integer.from_int(unit.to_int())))
  @scheme.Tagged("sdk-character", [@scheme.Vector(units)])
}

///|
fn sdk_decimal(
  value : @scheme.Value,
) -> @sdk_decimal.Decimal raise @scheme.SchemeError {
  match value {
    @scheme.Tagged("decimal", [@scheme.Text(source)]) =>
      match @sdk_decimal.from_string(source) {
        Some(decimal) => decimal
        None => raise @scheme.Invalid("Invalid Morphir Decimal")
      }
    @scheme.Number(@scheme.Number::Integer(n)) =>
      @sdk_decimal.from_integer(@integer.from_bigint(n))
    _ => raise @scheme.Invalid("Expected Morphir Decimal")
  }
}

///|
fn sdk_decimal_value(value : @sdk_decimal.Decimal) -> @scheme.Value {
  @scheme.Tagged("decimal", [@scheme.Text(@sdk_decimal.to_string(value))])
}

///|
fn sdk_maybe(value : @scheme.Value) -> @scheme.Value? raise @scheme.SchemeError {
  match value {
    @scheme.Tagged("morphir/SDK:maybe#just", [item]) => Some(item)
    @scheme.Tagged("morphir/SDK:maybe#nothing", []) => None
    _ => raise @scheme.Invalid("Expected Morphir Maybe")
  }
}

///|
fn sdk_maybe_value(value : @scheme.Value?) -> @scheme.Value {
  match value {
    Some(item) => @scheme.Tagged("morphir/SDK:maybe#just", [item])
    None => @scheme.Tagged("morphir/SDK:maybe#nothing", [])
  }
}

///|
fn sdk_result(
  value : @scheme.Value,
) -> Result[@scheme.Value, @scheme.Value] raise @scheme.SchemeError {
  match value {
    @scheme.Tagged("morphir/SDK:result#ok", [item]) => Ok(item)
    @scheme.Tagged("morphir/SDK:result#err", [item]) => Err(item)
    _ => raise @scheme.Invalid("Expected Morphir Result")
  }
}

///|
fn sdk_result_value(
  value : Result[@scheme.Value, @scheme.Value],
) -> @scheme.Value {
  match value {
    Ok(item) => @scheme.Tagged("morphir/SDK:result#ok", [item])
    Err(item) => @scheme.Tagged("morphir/SDK:result#err", [item])
  }
}

///|
fn sdk_order_value(value : @sdk.Order) -> @scheme.Value {
  let tag = match value {
    @sdk.LT => "l-t"
    @sdk.EQ => "e-q"
    @sdk.GT => "g-t"
  }
  @scheme.Tagged("morphir/SDK:basics#" + tag, [])
}

///|
fn sdk_order(value : @scheme.Value) -> @sdk.Order raise @scheme.SchemeError {
  match value {
    @scheme.Tagged("morphir/SDK:basics#l-t", []) => @sdk.LT
    @scheme.Tagged("morphir/SDK:basics#e-q", []) => @sdk.EQ
    @scheme.Tagged("morphir/SDK:basics#g-t", []) => @sdk.GT
    _ => raise @scheme.Invalid("Expected Morphir Order")
  }
}

///|
/// Morphir functions are curried, including callbacks passed to SDK functions.
fn sdk_apply(
  runtime : @scheme.Runtime,
  callback : @scheme.Value,
  arguments : Array[@scheme.Value],
) -> @scheme.Value raise {
  let mut result = callback
  for argument in arguments {
    result = runtime.call(result, [argument])
  }
  result
}

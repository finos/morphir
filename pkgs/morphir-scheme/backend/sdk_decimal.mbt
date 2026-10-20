///|
fn sdk_decimal_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name
    .clamped_view(start="morphir/SDK:decimal#".length())
    .to_owned()
  match suffix {
    "from-int" => sdk_decimal_value(@sdk_decimal.from_int(sdk_integer(args[0])))
    "from-float" => {
      let value = sdk_float(args[0])
      sdk_decimal_value(
        @sdk_decimal.from_float(value) catch {
          error => raise sdk_error(name, error)
        },
      )
    }
    "from-string" =>
      sdk_maybe_value(
        match
          @sdk_decimal.from_string(
            sdk_text(args[0]).to_string() catch {
              _ => return sdk_maybe_value(None)
            },
          ) {
          Some(value) => Some(sdk_decimal_value(value))
          None => None
        },
      )
    "hundred" => sdk_decimal_value(@sdk_decimal.hundred(sdk_integer(args[0])))
    "thousand" => sdk_decimal_value(@sdk_decimal.thousand(sdk_integer(args[0])))
    "million" => sdk_decimal_value(@sdk_decimal.million(sdk_integer(args[0])))
    "tenth" => sdk_decimal_value(@sdk_decimal.tenth(sdk_integer(args[0])))
    "hundredth" =>
      sdk_decimal_value(@sdk_decimal.hundredth(sdk_integer(args[0])))
    "thousandth" =>
      sdk_decimal_value(@sdk_decimal.thousandth(sdk_integer(args[0])))
    "millionth" =>
      sdk_decimal_value(@sdk_decimal.millionth(sdk_integer(args[0])))
    "bps" => sdk_decimal_value(@sdk_decimal.bps(sdk_integer(args[0])))
    "to-string" =>
      sdk_text_value(
        @sdk.Text::from_string(@sdk_decimal.to_string(sdk_decimal(args[0]))),
      )
    "to-float" =>
      @scheme.Number(
        @scheme.Number::Real(@sdk_decimal.to_float(sdk_decimal(args[0]))),
      )
    "add" =>
      sdk_decimal_value(
        @sdk_decimal.add(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "sub" =>
      sdk_decimal_value(
        @sdk_decimal.sub(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "negate" => sdk_decimal_value(@sdk_decimal.negate(sdk_decimal(args[0])))
    "mul" =>
      sdk_decimal_value(
        @sdk_decimal.mul(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "div" =>
      sdk_maybe_value(
        match @sdk_decimal.div(sdk_decimal(args[0]), sdk_decimal(args[1])) {
          Some(value) => Some(sdk_decimal_value(value))
          None => None
        },
      )
    "div-with-default" =>
      sdk_decimal_value(
        @sdk_decimal.div_with_default(
          sdk_decimal(args[0]),
          sdk_decimal(args[1]),
          sdk_decimal(args[2]),
        ),
      )
    "truncate" => sdk_decimal_value(@sdk_decimal.truncate(sdk_decimal(args[0])))
    "round" => sdk_decimal_value(@sdk_decimal.round(sdk_decimal(args[0])))
    "gt" =>
      @scheme.Boolean(
        @sdk_decimal.gt(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "gte" =>
      @scheme.Boolean(
        @sdk_decimal.gte(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "eq" =>
      @scheme.Boolean(
        @sdk_decimal.eq(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "neq" =>
      @scheme.Boolean(
        @sdk_decimal.neq(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "lt" =>
      @scheme.Boolean(
        @sdk_decimal.lt(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "lte" =>
      @scheme.Boolean(
        @sdk_decimal.lte(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "compare" =>
      sdk_order_value(
        @sdk_decimal.compare(sdk_decimal(args[0]), sdk_decimal(args[1])),
      )
    "abs" => sdk_decimal_value(@sdk_decimal.abs(sdk_decimal(args[0])))
    "shift-decimal-left" =>
      sdk_decimal_value(
        @sdk_decimal.shift_decimal_left(sdk_int(args[0]), sdk_decimal(args[1])),
      )
    "shift-decimal-right" =>
      sdk_decimal_value(
        @sdk_decimal.shift_decimal_right(sdk_int(args[0]), sdk_decimal(args[1])),
      )
    "zero" => sdk_decimal_value(@sdk_decimal.zero())
    "one" => sdk_decimal_value(@sdk_decimal.one())
    "minus-one" => sdk_decimal_value(@sdk_decimal.minus_one())
    _ => raise @scheme.Unbound(name)
  }
}

///|
fn checked_decimal_registry() -> Array[(String, Int32)] {
  [
    ("morphir/SDK:decimal-checked-v1#from-string-exact", 1),
    ("morphir/SDK:decimal-checked-v1#divide", 2),
    ("morphir/SDK:decimal-checked-v1#divide-with-default", 3),
  ]
}

///|
fn checked_decimal_arity(name : String) -> Int32? {
  checked_decimal_registry()
  .filter(row => row.0 == name)
  .get(0)
  .map(row => row.1)
}

///|
fn checked_decimal_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let result = try {
    match name {
      "morphir/SDK:decimal-checked-v1#from-string-exact" => {
        let text = sdk_text(args[0]).to_string() catch {
          _ => raise @scheme.Domain("sdk.decimal.invalid_literal", name)
        }
        @sdk_decimal.from_string_exact(text)
      }
      "morphir/SDK:decimal-checked-v1#divide" =>
        @sdk_decimal.divide(sdk_decimal(args[0]), sdk_decimal(args[1]))
      "morphir/SDK:decimal-checked-v1#divide-with-default" =>
        @sdk_decimal.divide_with_default(
          sdk_decimal(args[0]),
          sdk_decimal(args[1]),
          sdk_decimal(args[2]),
        )
      _ => raise @scheme.Unbound(name)
    }
  } catch {
    @sdk_decimal.DivisionByZero =>
      raise @scheme.Domain("sdk.decimal.division_by_zero", name)
    @sdk_decimal.Underflow =>
      raise @scheme.Domain("sdk.decimal.underflow", name)
    @sdk_decimal.PrecisionLoss =>
      raise @scheme.Domain("sdk.decimal.precision_loss", name)
    @sdk_decimal.InvalidLiteral =>
      raise @scheme.Domain("sdk.decimal.invalid_literal", name)
    error => raise error
  }
  sdk_decimal_value(result)
}

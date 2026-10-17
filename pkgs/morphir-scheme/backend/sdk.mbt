///|
fn sdk_error(name : String, error : @sdk.SdkError) -> @scheme.SchemeError {
  let detail = match error {
    @sdk.DivisionByZero => "division by zero"
    @sdk.InvalidNumber(message) => "invalid number: " + message
    @sdk.OutOfRange(message) => "out of range: " + message
    @sdk.InvalidComparison(message) => "invalid comparison: " + message
    @sdk.UnrepresentableText(message) => "unrepresentable text: " + message
  }
  let code = match error {
    @sdk.DivisionByZero => "sdk.division_by_zero"
    @sdk.InvalidNumber(_) => "sdk.invalid_number"
    @sdk.OutOfRange(_) => "sdk.out_of_range"
    @sdk.InvalidComparison(_) => "sdk.invalid_comparison"
    @sdk.UnrepresentableText(_) => "sdk.unrepresentable_text"
  }
  @scheme.Domain(code, name + ": " + detail)
}

///|
fn exact_integer(value : @integer.Integer) -> @scheme.Value {
  @scheme.Number(@scheme.Number::Integer(@integer.to_bigint(value)))
}

///|
fn sdk_integer_binary(
  name : String,
  left : @integer.Integer,
  right : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  match name {
    "morphir/SDK:basics#add" => @basics.add_int(left, right)
    "morphir/SDK:basics#subtract" => @basics.subtract_int(left, right)
    "morphir/SDK:basics#multiply" => @basics.multiply_int(left, right)
    "morphir/SDK:basics#integer-divide" => @basics.integer_divide(left, right)
    "morphir/SDK:basics#mod-by" => @basics.mod_by(left, right)
    "morphir/SDK:basics#remainder-by" => @basics.remainder_by(left, right)
    "morphir/SDK:basics#power" => @basics.power_int(left, right)
    _ => raise @sdk.InvalidNumber("Unsupported integer SDK operation")
  }
}

///|
fn sdk_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  sdk_dispatch_inner(rt, name, args) catch {
    @sdk.DivisionByZero => raise sdk_error(name, @sdk.DivisionByZero)
    @sdk.InvalidNumber(message) =>
      raise sdk_error(name, @sdk.InvalidNumber(message))
    @sdk.OutOfRange(message) => raise sdk_error(name, @sdk.OutOfRange(message))
    @sdk.InvalidComparison(message) =>
      raise sdk_error(name, @sdk.InvalidComparison(message))
    @sdk.UnrepresentableText(message) =>
      raise sdk_error(name, @sdk.UnrepresentableText(message))
    error => raise error
  }
}

///|
fn sdk_dispatch_inner(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let name = sdk_int_binding(name)
  if name.has_prefix("morphir/moonbit-source:") {
    return source_string_dispatch(name, args)
  }
  if name.has_prefix("morphir/SDK:basics#") {
    return sdk_basics_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:string#") {
    return sdk_string_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:char#") {
    return sdk_char_dispatch(name, args)
  }
  if name.has_prefix("morphir/SDK:int#") {
    return sdk_int_dispatch(name, args)
  }
  if name.has_prefix("morphir/SDK:decimal#") {
    return sdk_decimal_dispatch(name, args)
  }
  if name.has_prefix("morphir/SDK:maybe#") {
    return sdk_maybe_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:result#") {
    return sdk_result_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:list#") {
    return sdk_list_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:set#") {
    return sdk_set_dispatch(rt, name, args)
  }
  if name.has_prefix("morphir/SDK:dict#") {
    return sdk_dict_dispatch(rt, name, args)
  }
  raise @scheme.Unsupported("SDK adapter pending for " + name)
}

///|
fn install_sdk(
  runtime : @scheme.Runtime,
  accelerators : Bool,
  model_errors : Bool,
) -> Unit raise @scheme.SchemeError {
  runtime.define_native("%morphir-sdk", fn(rt, args) raise {
    if args.is_empty() {
      raise @scheme.Invalid("Morphir SDK call requires a value name")
    }
    let name = sdk_int_binding(args[0].as_text())
    match
      (match source_string_arity(name) {
        Some(n) => Some(n)
        None => sdk_expected_arity(name)
      }) {
      Some(expected) => @scheme.arity(args[1:].to_owned(), expected, name)
      None => raise @scheme.Unbound(name)
    }
    sdk_dispatch(rt, name, args[1:].to_owned()) catch {
      @scheme.Domain(code, message) => {
        if model_errors {
          raise @scheme.Domain(code, message)
        }
        raise @scheme.Invalid(message)
      }
      error => raise error
    }
  })
  if !accelerators {
    return
  }
  for
    (name, arity) in sdk_registry() +
    source_string_registry() +
    sdk_int_canonical_aliases() {
    runtime.register_native_binding("accelerator:" + name, arity, fn(
      rt,
      values,
    ) raise {
      let args : Array[@scheme.Value] = [@scheme.Value::Text(name)]
      args.append(values)
      rt.call(rt.lookup("%morphir-sdk"), args)
    })
  }
}

///|
fn sdk_unary(name : String, input : @scheme.Value) -> @scheme.Value raise {
  match input {
    @scheme.Number(@scheme.Number::Integer(n)) => {
      let integer = @integer.from_bigint(n)
      let result = match name {
        "morphir/SDK:basics#negate" =>
          exact_integer(@basics.negate_int(integer))
        "morphir/SDK:basics#abs" => exact_integer(@basics.abs_int(integer))
        "morphir/SDK:basics#to-float" =>
          @scheme.Number(@scheme.Number::Real(@basics.to_float(integer)))
        _ => raise @scheme.Invalid(name + ": unsupported Integer SDK operation")
      }
      result
    }
    @scheme.Number(@scheme.Number::Real(value)) => {
      let result = match name {
        "morphir/SDK:basics#negate" =>
          @scheme.Value::Number(
            @scheme.Number::Real(@basics.negate_float(value)),
          )
        "morphir/SDK:basics#abs" =>
          @scheme.Value::Number(@scheme.Number::Real(@basics.abs_float(value)))
        "morphir/SDK:basics#round" =>
          exact_integer(
            @basics.round(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#floor" =>
          exact_integer(
            @basics.floor(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#ceiling" =>
          exact_integer(
            @basics.ceiling(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#truncate" =>
          exact_integer(
            @basics.truncate(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#is-na-n" => @scheme.Boolean(@basics.is_nan(value))
        "morphir/SDK:basics#is-infinite" =>
          @scheme.Boolean(@basics.is_infinite(value))
        _ => raise @scheme.Invalid(name + ": unsupported Float SDK operation")
      }
      result
    }
    _ => raise @scheme.Invalid(name + ": incompatible SDK operand")
  }
}

///|
fn sdk_assert_equality_data(
  value : @scheme.Value,
  depth : Int32,
) -> Unit raise @scheme.SchemeError {
  if depth > 256 {
    raise @scheme.Limit("SDK equality depth")
  }
  match value {
    @scheme.Closure(_) | @scheme.Native(_) | @scheme.NativeFunction(_) =>
      raise @scheme.Invalid("Morphir equality does not support functions")
    @scheme.Pair(head, tail) => {
      sdk_assert_equality_data(head, depth + 1)
      sdk_assert_equality_data(tail, depth + 1)
    }
    @scheme.Vector(items) | @scheme.Tagged(_, items) =>
      for item in items {
        sdk_assert_equality_data(item, depth + 1)
      }
    @scheme.Record(fields) =>
      for _, item in fields {
        sdk_assert_equality_data(item, depth + 1)
      }
    _ => ()
  }
}

///|
fn sdk_contains_nan(
  value : @scheme.Value,
  depth : Int32,
) -> Bool raise @scheme.SchemeError {
  if depth > 256 {
    raise @scheme.Limit("SDK equality depth")
  }
  match value {
    @scheme.Number(@scheme.Number::Real(n)) => @basics.is_nan(n)
    @scheme.Pair(head, tail) =>
      sdk_contains_nan(head, depth + 1) || sdk_contains_nan(tail, depth + 1)
    @scheme.Vector(items) | @scheme.Tagged(_, items) => {
      for item in items {
        if sdk_contains_nan(item, depth + 1) {
          return true
        }
      }
      false
    }
    @scheme.Record(fields) => {
      for _, item in fields {
        if sdk_contains_nan(item, depth + 1) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn sdk_normalize_equality(
  value : @scheme.Value,
  depth : Int32,
) -> @scheme.Value raise @scheme.SchemeError {
  if depth > 256 {
    raise @scheme.Limit("SDK equality depth")
  }
  match value {
    @scheme.Tagged("decimal", _) => sdk_decimal_value(sdk_decimal(value))
    @scheme.Pair(head, tail) =>
      @scheme.Pair(
        sdk_normalize_equality(head, depth + 1),
        sdk_normalize_equality(tail, depth + 1),
      )
    @scheme.Vector(items) =>
      @scheme.Vector(items.map(item => sdk_normalize_equality(item, depth + 1)))
    @scheme.Tagged(tag, items) =>
      @scheme.Tagged(
        tag,
        items.map(item => sdk_normalize_equality(item, depth + 1)),
      )
    @scheme.Record(fields) => {
      let normalized : Map[String, @scheme.Value] = Map([])
      for key, item in fields {
        normalized[key] = sdk_normalize_equality(item, depth + 1)
      }
      @scheme.Record(normalized)
    }
    _ => value
  }
}

///|
fn sdk_compare(
  left : @scheme.Value,
  right : @scheme.Value,
  depth : Int32,
) -> @sdk.Order raise @scheme.SchemeError {
  if depth > 256 {
    raise @scheme.Limit("SDK comparison depth")
  }
  match (left, right) {
    (
      @scheme.Number(@scheme.Number::Integer(a)),
      @scheme.Number(@scheme.Number::Integer(b)),
    ) => @basics.compare_int(@integer.from_bigint(a), @integer.from_bigint(b))
    (
      @scheme.Number(@scheme.Number::Real(a)),
      @scheme.Number(@scheme.Number::Real(b)),
    ) =>
      @basics.compare_float(a, b) catch {
        error => raise sdk_error("morphir/SDK:basics#compare", error)
      }
    (@scheme.Text(_), @scheme.Text(_)) =>
      @basics.compare_string(sdk_text(left), sdk_text(right))
    (@scheme.Tagged("sdk-text", _), @scheme.Tagged("sdk-text", _)) =>
      @basics.compare_string(sdk_text(left), sdk_text(right))
    (@scheme.Text(_), @scheme.Tagged("sdk-text", _))
    | (@scheme.Tagged("sdk-text", _), @scheme.Text(_)) =>
      @basics.compare_string(sdk_text(left), sdk_text(right))
    (@scheme.Character(_), @scheme.Character(_)) =>
      @sdk.text_order(
        sdk_character(left).to_text(),
        sdk_character(right).to_text(),
      )
    (@scheme.Tagged("sdk-character", _), @scheme.Tagged("sdk-character", _))
    | (@scheme.Character(_), @scheme.Tagged("sdk-character", _))
    | (@scheme.Tagged("sdk-character", _), @scheme.Character(_)) =>
      @sdk.text_order(
        sdk_character(left).to_text(),
        sdk_character(right).to_text(),
      )
    (@scheme.Tagged("decimal", _), @scheme.Tagged("decimal", _)) =>
      @sdk_decimal.compare(sdk_decimal(left), sdk_decimal(right))
    (@scheme.Nil, @scheme.Nil) => @sdk.EQ
    (@scheme.Nil, @scheme.Pair(_, _)) => @sdk.LT
    (@scheme.Pair(_, _), @scheme.Nil) => @sdk.GT
    (@scheme.Pair(a, at), @scheme.Pair(b, bt)) => {
      let first = sdk_compare(a, b, depth + 1)
      if first is @sdk.EQ {
        sdk_compare(at, bt, depth + 1)
      } else {
        first
      }
    }
    (@scheme.Vector(a), @scheme.Vector(b)) => {
      let minimum = if a.length() < b.length() {
        a.length()
      } else {
        b.length()
      }
      for i = 0; i < minimum; i = i + 1 {
        let order = sdk_compare(a[i], b[i], depth + 1)
        if !(order is @sdk.EQ) {
          return order
        }
      }
      @sdk.order(a.length() - b.length())
    }
    _ => raise @scheme.Invalid("Unsupported Morphir comparable values")
  }
}

///|
fn sdk_pair(
  value : @scheme.Value,
) -> (Double, Double) raise @scheme.SchemeError {
  match value {
    @scheme.Vector([a, b]) => (sdk_float(a), sdk_float(b))
    _ => raise @scheme.Invalid("Expected a pair of Floats")
  }
}

///|
fn sdk_float_pair(pair : (Double, Double)) -> @scheme.Value {
  let (a, b) = pair
  @scheme.Vector([
    @scheme.Number(@scheme.Number::Real(a)),
    @scheme.Number(@scheme.Number::Real(b)),
  ])
}

///|
fn sdk_basics_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name
    .clamped_view(start="morphir/SDK:basics#".length())
    .to_owned()
  match suffix {
    "add" | "subtract" | "multiply" | "power" =>
      match (args[0], args[1]) {
        (
          @scheme.Number(@scheme.Number::Integer(a)),
          @scheme.Number(@scheme.Number::Integer(b)),
        ) =>
          exact_integer(
            sdk_integer_binary(
              name,
              @integer.from_bigint(a),
              @integer.from_bigint(b),
            ) catch {
              error => raise sdk_error(name, error)
            },
          )
        (
          @scheme.Number(@scheme.Number::Real(a)),
          @scheme.Number(@scheme.Number::Real(b)),
        ) => {
          let result = match suffix {
            "add" => @basics.add_float(a, b)
            "subtract" => @basics.subtract_float(a, b)
            "multiply" => @basics.multiply_float(a, b)
            _ => @basics.power_float(a, b)
          }
          @scheme.Number(@scheme.Number::Real(result))
        }
        _ => raise @scheme.Invalid(name + ": incompatible numeric operands")
      }
    "divide" =>
      @scheme.Number(
        @scheme.Number::Real(
          @basics.divide(sdk_float(args[0]), sdk_float(args[1])),
        ),
      )
    "integer-divide" | "mod-by" | "remainder-by" => {
      let left = sdk_integer(args[0])
      let right = sdk_integer(args[1])
      exact_integer(
        sdk_integer_binary(name, left, right) catch {
          error => raise sdk_error(name, error)
        },
      )
    }
    "to-float"
    | "round"
    | "floor"
    | "ceiling"
    | "truncate"
    | "negate"
    | "abs"
    | "is-na-n"
    | "is-infinite" => sdk_unary(name, args[0])
    "clamp" =>
      match (args[0], args[1], args[2]) {
        (
          @scheme.Number(@scheme.Number::Integer(_)),
          @scheme.Number(@scheme.Number::Integer(_)),
          @scheme.Number(@scheme.Number::Integer(_)),
        ) =>
          exact_integer(
            @basics.clamp_int(
              sdk_integer(args[0]),
              sdk_integer(args[1]),
              sdk_integer(args[2]),
            ),
          )
        _ =>
          @scheme.Number(
            @scheme.Number::Real(
              @basics.clamp_float(
                sdk_float(args[0]),
                sdk_float(args[1]),
                sdk_float(args[2]),
              ),
            ),
          )
      }
    "sqrt" =>
      @scheme.Number(@scheme.Number::Real(@basics.sqrt(sdk_float(args[0]))))
    "log-base" =>
      @scheme.Number(
        @scheme.Number::Real(
          @basics.log_base(sdk_float(args[0]), sdk_float(args[1])),
        ),
      )
    "e" => @scheme.Number(@scheme.Number::Real(@basics.e()))
    "pi" => @scheme.Number(@scheme.Number::Real(@basics.pi()))
    "cos" =>
      @scheme.Number(@scheme.Number::Real(@basics.cos(sdk_float(args[0]))))
    "sin" =>
      @scheme.Number(@scheme.Number::Real(@basics.sin(sdk_float(args[0]))))
    "tan" =>
      @scheme.Number(@scheme.Number::Real(@basics.tan(sdk_float(args[0]))))
    "acos" =>
      @scheme.Number(@scheme.Number::Real(@basics.acos(sdk_float(args[0]))))
    "asin" =>
      @scheme.Number(@scheme.Number::Real(@basics.asin(sdk_float(args[0]))))
    "atan" =>
      @scheme.Number(@scheme.Number::Real(@basics.atan(sdk_float(args[0]))))
    "atan2" =>
      @scheme.Number(
        @scheme.Number::Real(
          @basics.atan2(sdk_float(args[0]), sdk_float(args[1])),
        ),
      )
    "degrees" =>
      @scheme.Number(@scheme.Number::Real(@basics.degrees(sdk_float(args[0]))))
    "radians" =>
      @scheme.Number(@scheme.Number::Real(@basics.radians(sdk_float(args[0]))))
    "turns" =>
      @scheme.Number(@scheme.Number::Real(@basics.turns(sdk_float(args[0]))))
    "to-polar" => sdk_float_pair(@basics.to_polar(sdk_pair(args[0])))
    "from-polar" => sdk_float_pair(@basics.from_polar(sdk_pair(args[0])))
    "equal" | "not-equal" => {
      sdk_assert_equality_data(args[0], 0)
      sdk_assert_equality_data(args[1], 0)
      let same = !sdk_contains_nan(args[0], 0) &&
        !sdk_contains_nan(args[1], 0) &&
        rt.equal_values(
          sdk_normalize_equality(args[0], 0),
          sdk_normalize_equality(args[1], 0),
        )
      @scheme.Boolean(if suffix == "equal" { same } else { !same })
    }
    "less-than"
    | "greater-than"
    | "less-than-or-equal"
    | "greater-than-or-equal"
    | "max"
    | "min"
    | "compare" => {
      let order = sdk_compare(args[0], args[1], 0)
      match suffix {
        "less-than" => @scheme.Boolean(order is @sdk.LT)
        "greater-than" => @scheme.Boolean(order is @sdk.GT)
        "less-than-or-equal" => @scheme.Boolean(!(order is @sdk.GT))
        "greater-than-or-equal" => @scheme.Boolean(!(order is @sdk.LT))
        "max" => if order is @sdk.GT { args[0] } else { args[1] }
        "min" => if order is @sdk.LT { args[0] } else { args[1] }
        _ => sdk_order_value(order)
      }
    }
    "not" => @scheme.Boolean(@basics.not_(sdk_bool(args[0])))
    "and" => @scheme.Boolean(@basics.and_(sdk_bool(args[0]), sdk_bool(args[1])))
    "or" => @scheme.Boolean(@basics.or_(sdk_bool(args[0]), sdk_bool(args[1])))
    "xor" => @scheme.Boolean(@basics.xor(sdk_bool(args[0]), sdk_bool(args[1])))
    "append" =>
      match (args[0], args[1]) {
        (@scheme.Text(_), @scheme.Text(_))
        | (@scheme.Text(_), @scheme.Tagged("sdk-text", _))
        | (@scheme.Tagged("sdk-text", _), @scheme.Text(_))
        | (@scheme.Tagged("sdk-text", _), @scheme.Tagged("sdk-text", _)) =>
          sdk_text_value(
            @basics.append_string(sdk_text(args[0]), sdk_text(args[1])),
          )
        _ =>
          @scheme.list(
            @sdk_list.to_array(
              @basics.append_list(
                @sdk_list.from_array(args[0].to_array()),
                @sdk_list.from_array(args[1].to_array()),
              ),
            ),
          )
      }
    "identity" => @basics.identity(args[0])
    "always" => @basics.always(args[0], args[1])
    "compose-left" | "compose-right" => {
      let first = if suffix == "compose-left" { args[1] } else { args[0] }
      let second = if suffix == "compose-left" { args[0] } else { args[1] }
      @scheme.NativeFunction(fn(runtime, values) raise {
        @scheme.arity(values, 1, name)
        let intermediate = runtime.call(first, values)
        runtime.call(second, [intermediate])
      })
    }
    "never" => raise @scheme.Invalid("Cannot construct a Morphir Never value")
    _ => raise @scheme.Unbound(name)
  }
}

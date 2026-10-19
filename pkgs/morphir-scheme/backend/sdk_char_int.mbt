///|
/// Pinned SDK declarations separate the numeric word; historical runtime
/// bindings and opaque transport tags retain their compact spelling.
fn sdk_int_binding(name : String) -> String {
  match name {
    "morphir/SDK:int#from-int-16" => "morphir/SDK:int#from-int16"
    "morphir/SDK:int#to-int-16" => "morphir/SDK:int#to-int16"
    "morphir/SDK:int#from-int-32" => "morphir/SDK:int#from-int32"
    "morphir/SDK:int#to-int-32" => "morphir/SDK:int#to-int32"
    "morphir/SDK:int#from-int-64" => "morphir/SDK:int#from-int64"
    "morphir/SDK:int#to-int-64" => "morphir/SDK:int#to-int64"
    _ => name
  }
}

///|
fn sdk_int_canonical_aliases() -> Array[(String, Int32)] {
  [
    ("morphir/SDK:int#from-int-16", 1),
    ("morphir/SDK:int#to-int-16", 1),
    ("morphir/SDK:int#from-int-32", 1),
    ("morphir/SDK:int#to-int-32", 1),
    ("morphir/SDK:int#from-int-64", 1),
    ("morphir/SDK:int#to-int-64", 1),
  ]
}

///|
fn numeric_int_registry() -> Array[(String, Int32)] {
  let rows = []
  for name in ["byte", "uint-16", "uint-32", "uint-64"] {
    rows.push(("morphir/SDK:int#from-" + name, 1))
    rows.push(("morphir/SDK:int#to-" + name, 1))
  }
  for
    name in [
      "from-float64-exact", "from-float64-truncated", "from-float64-floor", "from-float64-ceiling",
      "from-float64-rounded", "from-float32-exact", "from-float32-truncated", "from-float32-floor",
      "from-float32-ceiling", "from-float32-rounded", "to-float64-exact", "to-float64-rounded",
      "to-float32-exact", "to-float32-rounded",
    ] {
    rows.push(("morphir/SDK:int#" + name, 1))
  }
  rows
}

///|
fn numeric_int_arity(name : String) -> Int32? {
  numeric_int_registry().filter(row => row.0 == name).get(0).map(row => row.1)
}

///|
fn sdk_char_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise @scheme.SchemeError {
  let suffix = name.clamped_view(start="morphir/SDK:char#".length()).to_owned()
  if suffix == "from-code" {
    return sdk_character_value(@sdk_char.from_code(sdk_integer(args[0])))
  }
  let character = sdk_character(args[0])
  match suffix {
    "is-upper" => @scheme.Boolean(@sdk_char.is_upper(character))
    "is-lower" => @scheme.Boolean(@sdk_char.is_lower(character))
    "is-alpha" => @scheme.Boolean(@sdk_char.is_alpha(character))
    "is-alpha-num" => @scheme.Boolean(@sdk_char.is_alpha_num(character))
    "is-digit" => @scheme.Boolean(@sdk_char.is_digit(character))
    "is-oct-digit" => @scheme.Boolean(@sdk_char.is_oct_digit(character))
    "is-hex-digit" => @scheme.Boolean(@sdk_char.is_hex_digit(character))
    "to-upper" => sdk_character_value(@sdk_char.to_upper(character))
    "to-lower" => sdk_character_value(@sdk_char.to_lower(character))
    "to-locale-upper" =>
      sdk_character_value(@sdk_char.to_locale_upper(character))
    "to-locale-lower" =>
      sdk_character_value(@sdk_char.to_locale_lower(character))
    "to-code" => exact_integer(@sdk_char.to_code(character))
    _ => raise @scheme.Unbound(name)
  }
}

///|
fn sdk_width_value(width : String, value : @integer.Integer) -> @scheme.Value {
  @scheme.Tagged("morphir/SDK:int#" + width, [exact_integer(value)])
}

///|
fn sdk_width_input(
  width : String,
  value : @scheme.Value,
) -> @integer.Integer raise @scheme.SchemeError {
  match value {
    @scheme.Tagged(tag, [number]) if tag == "morphir/SDK:int#" + width => {
      let integer = sdk_integer(number)
      let fits = match width {
        "int8" => @sdk_int.to_int8(integer) is Some(_)
        "int16" => @sdk_int.to_int16(integer) is Some(_)
        "int32" => @sdk_int.to_int32(integer) is Some(_)
        "int64" => @sdk_int.to_int64(integer) is Some(_)
        "byte" => @sdk_int.to_byte(integer) is Some(_)
        "uint-16" => @sdk_int.to_uint16(integer) is Some(_)
        "uint-32" => @sdk_int.to_uint32(integer) is Some(_)
        "uint-64" => @sdk_int.to_uint64(integer) is Some(_)
        _ => false
      }
      if !fits {
        raise @scheme.Invalid("Morphir " + width + " is out of range")
      }
      integer
    }
    _ => raise @scheme.Invalid("Expected Morphir " + width)
  }
}

///|
fn sdk_int_dispatch(
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise @scheme.SchemeError {
  let suffix = name.clamped_view(start="morphir/SDK:int#".length()).to_owned()
  match suffix {
    "to-int8" =>
      sdk_maybe_value(
        match @sdk_int.to_int8(sdk_integer(args[0])) {
          Some(value) =>
            Some(sdk_width_value("int8", @sdk_int.from_int8(value)))
          None => None
        },
      )
    "to-int16" =>
      sdk_maybe_value(
        match @sdk_int.to_int16(sdk_integer(args[0])) {
          Some(value) =>
            Some(sdk_width_value("int16", @sdk_int.from_int16(value)))
          None => None
        },
      )
    "to-int32" =>
      sdk_maybe_value(
        match @sdk_int.to_int32(sdk_integer(args[0])) {
          Some(value) =>
            Some(sdk_width_value("int32", @sdk_int.from_int32(value)))
          None => None
        },
      )
    "to-int64" =>
      sdk_maybe_value(
        match @sdk_int.to_int64(sdk_integer(args[0])) {
          Some(value) =>
            Some(sdk_width_value("int64", @sdk_int.from_int64(value)))
          None => None
        },
      )
    "to-byte" =>
      sdk_maybe_value(
        @sdk_int.to_byte(sdk_integer(args[0])).map(value => {
          sdk_width_value("byte", @sdk_int.from_byte(value))
        }),
      )
    "to-uint-16" =>
      sdk_maybe_value(
        @sdk_int.to_uint16(sdk_integer(args[0])).map(value => {
          sdk_width_value("uint-16", @sdk_int.from_uint16(value))
        }),
      )
    "to-uint-32" =>
      sdk_maybe_value(
        @sdk_int.to_uint32(sdk_integer(args[0])).map(value => {
          sdk_width_value("uint-32", @sdk_int.from_uint32(value))
        }),
      )
    "to-uint-64" =>
      sdk_maybe_value(
        @sdk_int.to_uint64(sdk_integer(args[0])).map(value => {
          sdk_width_value("uint-64", @sdk_int.from_uint64(value))
        }),
      )
    "from-int8" => exact_integer(sdk_width_input("int8", args[0]))
    "from-int16" => exact_integer(sdk_width_input("int16", args[0]))
    "from-int32" => exact_integer(sdk_width_input("int32", args[0]))
    "from-int64" => exact_integer(sdk_width_input("int64", args[0]))
    "from-byte" => exact_integer(sdk_width_input("byte", args[0]))
    "from-uint-16" => exact_integer(sdk_width_input("uint-16", args[0]))
    "from-uint-32" => exact_integer(sdk_width_input("uint-32", args[0]))
    "from-uint-64" => exact_integer(sdk_width_input("uint-64", args[0]))
    "from-float64-exact" =>
      sdk_maybe_value(
        @sdk_int.from_float64_exact(sdk_float(args[0])).map(exact_integer),
      )
    "from-float64-truncated" =>
      sdk_maybe_value(
        @sdk_int.from_float64_truncated(sdk_float(args[0])).map(exact_integer),
      )
    "from-float64-floor" =>
      sdk_maybe_value(
        @sdk_int.from_float64_floor(sdk_float(args[0])).map(exact_integer),
      )
    "from-float64-ceiling" =>
      sdk_maybe_value(
        @sdk_int.from_float64_ceiling(sdk_float(args[0])).map(exact_integer),
      )
    "from-float64-rounded" =>
      sdk_maybe_value(
        @sdk_int.from_float64_rounded(sdk_float(args[0])).map(exact_integer),
      )
    "from-float32-exact" =>
      sdk_maybe_value(
        @sdk_int.from_float32_exact(sdk_float(args[0])).map(exact_integer),
      )
    "from-float32-truncated" =>
      sdk_maybe_value(
        @sdk_int.from_float32_truncated(sdk_float(args[0])).map(exact_integer),
      )
    "from-float32-floor" =>
      sdk_maybe_value(
        @sdk_int.from_float32_floor(sdk_float(args[0])).map(exact_integer),
      )
    "from-float32-ceiling" =>
      sdk_maybe_value(
        @sdk_int.from_float32_ceiling(sdk_float(args[0])).map(exact_integer),
      )
    "from-float32-rounded" =>
      sdk_maybe_value(
        @sdk_int.from_float32_rounded(sdk_float(args[0])).map(exact_integer),
      )
    "to-float64-exact" =>
      sdk_maybe_value(
        @sdk_int.to_float64_exact(sdk_integer(args[0])).map(n => {
          @scheme.Value::Number(@scheme.Number::Real(n))
        }),
      )
    "to-float64-rounded" =>
      @scheme.Value::Number(
        @scheme.Number::Real(@sdk_int.to_float64_rounded(sdk_integer(args[0]))),
      )
    "to-float32-exact" =>
      sdk_maybe_value(
        @sdk_int.to_float32_exact(sdk_integer(args[0])).map(n => {
          @scheme.Value::Number(@scheme.Number::Real(n))
        }),
      )
    "to-float32-rounded" =>
      @scheme.Value::Number(
        @scheme.Number::Real(@sdk_int.to_float32_rounded(sdk_integer(args[0]))),
      )
    _ => raise @scheme.Unbound(name)
  }
}

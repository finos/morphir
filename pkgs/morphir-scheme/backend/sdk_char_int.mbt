///|
/// Pinned SDK declarations separate the numeric word; historical runtime
/// bindings and opaque transport tags retain their compact spelling.
fn sdk_int_binding(name : String) -> String {
  match name {
    "morphir/SDK:int#from-int-32" => "morphir/SDK:int#from-int32"
    "morphir/SDK:int#to-int-32" => "morphir/SDK:int#to-int32"
    _ => name
  }
}

///|
fn sdk_int_canonical_aliases() -> Array[(String, Int32)] {
  [("morphir/SDK:int#from-int-32", 1), ("morphir/SDK:int#to-int-32", 1)]
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
    "from-int8" => exact_integer(sdk_width_input("int8", args[0]))
    "from-int16" => exact_integer(sdk_width_input("int16", args[0]))
    "from-int32" => exact_integer(sdk_width_input("int32", args[0]))
    "from-int64" => exact_integer(sdk_width_input("int64", args[0]))
    _ => raise @scheme.Unbound(name)
  }
}

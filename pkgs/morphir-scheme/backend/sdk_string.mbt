///|
fn sdk_text_list(
  value : @scheme.Value,
) -> @sdk_list.List[@sdk.Text] raise @scheme.SchemeError {
  @sdk_list.from_array(value.to_array().map(sdk_text))
}

///|
fn sdk_text_list_value(value : @sdk_list.List[@sdk.Text]) -> @scheme.Value {
  @scheme.list(@sdk_list.to_array(value).map(sdk_text_value))
}

///|
fn sdk_character_list(
  value : @scheme.Value,
) -> @sdk_list.List[@sdk.Character] raise @scheme.SchemeError {
  @sdk_list.from_array(value.to_array().map(sdk_character))
}

///|
fn sdk_character_list_value(
  value : @sdk_list.List[@sdk.Character],
) -> @scheme.Value {
  @scheme.list(@sdk_list.to_array(value).map(sdk_character_value))
}

///|
fn sdk_indexes_value(value : @sdk_list.List[Int32]) -> @scheme.Value {
  @scheme.list(
    @sdk_list.to_array(value).map(index => {
      exact_integer(@integer.from_int(index))
    }),
  )
}

///|
fn sdk_string_dispatch(
  runtime : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name
    .clamped_view(start="morphir/SDK:string#".length())
    .to_owned()
  match suffix {
    "is-empty" => @scheme.Boolean(@sdk_string.is_empty(sdk_text(args[0])))
    "length" =>
      exact_integer(@integer.from_int(@sdk_string.length(sdk_text(args[0]))))
    "reverse" => sdk_text_value(@sdk_string.reverse(sdk_text(args[0])))
    "repeat" =>
      sdk_text_value(@sdk_string.repeat(sdk_int(args[0]), sdk_text(args[1])))
    "replace" =>
      sdk_text_value(
        @sdk_string.replace(
          sdk_text(args[0]),
          sdk_text(args[1]),
          sdk_text(args[2]),
        ),
      )
    "append" =>
      sdk_text_value(@sdk_string.append(sdk_text(args[0]), sdk_text(args[1])))
    "concat" => sdk_text_value(@sdk_string.concat(sdk_text_list(args[0])))
    "split" =>
      sdk_text_list_value(
        @sdk_string.split(sdk_text(args[0]), sdk_text(args[1])),
      )
    "join" =>
      sdk_text_value(
        @sdk_string.join(sdk_text(args[0]), sdk_text_list(args[1])),
      )
    "words" => sdk_text_list_value(@sdk_string.words(sdk_text(args[0])))
    "lines" => sdk_text_list_value(@sdk_string.lines(sdk_text(args[0])))
    "slice" =>
      sdk_text_value(
        @sdk_string.slice(sdk_int(args[0]), sdk_int(args[1]), sdk_text(args[2])),
      )
    "left" =>
      sdk_text_value(@sdk_string.left(sdk_int(args[0]), sdk_text(args[1])))
    "right" =>
      sdk_text_value(@sdk_string.right(sdk_int(args[0]), sdk_text(args[1])))
    "drop-left" =>
      sdk_text_value(@sdk_string.drop_left(sdk_int(args[0]), sdk_text(args[1])))
    "drop-right" =>
      sdk_text_value(
        @sdk_string.drop_right(sdk_int(args[0]), sdk_text(args[1])),
      )
    "contains" =>
      @scheme.Boolean(
        @sdk_string.contains(sdk_text(args[0]), sdk_text(args[1])),
      )
    "starts-with" =>
      @scheme.Boolean(
        @sdk_string.starts_with(sdk_text(args[0]), sdk_text(args[1])),
      )
    "ends-with" =>
      @scheme.Boolean(
        @sdk_string.ends_with(sdk_text(args[0]), sdk_text(args[1])),
      )
    "indexes" =>
      sdk_indexes_value(
        @sdk_string.indexes(sdk_text(args[0]), sdk_text(args[1])),
      )
    "indices" =>
      sdk_indexes_value(
        @sdk_string.indices(sdk_text(args[0]), sdk_text(args[1])),
      )
    "to-int" =>
      sdk_maybe_value(
        match @sdk_string.to_int(sdk_text(args[0])) {
          Some(value) => Some(exact_integer(value))
          None => None
        },
      )
    "from-int" => sdk_text_value(@sdk_string.from_int(sdk_integer(args[0])))
    "to-float" =>
      sdk_maybe_value(
        match @sdk_string.to_float(sdk_text(args[0])) {
          Some(value) => Some(@scheme.Number(@scheme.Number::Real(value)))
          None => None
        },
      )
    "from-float" => sdk_text_value(@sdk_string.from_float(sdk_float(args[0])))
    "from-char" => sdk_text_value(@sdk_string.from_char(sdk_character(args[0])))
    "cons" =>
      sdk_text_value(
        @sdk_string.cons(sdk_character(args[0]), sdk_text(args[1])),
      )
    "uncons" =>
      sdk_maybe_value(
        match @sdk_string.uncons(sdk_text(args[0])) {
          Some((character, rest)) =>
            Some(
              @scheme.Vector([
                sdk_character_value(character),
                sdk_text_value(rest),
              ]),
            )
          None => None
        },
      )
    "to-list" =>
      sdk_character_list_value(@sdk_string.to_list(sdk_text(args[0])))
    "from-list" =>
      sdk_text_value(@sdk_string.from_list(sdk_character_list(args[0])))
    "to-upper" => sdk_text_value(@sdk_string.to_upper(sdk_text(args[0])))
    "to-lower" => sdk_text_value(@sdk_string.to_lower(sdk_text(args[0])))
    "pad" =>
      sdk_text_value(
        @sdk_string.pad(
          sdk_int(args[0]),
          sdk_character(args[1]),
          sdk_text(args[2]),
        ),
      )
    "pad-left" =>
      sdk_text_value(
        @sdk_string.pad_left(
          sdk_int(args[0]),
          sdk_character(args[1]),
          sdk_text(args[2]),
        ),
      )
    "pad-right" =>
      sdk_text_value(
        @sdk_string.pad_right(
          sdk_int(args[0]),
          sdk_character(args[1]),
          sdk_text(args[2]),
        ),
      )
    "trim" => sdk_text_value(@sdk_string.trim(sdk_text(args[0])))
    "trim-left" => sdk_text_value(@sdk_string.trim_left(sdk_text(args[0])))
    "trim-right" => sdk_text_value(@sdk_string.trim_right(sdk_text(args[0])))
    "map" =>
      sdk_text_value(
        @sdk_string.map(
          fn(character) raise {
            sdk_character(
              sdk_apply(runtime, args[0], [sdk_character_value(character)]),
            )
          },
          sdk_text(args[1]),
        ),
      )
    "filter" =>
      sdk_text_value(
        @sdk_string.filter(
          fn(character) raise {
            sdk_bool(
              sdk_apply(runtime, args[0], [sdk_character_value(character)]),
            )
          },
          sdk_text(args[1]),
        ),
      )
    "foldl" =>
      @sdk_string.foldl(
        fn(character, acc) raise {
          sdk_apply(runtime, args[0], [sdk_character_value(character), acc])
        },
        args[1],
        sdk_text(args[2]),
      )
    "foldr" =>
      @sdk_string.foldr(
        fn(character, acc) raise {
          sdk_apply(runtime, args[0], [sdk_character_value(character), acc])
        },
        args[1],
        sdk_text(args[2]),
      )
    "any" =>
      @scheme.Boolean(
        @sdk_string.any(
          fn(character) raise {
            sdk_bool(
              sdk_apply(runtime, args[0], [sdk_character_value(character)]),
            )
          },
          sdk_text(args[1]),
        ),
      )
    "all" =>
      @scheme.Boolean(
        @sdk_string.all(
          fn(character) raise {
            sdk_bool(
              sdk_apply(runtime, args[0], [sdk_character_value(character)]),
            )
          },
          sdk_text(args[1]),
        ),
      )
    _ => raise @scheme.Unbound(name)
  }
}

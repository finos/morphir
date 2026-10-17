///|
fn sdk_string_arity(binding : String, context : String) -> Int32 raise {
  match binding {
    "replace"
    | "slice"
    | "pad"
    | "pad-left"
    | "pad-right"
    | "foldl"
    | "foldr" => 3
    "repeat"
    | "append"
    | "split"
    | "join"
    | "left"
    | "right"
    | "drop-left"
    | "drop-right"
    | "contains"
    | "starts-with"
    | "ends-with"
    | "indexes"
    | "indices"
    | "cons"
    | "map"
    | "filter"
    | "any"
    | "all" => 2
    "is-empty"
    | "length"
    | "reverse"
    | "concat"
    | "words"
    | "lines"
    | "to-int"
    | "from-int"
    | "to-float"
    | "from-float"
    | "from-char"
    | "uncons"
    | "to-list"
    | "from-list"
    | "to-upper"
    | "to-lower"
    | "trim"
    | "trim-left"
    | "trim-right" => 1
    _ =>
      raise Invalid(
        "moonbit.unsupported_sdk",
        context,
        "morphir/SDK:string#" + binding,
      )
  }
}

///|
/// Adapt the SDK's machine counts and uncurried folds to Morphir's concrete types.
fn sdk_string_call(
  ctx : Lowering,
  binding : String,
  inputs : Array[Lowered],
  result : Lowered,
  context : String,
) -> String raise {
  let canonical = "morphir/SDK:string#" + binding
  let text = Atom(Scalar::Text)
  let character = Atom(Scalar::Character)
  let int = Atom(Scalar::Integer)
  let float = Atom(Scalar::Float)
  let bool = Atom(Scalar::Boolean)
  let arguments = Array::makei(inputs.length(), i => "a" + i.to_string())
  fn require(signature : Array[Lowered], output : Lowered) -> Unit raise {
    if inputs != signature || result != output {
      raise Invalid("moonbit.sdk_signature", context, canonical)
    }
  }
  fn count(index : Int32) -> Unit {
    ctx.imports["integer"] = true
    arguments[index] = "(match @integer.to_int(a" +
      index.to_string() +
      ") { Some(n) => n; None => raise @sdk.OutOfRange(" +
      quote(canonical) +
      ") })"
  }
  match binding {
    "append" => require([text, text], text)
    "replace" => require([text, text, text], text)
    "is-empty" => require([text], bool)
    "length" => require([text], int)
    "reverse" | "to-upper" | "to-lower" | "trim" | "trim-left" | "trim-right" =>
      require([text], text)
    "concat" => require([Sequence(text)], text)
    "split" => require([text, text], Sequence(text))
    "join" => require([text, Sequence(text)], text)
    "words" | "lines" => require([text], Sequence(text))
    "repeat" | "left" | "right" | "drop-left" | "drop-right" => {
      require([int, text], text)
      count(0)
    }
    "slice" => {
      require([int, int, text], text)
      count(0)
      count(1)
    }
    "pad" | "pad-left" | "pad-right" => {
      require([int, character, text], text)
      count(0)
    }
    "contains" | "starts-with" | "ends-with" => require([text, text], bool)
    "indexes" | "indices" => require([text, text], Sequence(int))
    "to-int" => require([text], Optional(int))
    "from-int" => require([int], text)
    "to-float" => require([text], Optional(float))
    "from-float" => require([float], text)
    "from-char" => require([character], text)
    "cons" => require([character, text], text)
    "uncons" => require([text], Optional(Product([character, text])))
    "to-list" => require([text], Sequence(character))
    "from-list" => require([Sequence(character)], text)
    "map" => require([Arrow(character, character), text], text)
    "filter" => require([Arrow(character, bool), text], text)
    "any" | "all" => require([Arrow(character, bool), text], bool)
    "foldl" | "foldr" => {
      require([Arrow(character, Arrow(result, result)), result, text], result)
      arguments[0] = "fn(value, state) raise @sdk.SdkError { a0(value)(state) }"
    }
    _ => raise Invalid("moonbit.unsupported_sdk", context, canonical)
  }
  ctx.imports["string"] = true
  let function = binding
    .split("-")
    .map(StringView::to_owned)
    .collect()
    .join("_")
  let call = "@string." + function + "(" + arguments.join(", ") + ")"
  match binding {
    "length" => {
      ctx.imports["integer"] = true
      "@integer.from_int(" + call + ")"
    }
    "indexes" | "indices" => {
      ctx.imports["integer"] = true
      ctx.imports["list"] = true
      "@list.map(@integer.from_int, " + call + ")"
    }
    _ => call
  }
}

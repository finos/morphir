///|
fn sdk_constructor(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  match (name.to_canonical(), expected) {
    ("morphir/SDK:maybe#nothing", Optional(_)) => "None"
    ("morphir/SDK:maybe#just", Arrow(a, Optional(b))) if a == b =>
      curry_source(ctx, [("value", a)], Optional(b), "Some(value)")
    ("morphir/SDK:result#ok", Arrow(a, Outcome(b, e))) if a == b =>
      curry_source(ctx, [("value", a)], Outcome(b, e), "Ok(value)")
    ("morphir/SDK:result#err", Arrow(e, Outcome(a, b))) if e == b =>
      curry_source(ctx, [("value", e)], Outcome(a, b), "Err(value)")
    _ =>
      raise Invalid(
        "moonbit.unresolved_constructor",
        context,
        name.to_canonical(),
      )
  }
}

///|
fn sdk_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  let binding_name = name.local_name.to_canonical()
  let arity = match (name.module_name.to_canonical(), binding_name) {
    ("decimal", "zero" | "one" | "minus-one") => 0
    ("list", "foldl" | "foldr") => 3
    ("string", _) => sdk_string_arity(binding_name, context)
    (
      "basics",
      "add"
      | "subtract"
      | "multiply"
      | "integer-divide"
      | "power"
      | "mod-by"
      | "remainder-by"
      | "divide"
      | "and"
      | "or"
      | "xor"
      | "always"
      | "equal"
      | "not-equal"
      | "less-than"
      | "greater-than"
      | "less-than-or-equal"
      | "greater-than-or-equal",
    )
    | (
      "decimal",
      "add"
      | "sub"
      | "mul"
      | "div"
      | "eq"
      | "neq"
      | "gt"
      | "gte"
      | "lt"
      | "lte",
    )
    | ("list", "map" | "filter" | "append")
    | ("maybe", "map" | "with-default") => 2
    (
      "basics",
      "negate"
      | "abs"
      | "not"
      | "identity"
      | "to-float"
      | "round"
      | "floor"
      | "ceiling"
      | "truncate",
    )
    | ("decimal", "negate" | "abs" | "truncate" | "round" | "from-int")
    | ("list", "sum" | "product" | "length" | "reverse")
    | ("char", "to-upper")
    | (
      "int",
      "to-int32"
      | "from-int32"
      | "to-int-32"
      | "from-int-32"
      | "to-int-16"
      | "from-int-16"
      | "to-int-64"
      | "from-int-64"
      | "to-byte"
      | "from-byte"
      | "to-uint-16"
      | "from-uint-16"
      | "to-uint-32"
      | "from-uint-32"
      | "to-uint-64"
      | "from-uint-64"
      | "from-float64-exact"
      | "from-float64-truncated"
      | "from-float64-floor"
      | "from-float64-ceiling"
      | "from-float64-rounded",
    ) => 1
    (
      "int",
      "from-float32-exact"
      | "from-float32-truncated"
      | "from-float32-floor"
      | "from-float32-ceiling"
      | "from-float32-rounded"
      | "to-float64-exact"
      | "to-float64-rounded"
      | "to-float32-exact"
      | "to-float32-rounded",
    ) => 1
    _ => raise Invalid("moonbit.unsupported_sdk", context, name.to_canonical())
  }
  let inputs = []
  let mut result = expected
  for _ in 0..<arity {
    guard result is Arrow(a, b) else {
      raise Invalid("moonbit.sdk_signature", context, name.to_canonical())
    }
    inputs.push(a)
    result = b
  }
  let args = Array::makei(inputs.length(), i => ("a" + i.to_string(), inputs[i]))
  let canonical = name.to_canonical()
  let int = Atom(Scalar::Integer)
  let dec = Atom(Scalar::Decimal)
  let float = Atom(Scalar::Float)
  let float32 = Atom(Scalar::Float32)
  let bool = Atom(Scalar::Boolean)
  let mut call = ""
  let module_name = name.module_name.to_canonical()
  let binding = name.local_name.to_canonical()
  let native_binding = binding
    .split("-")
    .map(StringView::to_owned)
    .collect()
    .join("_")
  fn require(signature : Array[Lowered], output : Lowered) -> Unit raise {
    if inputs != signature || result != output {
      raise Invalid("moonbit.sdk_signature", context, canonical)
    }
  }
  fn native(module_name : String, function : String) -> String {
    ctx.imports[module_name] = true
    "@" +
    module_name +
    "." +
    function +
    "(" +
    args.map(p => p.0).join(", ") +
    ")"
  }
  match (module_name, binding) {
    ("string", _) =>
      call = sdk_string_call(ctx, binding, inputs, result, context)
    ("int", "to-int32" | "to-int-32") => {
      require([int], Optional(Atom(Scalar::SignedInt32)))
      call = native("int", "to_int32")
    }
    ("int", "from-int32" | "from-int-32") => {
      require([Atom(Scalar::SignedInt32)], int)
      call = native("int", "from_int32")
    }
    (
      "int",
      "from-float64-exact"
      | "from-float64-truncated"
      | "from-float64-floor"
      | "from-float64-ceiling"
      | "from-float64-rounded",
    ) => {
      require([float], Optional(int))
      call = native("int", native_binding)
    }
    (
      "int",
      "from-float32-exact"
      | "from-float32-truncated"
      | "from-float32-floor"
      | "from-float32-ceiling"
      | "from-float32-rounded",
    ) => {
      require([float32], Optional(int))
      call = native("int", native_binding)
    }
    ("int", "to-float64-exact") => {
      require([int], Optional(float))
      call = native("int", native_binding)
    }
    ("int", "to-float32-exact") => {
      require([int], Optional(float32))
      call = native("int", native_binding)
    }
    ("int", "to-float64-rounded") => {
      require([int], float)
      call = native("int", native_binding)
    }
    ("int", "to-float32-rounded") => {
      require([int], float32)
      call = native("int", native_binding)
    }
    (
      "int",
      "to-int-16"
      | "from-int-16"
      | "to-int-64"
      | "from-int-64"
      | "to-byte"
      | "from-byte"
      | "to-uint-16"
      | "from-uint-16"
      | "to-uint-32"
      | "from-uint-32"
      | "to-uint-64"
      | "from-uint-64",
    ) => {
      let to = binding.has_prefix("to-")
      let width = binding[if to { 3 } else { 5 }:].to_owned()
      let bounded = Atom(Scalar::BoundedInteger(width))
      if to {
        require([int], Optional(bounded))
      } else {
        require([bounded], int)
      }
      call = native(
        "int",
        (if to { "to_" } else { "from_" }) + width.replace(old="-", new=""),
      )
    }
    ("basics", "add" | "subtract" | "multiply") => {
      let t = if inputs == [int, int] { int } else { float }
      require([t, t], t)
      call = native(
        "basics",
        binding + (if t == int { "_int" } else { "_float" }),
      )
    }
    ("basics", "power") => {
      let t = if inputs == [int, int] { int } else { float }
      require([t, t], t)
      call = native(
        "basics",
        if t == int {
          "power_int"
        } else {
          "power_float"
        },
      )
    }
    ("basics", "integer-divide" | "mod-by" | "remainder-by") => {
      require([int, int], int)
      call = native(
        "basics",
        match binding {
          "integer-divide" => "integer_divide"
          "mod-by" => "mod_by"
          _ => "remainder_by"
        },
      )
    }
    ("basics", "divide") => {
      require([float, float], float)
      call = native("basics", "divide")
    }
    ("basics", "negate" | "abs") => {
      let t = if inputs == [int] { int } else { float }
      require([t], t)
      call = native(
        "basics",
        binding + (if t == int { "_int" } else { "_float" }),
      )
    }
    ("basics", "not") => {
      require([bool], bool)
      call = "!a0"
    }
    ("basics", "and" | "or" | "xor") => {
      require([bool, bool], bool)
      call = native(
        "basics",
        if binding == "xor" {
          "xor"
        } else {
          binding + "_"
        },
      )
    }
    ("basics", "identity") if inputs.length() == 1 && inputs[0] == result =>
      call = "a0"
    ("basics", "always") if inputs.length() == 2 && inputs[0] == result =>
      call = "a0"
    ("basics", "to-float") => {
      require([int], float)
      call = native("basics", "to_float")
    }
    ("basics", "round" | "floor" | "ceiling" | "truncate") => {
      require([float], int)
      call = native("basics", binding)
    }
    (
      "basics",
      "equal"
      | "not-equal"
      | "less-than"
      | "greater-than"
      | "less-than-or-equal"
      | "greater-than-or-equal",
    ) if inputs.length() == 2 && inputs[0] == inputs[1] => {
      let t = inputs[0]
      if ![int, float, bool, Atom(Scalar::Text), Atom(Scalar::Character)].contains(
          t,
        ) {
        raise Invalid(
          "moonbit.unsupported_sdk", context, "Comparison requires an audited scalar instance",
        )
      }
      require([t, t], bool)
      let equality = ["equal", "not-equal"].contains(binding)
      if !equality && t == bool {
        raise Invalid(
          "moonbit.sdk_signature", context, "Boolean is not an ordered SDK scalar",
        )
      }
      if !equality && (t == Atom(Scalar::Text) || t == Atom(Scalar::Character)) {
        let left = if t == Atom(Scalar::Character) {
          "a0.to_text()"
        } else {
          "a0"
        }
        let right = if t == Atom(Scalar::Character) {
          "a1.to_text()"
        } else {
          "a1"
        }
        call = "(@sdk.text_order(" +
          left +
          ", " +
          right +
          ") " +
          (match binding {
            "less-than" => "== @sdk.LT"
            "greater-than" => "== @sdk.GT"
            "less-than-or-equal" => "!= @sdk.GT"
            _ => "!= @sdk.LT"
          }) +
          ")"
      } else if !equality && t == float {
        call = "if a0.is_nan() || a1.is_nan() { false } else { a0 " +
          (match binding {
            "less-than" => "<"
            "greater-than" => ">"
            "less-than-or-equal" => "<="
            _ => ">="
          }) +
          " a1 }"
      } else {
        call = native(
          "basics",
          binding.split("-").map(StringView::to_owned).collect().join("_"),
        )
      }
    }
    ("char", "to-upper") => {
      require([Atom(Scalar::Character)], Atom(Scalar::Character))
      call = native("char", "to_upper")
    }
    ("decimal", "add" | "sub" | "mul") => {
      require([dec, dec], dec)
      call = native("decimal", binding)
    }
    ("decimal", "div") => {
      require([dec, dec], Optional(dec))
      call = native("decimal", "div")
    }
    ("decimal", "negate" | "abs" | "truncate" | "round") => {
      require([dec], dec)
      call = native("decimal", binding)
    }
    ("decimal", "eq" | "neq" | "gt" | "gte" | "lt" | "lte") => {
      require([dec, dec], bool)
      call = native("decimal", binding)
    }
    ("decimal", "from-int") => {
      require([int], dec)
      call = native("decimal", "from_int")
    }
    ("decimal", "zero" | "one" | "minus-one") => {
      require([], dec)
      call = native(
        "decimal",
        binding.split("-").map(StringView::to_owned).collect().join("_"),
      )
    }
    ("list", "map") => {
      guard inputs is [Arrow(a, b), Sequence(c)] &&
        result is Sequence(d) &&
        a == c &&
        b == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("list", "map")
    }
    ("list", "filter") => {
      guard inputs is [Arrow(a, b), Sequence(c)] &&
        result is Sequence(d) &&
        a == c &&
        b == bool &&
        c == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("list", "filter")
    }
    ("list", "sum" | "product") => {
      require([Sequence(int)], int)
      call = native("list", binding)
    }
    ("list", "length") if inputs.length() == 1 && inputs[0] is Sequence(_) => {
      require(inputs, int)
      ctx.imports["integer"] = true
      call = "@integer.from_int(" + native("list", "length") + ")"
    }
    ("list", "reverse") if inputs.length() == 1 &&
      inputs[0] is Sequence(_) &&
      result == inputs[0] => call = native("list", "reverse")
    ("list", "append") if inputs.length() == 2 &&
      inputs[0] is Sequence(_) &&
      inputs[0] == inputs[1] &&
      result == inputs[0] => call = native("list", "append")
    ("list", "foldl" | "foldr") => {
      guard inputs is [Arrow(a, Arrow(b, c)), d, Sequence(e)] &&
        a == e &&
        b == c &&
        c == d &&
        result == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      ctx.imports["list"] = true
      call = "@list." +
        binding +
        "(fn(value, state) raise @sdk.SdkError { a0(value)(state) }, a1, a2)"
    }
    ("maybe", "with-default") => {
      guard inputs is [a, Optional(b)] && a == b && result == a else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("maybe", "with_default")
    }
    ("maybe", "map") => {
      guard inputs is [Arrow(a, b), Optional(c)] &&
        result is Optional(d) &&
        a == c &&
        b == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("maybe", "map")
    }
    _ => raise Invalid("moonbit.unsupported_sdk", context, canonical)
  }
  curry_source(ctx, args, result, call)
}

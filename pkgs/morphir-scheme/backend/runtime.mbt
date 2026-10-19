///|
fn literal_value(literal : @ir.PatternLiteral) -> @scheme.Value raise {
  match literal {
    BoolLiteral(b) => @scheme.Boolean(b)
    CharLiteral(c) => @scheme.Character(c)
    StringLiteral(s) => @scheme.Text(s)
    IntegerLiteral(s) => @scheme.integer(s)
    FloatLiteral(n) => @scheme.Number(@scheme.Number::Real(n))
    DecimalLiteral(s) => @scheme.Tagged("decimal", [@scheme.Text(s)])
  }
}

///|
fn matches(
  runtime : @scheme.Runtime,
  pattern : @ir.Pattern,
  value : @scheme.Value,
  bindings : Map[String, @scheme.Value],
  depth : Int32,
) -> Bool raise {
  if depth > 256 {
    raise @scheme.Limit("Pattern depth")
  }
  match pattern {
    WildcardPattern(_) => true
    AsPattern(_, pattern, name) => {
      if !matches(runtime, pattern, value, bindings, depth + 1) {
        return false
      }
      let key = name.to_canonical()
      if bindings.contains(key) {
        raise @scheme.Invalid("Duplicate pattern binding")
      }
      bindings[key] = value
      true
    }
    TuplePattern(_, patterns) =>
      match value {
        Vector(items) =>
          match_items(runtime, patterns, items, bindings, depth + 1)
        _ => false
      }
    ConstructorPattern(_, name, patterns) =>
      match value {
        Tagged(tag, items) if tag == name.to_canonical() =>
          match_items(runtime, patterns, items, bindings, depth + 1)
        _ => false
      }
    EmptyListPattern(_) => value is @scheme.Nil
    HeadTailPattern(_, head, tail) =>
      match value {
        Pair(a, b) =>
          matches(runtime, head, a, bindings, depth + 1) &&
          matches(runtime, tail, b, bindings, depth + 1)
        _ => false
      }
    LiteralPattern(_, literal) =>
      runtime.equal_values(value, literal_value(literal))
    UnitPattern(_) => value is @scheme.Unit
  }
}

///|
fn match_items(
  runtime : @scheme.Runtime,
  patterns : Array[@ir.Pattern],
  values : Array[@scheme.Value],
  bindings : Map[String, @scheme.Value],
  depth : Int32,
) -> Bool raise {
  if patterns.length() != values.length() {
    return false
  }
  for i = 0; i < patterns.length(); i = i + 1 {
    if !matches(runtime, patterns[i], values[i], bindings, depth) {
      return false
    }
  }
  true
}

///|
fn register_constructor(
  runtime : @scheme.Runtime,
  name : String,
  arity : Int32,
) -> Unit raise {
  if arity < 0 || arity > 256 {
    raise @scheme.Invalid("Invalid constructor arity")
  }
  let parameters = []
  for i = 0; i < arity; i = i + 1 {
    parameters.push("%constructor-arg-" + i.to_string())
  }
  let mut body = "(%morphir-tag " +
    text(name) +
    (if parameters.is_empty() { "" } else { " " + parameters.join(" ") }) +
    ")"
  for i = arity - 1; i >= 0; i = i - 1 {
    body = "(lambda (" + parameters[i] + ") " + body + ")"
  }
  let value = runtime.eval(body)
  runtime.set_global("constructor:" + name, value)
  // Custom constructors have a distinct namespace from value references.
  if name.has_prefix("morphir/SDK:") {
    runtime.define_native("r:" + name, fn(_runtime, args) raise {
      @scheme.arity(args, 0, name)
      value
    })
  }
}

///|
/// Install the runtime contract used by emitted Scheme. No file or network capabilities.
pub fn install(
  runtime : @scheme.Runtime,
  accelerators~ : Bool = true,
  model_errors~ : Bool = false,
) -> Unit raise {
  runtime.define_native("%morphir-unsupported-reached", fn(_rt, args) raise {
    @scheme.arity(args, 0, "unsupported operation")
    raise @scheme.Stage("evaluate", "execution.unsupported_reached")
  })
  runtime.define_native("%morphir-check-native", fn(rt, args) raise {
    @scheme.arity(args, 2, "native binding arity")
    let expected = match args[1] {
      Number(Integer(n)) if n.compare_int(0) >= 0 &&
        n.compare_int(2147483647) <= 0 => n.to_int()
      _ => raise @scheme.Invalid("Expected bounded native arity")
    }
    native_arity(rt, args[0].as_text(), expected)
    @scheme.Unit
  })
  runtime.define_native("%morphir-tag", fn(_rt, args) raise {
    if args.is_empty() {
      raise @scheme.Invalid("Tag requires a name")
    }
    @scheme.Tagged(args[0].as_text(), args[1:].to_owned())
  })
  runtime.define_native("%morphir-match", fn(rt, args) raise {
    @scheme.arity(args, 2, "pattern match")
    let pattern = @ir_json.read_pattern(@wire.parse(args[0].as_text()))
    let bindings = Map([])
    if matches(rt, pattern, args[1], bindings, 0) {
      @scheme.Record(bindings)
    } else {
      @scheme.Boolean(false)
    }
  })
  runtime.define_native("%morphir-boolean", fn(_rt, args) raise {
    @scheme.arity(args, 1, "boolean condition")
    match args[0] {
      Boolean(_) => args[0]
      _ => raise @scheme.Invalid("Morphir condition must be boolean")
    }
  })
  runtime.define_native("%morphir-update", fn(_rt, args) raise {
    @scheme.arity(args, 3, "record update")
    match args[0] {
      Record(fields) => {
        let key = args[1].as_text()
        if !fields.contains(key) {
          raise @scheme.Invalid("Update requires an existing record field")
        }
        let copy = Map::from_array(fields.iter().collect())
        copy[key] = args[2]
        @scheme.Record(copy)
      }
      _ => raise @scheme.Invalid("Expected record")
    }
  })
  runtime.define_native("%morphir-external", fn(rt, args) raise {
    if args.is_empty() {
      raise @scheme.Invalid("External call requires a registered name")
    }
    rt.call(rt.lookup("external:" + args[0].as_text()), args[1:].to_owned())
  })
  runtime.define_native("%morphir-has-native", fn(rt, args) raise {
    @scheme.arity(args, 1, "native binding lookup")
    @scheme.Boolean(rt.has_native(args[0].as_text()))
  })
  runtime.define_native("%morphir-require-native", fn(_rt, args) raise {
    @scheme.arity(args, 1, "required native binding")
    raise @scheme.Unbound(args[0].as_text())
  })
  runtime.define_native("%morphir-call-native", fn(rt, args) raise {
    if args.is_empty() {
      raise @scheme.Invalid("Native call requires a binding name")
    }
    rt.call(rt.lookup(args[0].as_text()), args[1:].to_owned())
  })
  runtime.define_native("%morphir-constructor", fn(rt, args) raise {
    @scheme.arity(args, 1, "constructor")
    rt.lookup("constructor:" + args[0].as_text())
  })
  runtime.define_native("%morphir-register-constructor", fn(rt, args) raise {
    @scheme.arity(args, 2, "register constructor")
    let arity = match args[1] {
      Number(Integer(n)) if n.compare_int(0) >= 0 && n.compare_int(256) <= 0 =>
        n.to_int()
      _ => raise @scheme.Invalid("Expected bounded constructor arity")
    }
    register_constructor(rt, args[0].as_text(), arity)
    @scheme.Unit
  })
  install_sdk(runtime, accelerators, model_errors)
  for
    (fq, count) in sdk_registry() +
    source_string_registry() +
    source_int32_registry() +
    sdk_int_canonical_aliases() {
    let parameters : Array[String] = []
    for i = 0; i < count; i = i + 1 {
      parameters.push("x" + i.to_string())
    }
    let args = if parameters.is_empty() {
      ""
    } else {
      " " + parameters.join(" ")
    }
    let body = "(%morphir-sdk \"" + fq + "\"" + args + ")"
    let mut closure = body
    for i = parameters.length() - 1; i >= 0; i = i - 1 {
      closure = "(lambda (" + parameters[i] + ") " + closure + ")"
    }
    ignore(
      runtime.eval(
        "(define " +
        @scheme.symbol_text("r:" + fq) +
        " (lambda () " +
        closure +
        "))",
      ),
    )
  }
  register_constructor(runtime, "morphir/SDK:maybe#just", 1)
  register_constructor(runtime, "morphir/SDK:maybe#nothing", 0)
  register_constructor(runtime, "morphir/SDK:result#ok", 1)
  register_constructor(runtime, "morphir/SDK:result#err", 1)
}

///|
pub fn evaluate(
  value : @ir.Value,
  limits~ : @scheme.Limits = @scheme.Limits::default(),
) -> @scheme.Value raise {
  let runtime = @scheme.Runtime::new(limits~)
  install(runtime)
  evaluate_in(runtime, value)
}

///|
pub fn run_file(
  file : @ir.IRFile,
  entry : @ir.FQName,
  arguments : Array[@scheme.Value],
  limits~ : @scheme.Limits = @scheme.Limits::default(),
) -> @scheme.Value raise {
  let runtime = @scheme.Runtime::new(limits~)
  install(runtime)
  run_file_in(runtime, file, entry, arguments)
}

///|
/// Bind a top-level NativeBody by qualified name. Arguments arrive uncurried.
pub fn register_native(
  runtime : @scheme.Runtime,
  name : @ir.FQName,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  let binding = "external:" + name.to_canonical()
  if runtime.has_native(binding) {
    raise @scheme.Invalid("Duplicate native binding: " + binding)
  }
  runtime.define_native(binding, procedure)
}

///|
pub fn replace_native(
  runtime : @scheme.Runtime,
  name : @ir.FQName,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  let binding = "external:" + name.to_canonical()
  if !runtime.has_native(binding) {
    raise @scheme.Invalid("No native binding to replace: " + binding)
  }
  runtime.define_native(binding, procedure)
}

///|
pub fn register_external(
  runtime : @scheme.Runtime,
  external_name : String,
  arity : Int32,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  runtime.register_native_binding("external:" + external_name, arity, procedure)
}

///|
pub fn replace_external(
  runtime : @scheme.Runtime,
  external_name : String,
  arity : Int32,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  runtime.replace_native_binding("external:" + external_name, arity, procedure)
}

///|
/// Explicit acceleration preserves the portable ExpressionBody fallback.
pub fn register_accelerator(
  runtime : @scheme.Runtime,
  name : @ir.FQName,
  arity : Int32,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  runtime.register_native_binding(
    "accelerator:" + name.to_canonical(),
    arity,
    procedure,
  )
}

///|
pub fn replace_accelerator(
  runtime : @scheme.Runtime,
  name : @ir.FQName,
  arity : Int32,
  procedure : (@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise,
) -> Unit raise @scheme.SchemeError {
  runtime.replace_native_binding(
    "accelerator:" + name.to_canonical(),
    arity,
    procedure,
  )
}

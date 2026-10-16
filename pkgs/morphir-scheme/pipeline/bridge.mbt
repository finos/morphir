///|
fn json_value(value : Json) -> @scheme.Value raise {
  match value {
    Null => @scheme.Unit
    True => @scheme.Boolean(true)
    False => @scheme.Boolean(false)
    String(s) => @scheme.Text(s)
    Number(_, ..) =>
      match @scheme.parse_number(@wire.number_text(value)) {
        Some(n) => @scheme.Number(n)
        None => raise @scheme.Invalid("Invalid JSON number")
      }
    Array(items) => @scheme.list(items.map(json_value))
    Object(fields) => @scheme.Record(@wire.map_values(fields, json_value))
  }
}

///|
fn value_json(value : @scheme.Value, depth : Int32) -> Json raise {
  if depth > 256 {
    raise @scheme.Limit("JSON conversion depth")
  }
  match value {
    Unit => Json::null()
    Boolean(b) => b.to_json()
    Text(s) => Json::string(s)
    Number(Integer(n)) => @wire.number(n.to_string())
    Number(Real(n)) => @wire.write_float(n)
    Nil | Pair(_, _) =>
      Json::array(value.to_array().map(item => value_json(item, depth + 1)))
    Vector(items) => Json::array(items.map(item => value_json(item, depth + 1)))
    Record(fields) =>
      Json::object(
        @wire.map_values(fields, fn(item) raise { value_json(item, depth + 1) }),
      )
    _ => raise @scheme.Invalid("Value has no JSON representation")
  }
}

///|
/// Register typed IR and JSON procedures in a caller-owned Scheme session.
pub fn install(runtime : @scheme.Runtime) -> Unit raise {
  @backend.install(runtime)
  runtime.define_native("ir-read", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-read")
    @scheme.IRFile(
      @migration.to_current(@versioned_json.read(args[0].as_text())),
    )
  })
  runtime.define_native("ir-write", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-write")
    @scheme.Text(@ir_json.write(args[0].as_file()))
  })
  runtime.define_native("ir-value-read", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-value-read")
    @scheme.IR(@ir_json.read_value(@wire.parse(args[0].as_text())))
  })
  runtime.define_native("ir-value-write", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-value-write")
    @scheme.Text(@ir_json.write_value(args[0].as_ir()).stringify())
  })
  runtime.define_native("ir->datum", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir->datum")
    json_value(@ir_json.write_value(args[0].as_ir()))
  })
  runtime.define_native("datum->ir", fn(_rt, args) raise {
    @scheme.arity(args, 1, "datum->ir")
    @scheme.IR(@ir_json.read_value(value_json(args[0], 0)))
  })
  runtime.define_native("json-read", fn(_rt, args) raise {
    @scheme.arity(args, 1, "json-read")
    json_value(@wire.parse(args[0].as_text()))
  })
  runtime.define_native("json-write", fn(_rt, args) raise {
    @scheme.arity(args, 1, "json-write")
    @scheme.Text(value_json(args[0], 0).stringify())
  })
  runtime.define_native("scheme->ir", fn(_rt, args) raise {
    @scheme.arity(args, 1, "scheme->ir")
    @scheme.IR(@frontend.compile_expression(args[0].as_text()))
  })
  runtime.define_native("ir->scheme", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir->scheme")
    @scheme.Text(@backend.emit_expression(args[0].as_ir()))
  })
  runtime.define_native("ir-eval", fn(rt, args) raise {
    @scheme.arity(args, 1, "ir-eval")
    @backend.evaluate_in(rt, args[0].as_ir())
  })
  runtime.define_native("ir-kind", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-kind")
    let json = @ir_json.write_value(args[0].as_ir())
    let fields = @wire.object(json)
    @scheme.Text(fields.iter().collect()[0].0)
  })
  runtime.define_native("ir-integer?", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-integer?")
    @scheme.Boolean(
      args[0].as_ir() is @ir.Value::Literal(_, @ir.Literal::IntegerLiteral(_)),
    )
  })
  runtime.define_native("ir-integer", fn(_rt, args) raise {
    @scheme.arity(args, 1, "ir-integer")
    match args[0].as_ir() {
      Literal(_, IntegerLiteral(s)) => @scheme.integer(s)
      _ => raise @scheme.Invalid("Expected IR integer literal")
    }
  })
  runtime.define_native("ir-with-integer", fn(_rt, args) raise {
    @scheme.arity(args, 2, "ir-with-integer")
    match (args[0].as_ir(), args[1]) {
      (Literal(attributes, IntegerLiteral(_)), Number(Integer(n))) =>
        @scheme.IR(
          @ir.Value::Literal(
            attributes,
            @ir.Literal::IntegerLiteral(n.to_string()),
          ),
        )
      _ =>
        raise @scheme.Invalid(
          "Expected IR integer and exact integer replacement",
        )
    }
  })
  runtime.define_native("ir-rewrite", fn(rt, args) raise {
    @scheme.arity(args, 2, "ir-rewrite")
    @scheme.IR(
      rewrite_value(args[0].as_ir(), fn(value) raise {
        rt.call(args[1], [@scheme.IR(value)]).as_ir()
      }),
    )
  })
  runtime.define_native("ir-rewrite-file", fn(rt, args) raise {
    @scheme.arity(args, 2, "ir-rewrite-file")
    @scheme.IRFile(
      rewrite_file(args[0].as_file(), fn(value) raise {
        rt.call(args[1], [@scheme.IR(value)]).as_ir()
      }),
    )
  })
}

///|
pub fn new_runtime(
  limits~ : @scheme.Limits = @scheme.Limits::default(),
) -> @scheme.Runtime raise {
  let runtime = @scheme.Runtime::new(limits~)
  install(runtime)
  runtime
}

///|
/// Script evaluates to an IRFile -> IRFile procedure. The input is not mutated.
pub fn transform_file(
  file : @ir.IRFile,
  script : String,
  limits~ : @scheme.Limits = @scheme.Limits::default(),
) -> @ir.IRFile raise {
  let runtime = new_runtime(limits~)
  let transform = runtime.eval(script)
  runtime.call(transform, [@scheme.IRFile(file)]).as_file()
}

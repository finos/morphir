///|
test "Scheme frontend through real Morphir IR and Scheme backend" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let reread = @ir_json.read(@ir_json.write(file))
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(reread, @ir.FQName::parse("user:main#main"), []),
    ),
    "42",
  )
  for
    source in [
      "(let ((x 10)) (let ((x 20) (y x)) (+ x y)))", "(letrec ((sum (lambda (n) (if (= n 0) 0 (+ n (sum (- n 1))))))) (sum 10))",
    ] {
    let ir = @frontend.compile_expression(source)
    assert_eq(
      @scheme.value_to_string(@backend.evaluate(ir)),
      @scheme.value_to_string(@scheme.eval_program(source)),
    )
  }
}

///|
test "scripted bottom-up IR transform retains source metadata" {
  let runtime = @pipeline.new_runtime()
  let result = runtime.eval(
    "(ir-eval (ir-rewrite (scheme->ir \"(+ 20 20)\") (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 1)) node))))",
  )
  assert_eq(@scheme.value_to_string(result), "42")
  let file = @frontend.compile_file("40")
  let transformed = @pipeline.transform_file(
    file, "(lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 2)) node))))",
  )
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(transformed, @ir.FQName::parse("user:main#main"), []),
    ),
    "42",
  )
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(file, @ir.FQName::parse("user:main#main"), []),
    ),
    "40",
  )
}

///|
test "ir-eval uses host native bindings in the caller's runtime" {
  let runtime = @pipeline.new_runtime()
  let name = @ir.FQName::parse("test:main#answer")
  @backend.register_accelerator(runtime, name, 0, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  runtime.set_global(
    "input",
    @scheme.IR(@ir.Value::Reference(@ir.ValueAttributes::default(), name)),
  )
  assert_eq(@scheme.value_to_string(runtime.eval("(ir-eval input)")), "42")
}

///|
test "lowering preserves shadowed parameters and sequential bindings" {
  for
    source in [
      "(let ((f (lambda (x) (lambda (x) x)))) ((f 1) 42))", "(let* ((x 20) (x (+ x 22))) x)",
      "(let ((x 1.0)) x)",
    ] {
    assert_eq(
      @scheme.value_to_string(
        @backend.evaluate(@frontend.compile_expression(source)),
      ),
      @scheme.value_to_string(@scheme.eval_program(source)),
    ) catch {
      @scheme.Unsupported(message) => fail(source + ": " + message)
      error => raise error
    }
  }
  for source in ["1 (define x 2)", "(set! x 2)", "1/2"] {
    let refused = try {
      ignore(@frontend.compile_file(source))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "rewriting preserves explicit attributes" {
  let attributes : @ir.ValueAttributes = {
    source: Some({ start_line: 2, start_column: 3, end_line: 2, end_column: 5, }),
    inferred_type: Some(@frontend.unknown_type()),
    extensions: Map([]),
  }
  let value = @ir.Value::Literal(attributes, @ir.Literal::IntegerLiteral("40"))
  let runtime = @pipeline.new_runtime()
  runtime.set_global("input", @scheme.IR(value))
  let result = runtime.eval("(ir-with-integer input 42)").as_ir()
  assert_eq(
    result,
    @ir.Value::Literal(attributes, @ir.Literal::IntegerLiteral("42")),
  )
  assert_eq(runtime.lookup("input").as_ir(), value)
}

///|
fn signature_variables(t : @ir.Type, out : Array[(String, Bool)]) -> Unit {
  match t {
    Variable(a, n) => out.push((n.to_canonical(), a.is_unknown()))
    Function(_, x, y) => {
      signature_variables(x, out)
      signature_variables(y, out)
    }
    _ => ()
  }
}

///|
fn definition_variables(
  def : @ir.ValueDefinition,
  out : Array[(String, Bool)],
) -> Unit {
  guard def is ExpressionBody(inputs, output, body) else { return }
  inputs.each(i => signature_variables(i.1, out))
  signature_variables(output, out)
  body_variables(body, out)
}

///|
fn body_variables(v : @ir.Value, out : Array[(String, Bool)]) -> Unit {
  match v {
    LetDefinition(_, _, def, rest) => {
      definition_variables(def, out)
      body_variables(rest, out)
    }
    LetRecursion(_, defs, rest) => {
      for _, def in defs {
        definition_variables(def, out)
      }
      body_variables(rest, out)
    }
    Apply(_, f, x) => {
      body_variables(f, out)
      body_variables(x, out)
    }
    Lambda(_, _, body) => body_variables(body, out)
    IfThenElse(_, c, t, e) => {
      body_variables(c, out)
      body_variables(t, out)
      body_variables(e, out)
    }
    _ => ()
  }
}

///|
/// The variable names and markers of every signature type of `name`, in traversal order: inputs, then output,
/// then the let signatures of the body.
fn placeholder_names(file : @ir.IRFile, name : String) -> Array[(String, Bool)] {
  guard file.distribution is Library(_, _, def) else { panic() }
  let out = []
  for _, m in def.modules {
    for n, v in m.value.values {
      if n.to_canonical() == name {
        definition_variables(v.value.value, out)
      }
    }
  }
  out
}

///|
fn body_of(file : @ir.IRFile, name : String) -> @ir.Value {
  guard file.distribution is Library(_, _, def) else { panic() }
  for _, m in def.modules {
    for n, v in m.value.values {
      if n.to_canonical() == name && v.value.value is ExpressionBody(_, _, body) {
        return body
      }
    }
  }
  panic()
}

///|
test "each placeholder has its own marked name in a declaration" {
  let file = @frontend.compile_file("(define (f x y) (+ x y))")
  assert_eq(placeholder_names(file, "f"), [
    ("t-0", true),
    ("t-1", true),
    ("t-2", true),
  ])
}

///|
test "placeholder numbers restart for each declaration" {
  let file = @frontend.compile_file("(define (f x) x)\n(define (g y) y)")
  assert_eq(placeholder_names(file, "f")[0], ("t-0", true))
  assert_eq(placeholder_names(file, "g")[0], ("t-0", true))
}

///|
test "let signatures get their own placeholders" {
  let file = @frontend.compile_file("(define (f x) (let ((y x)) y))")
  let names = placeholder_names(file, "f")
  assert_true(names.length() > 2)
  assert_true(names.all(n => n.1))
  let distinct : Map[String, Bool] = Map([])
  names.each(n => distinct[n.0] = true)
  assert_eq(distinct.length(), names.length())
}

///|
test "integer literals carry the fact Int" {
  let file = @frontend.compile_file("(define answer 42)")
  guard body_of(file, "answer") is Literal(a, IntegerLiteral(_)) else {
    fail("literal")
  }
  guard a.inferred_type is Some(Reference(_, name, [])) else { fail("type") }
  assert_eq(name.to_canonical(), "morphir/SDK:basics#int")
}

///|
test "no scheme-value variable remains" {
  let file = @frontend.compile_file(
    "(define (f x) (let ((y x)) (lambda (z) (+ y z))))",
  )
  assert_false(@ir_json.write(file).contains("scheme-value"))
}

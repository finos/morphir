///|
test "inexact zero printing preserves its sign" {
  assert_eq(@scheme.value_to_string(@scheme.eval_program("-0.0")), "-0.0")
  assert_eq(@scheme.value_to_string(@scheme.eval_program("0.0")), "0.0")
}

///|
test "lexical closures, exact arithmetic and tail recursion" {
  assert_eq(
    @scheme.value_to_string(
      @scheme.eval_program(
        "(define (make-adder x) (lambda (y) (+ x y))) ((make-adder 10) 32)",
      ),
    ),
    "42",
  )
  assert_eq(
    @scheme.value_to_string(@scheme.eval_program("(+ 18446744073709551616 1)")),
    "18446744073709551617",
  )
  assert_eq(@scheme.value_to_string(@scheme.eval_program("(+ 1/3 1/6)")), "1/2")
  assert_eq(
    @scheme.value_to_string(
      @scheme.eval_program(
        "(let loop ((n 10000) (sum 0)) (if (= n 0) sum (loop (- n 1) (+ sum 1))))",
      ),
    ),
    "10000",
  )
}

///|
test "data, lists and persistent sessions" {
  let runtime = @scheme.Runtime::new()
  ignore(runtime.eval("(define answer 40)"))
  assert_eq(
    @scheme.value_to_string(runtime.eval("(set! answer (+ answer 2)) answer")),
    "42",
  )
  assert_eq(
    @scheme.value_to_string(runtime.eval("(map (lambda (x) (* x x)) '(1 2 3))")),
    "(1 4 9)",
  )
  assert_eq(@scheme.value_to_string(runtime.eval("(apply + 1 '(2 3))")), "6")
  assert_eq(
    @scheme.value_to_string(runtime.eval("((lambda (a . rest) rest) 1 2 3)")),
    "(2 3)",
  )
  assert_eq(
    @scheme.value_to_string(
      runtime.eval("(record-ref (record (cons \"x\" 42)) \"x\")"),
    ),
    "42",
  )
}

///|
test "resource errors leave the session usable" {
  let runtime = @scheme.Runtime::new(limits={
    steps: 100,
    depth: 32,
    frames: 100,
  })
  let limited = try {
    ignore(runtime.eval("(let loop () (loop))"))
    false
  } catch {
    @scheme.Limit(_) => true
    _ => false
  }
  assert_true(limited)
  assert_eq(@scheme.value_to_string(runtime.eval("(+ 1 2)")), "3")
}

///|
test "reader handles comments, quotation, vectors and improper pairs" {
  assert_eq(
    @scheme.value_to_string(
      @scheme.eval_program("#| outer #| inner |# |# #; (+ 9 9) '(1 . 2)"),
    ),
    "(1 . 2)",
  )
  assert_eq(
    @scheme.value_to_string(@scheme.eval_program("#(#t #\\space \"hello\")")),
    "#(#t #\\space \"hello\")",
  )
  for bad in ["(", ")", "(1 . 2 3)", "#|", "#;", "\"unterminated"] {
    let refused = try {
      ignore(@scheme.parse_program(bad))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "reader and writer preserve escaped symbols strings and inexact numbers" {
  for
    datum in [
      @scheme.Datum::Text("quote\" slash\\ control\u0008\n雪"),
      @scheme.Datum::Symbol("12abc"),
      @scheme.Datum::Symbol("`name"),
      @scheme.Datum::Symbol("a|b\\c"),
      @scheme.Datum::Number(@scheme.Number::Real(1.0)),
    ] {
    assert_eq(@scheme.parse_program(datum.to_source())[0], datum)
  }
}

///|
test "recursive scopes reject uninitialized reads and allow mutual closures" {
  let refused = try {
    ignore(@scheme.eval_program("(let ((x 1)) (letrec ((x x)) x))"))
    false
  } catch {
    @scheme.Invalid(_) => true
    _ => false
  }
  assert_true(refused)
  assert_eq(
    @scheme.value_to_string(
      @scheme.eval_program(
        "(letrec ((even (lambda (n) (if (= n 0) #t (odd (- n 1))))) (odd (lambda (n) (if (= n 0) #f (even (- n 1)))))) (even 10))",
      ),
    ),
    "#t",
  )
  assert_eq(
    @scheme.value_to_string(
      @scheme.eval_program("(let* ((x 1) (x (+ x 1))) x)"),
    ),
    "2",
  )
  let a = @scheme.Runtime::new()
  let b = @scheme.Runtime::new()
  let refused = try {
    ignore(b.call(a.eval("(lambda (x) x)"), [@scheme.Unit]))
    false
  } catch {
    @scheme.Invalid(_) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "host cancellation interrupts an evaluator step" {
  let runtime = @scheme.Runtime::new()
  let ticks = Ref(0)
  runtime.set_cancelled(fn() {
    ticks.val += 1
    ticks.val > 20
  })
  let error = try {
    ignore(
      runtime.eval("(letrec ((loop (lambda (n) (loop (+ n 1))))) (loop 0))"),
    )
    ""
  } catch {
    error => @scheme.error_message(error)
  }
  assert_true(error.contains("cancelled"))
}

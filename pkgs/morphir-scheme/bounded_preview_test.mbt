///|
fn prefix(text : String, limit : Int32) -> String {
  let mut end = if text.length() < limit { text.length() } else { limit }
  if end > 0 &&
    end < text.length() &&
    text.code_unit_at(end).to_int() >= 0xDC00 &&
    text.code_unit_at(end).to_int() <= 0xDFFF {
    end -= 1
  }
  text[0:end].to_owned()
}

///|
test "bounded preview preserves full printer prefixes and Unicode boundaries" {
  for
    source in [
      "'(1 #t . hello)", "#(1 #f)", "\"quote\\\" slash\\\\ newline\\n😀雪\"",
      "'|a b\\|c|", "'|12abc|", "'+1", "'|+1/0|", "'hello", "''x", "#\\space", "#\\😀",
      "1/3", "-0.0", "(unit)", "(lambda (x) x)", "(record (cons \"a\" 1) (cons \"😀\" #t))",
      "'()", "\"\"", "'||",
    ] {
    let value = @scheme.eval_program(source) catch {
      error => fail(source + ": " + @scheme.error_message(error))
    }
    let full = @scheme.value_to_string(value)
    for limit = 0; limit <= full.length() + 1; limit = limit + 1 {
      assert_eq(@scheme.value_preview(value, limit), prefix(full, limit))
    }
  }
}

///|
test "bounded preview stops before expanding a shared vector tree" {
  let value = @scheme.eval_program(
    "(let loop ((n 30) (v #(1))) (if (= n 0) v (loop (- n 1) (vector v v))))",
  )
  let preview = @scheme.value_preview(value, 4000)
  assert_eq(preview.length(), 4000)
  assert_true(preview.has_prefix("#(#(#("))
}

///|
test "bounded preview validates limits and bounds empty traversal" {
  for limit in [-1, 65537] {
    let rejected = try {
      ignore(@scheme.value_preview(@scheme.Unit, limit))
      false
    } catch {
      @scheme.Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  let empty = @scheme.Record(Map([("", @scheme.Text(""))]))
  assert_eq(@scheme.value_preview(empty, 100), @scheme.value_to_string(empty))
  let mut deep = @scheme.Unit
  for _ in 0..<258 {
    deep = @scheme.Vector([deep])
  }
  let rejected = try {
    ignore(@scheme.value_preview(deep, 4000))
    false
  } catch {
    @scheme.Limit(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(@scheme.value_preview(deep, 0), "")
}

///|
test "bounded preview limits lookahead and scalar allocation before rendering" {
  for
    value in [
      @scheme.Value::Symbol("x".repeat(100001)),
      @scheme.Value::Number(
        @scheme.Integer(@bigint.BigInt::from_int(1) << 100000),
      ),
    ] {
    let rejected = try {
      ignore(@scheme.value_preview(value, 4000))
      false
    } catch {
      @scheme.Limit(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  let text = @scheme.Value::Text("😀".repeat(100000))
  assert_eq(@scheme.value_preview(text, 2), "\"")
  assert_eq(@scheme.value_preview(text, 3), "\"😀")
  assert_eq(@scheme.value_preview(text, 65536).length(), 65535)
  let record = @scheme.Record(Map([("😀".repeat(100000), @scheme.Text(""))]))
  assert_eq(@scheme.value_preview(record, 12), "#<record 😀")
  let supported_integer = @scheme.Value::Number(
    @scheme.Integer(@bigint.BigInt::from_string("9".repeat(10000))),
  )
  assert_eq(@scheme.value_preview(supported_integer, 4000), "9".repeat(4000))
}

///|
test "error argument rendering shares one bounded diagnostic budget" {
  let source = "(let loop ((n 15) (v #(1))) (if (= n 0) (error v v) (loop (- n 1) (vector v v))))"
  let message = try {
    ignore(@scheme.eval_program(source))
    "accepted"
  } catch {
    @scheme.Invalid(message) => message
    error => @scheme.error_message(error)
  }
  assert_eq(message.length(), 4096)
  assert_true(message.has_prefix("#(#(#("))
}

///|
test "error diagnostics preserve small messages and aggregate prefix parity" {
  for
    (source, expected) in [
      ("(error)", ""),
      ("(error \"hello\" 7 #t)", "\"hello\" 7 #t"),
      ("(error '(1 #t) #(2 3))", "(1 #t) #(2 3)"),
      (
        "(error \"" + "x".repeat(3000) + "\" \"" + "y".repeat(3000) + "\")",
        "\"" + "x".repeat(3000) + "\" \"" + "y".repeat(1092),
      ),
    ] {
    let actual = try {
      ignore(@scheme.eval_program(source))
      "accepted"
    } catch {
      @scheme.Invalid(message) => message
      error => @scheme.error_message(error)
    }
    assert_eq(actual, expected)
  }
}

///|
test "error diagnostics stop before expanding a depth thirty shared vector" {
  let actual = try {
    ignore(
      @scheme.eval_program(
        "(let loop ((n 30) (v #(1))) (if (= n 0) (error v) (loop (- n 1) (vector v v))))",
      ),
    )
    "accepted"
  } catch {
    @scheme.Invalid(message) => message
    error => @scheme.error_message(error)
  }
  assert_eq(actual.length(), 4096)
  assert_true(actual.has_prefix("#(#(#("))
}

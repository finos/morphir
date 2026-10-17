///|
test "canonical SDK Int32 declarations share the historical runtime ABI" {
  for accelerators in [false, true] {
    let runtime = @scheme.Runtime::new()
    install(runtime, accelerators~)
    let to_int32 = runtime.call(runtime.lookup("r:morphir/SDK:int#to-int-32"), [])
    let from_int32 = runtime.call(
      runtime.lookup("r:morphir/SDK:int#from-int-32"),
      [],
    )
    for text in ["-2147483648", "0", "2147483647"] {
      guard runtime.call(to_int32, [@scheme.integer(text)])
        is Tagged("morphir/SDK:maybe#just", [bounded]) else {
        fail("Expected Int32")
      }
      guard bounded is Tagged("morphir/SDK:int#int32", [_]) else {
        fail("Expected historical opaque tag")
      }
      guard runtime.call(from_int32, [bounded]) is Number(Integer(value)) else {
        fail("Expected Integer")
      }
      assert_eq(value.to_string(), text)
    }
    for text in ["-2147483649", "2147483648"] {
      guard runtime.call(to_int32, [@scheme.integer(text)])
        is Tagged("morphir/SDK:maybe#nothing", []) else {
        fail("Expected checked refusal")
      }
    }
  }
}

///|
test "all pinned SDK values install with the declared arity" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  assert_eq(sdk_registry().length(), 248)
  for (name, arity) in sdk_registry() {
    assert_true(runtime.has_native("accelerator:" + name))
    assert_eq(sdk_expected_arity(name), Some(arity))
    ignore(runtime.lookup("r:" + name))
    let arguments : Array[@scheme.Value] = []
    for _ in 0..<arity {
      arguments.push(@scheme.integer("0"))
    }
    let missing = try {
      ignore(sdk_dispatch(runtime, name, arguments))
      false
    } catch {
      @scheme.Unbound(_) | @scheme.Unsupported(_) => true
      _ => false
    }
    assert_true(!missing)
  }
}

///|
test "nonreturning never and callback failures stay explicit" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  let never = try {
    ignore(runtime.eval("(%morphir-sdk \"morphir/SDK:basics#never\" 0)"))
    false
  } catch {
    @scheme.Invalid(message) => message.contains("Never")
    _ => false
  }
  assert_true(never)
  runtime.define_native("fail-callback", fn(_rt, args) raise {
    @scheme.arity(args, 1, "fail-callback")
    raise @scheme.Invalid("callback failed")
  })
  let failure = try {
    ignore(
      runtime.eval(
        "(%morphir-sdk \"morphir/SDK:list#map\" (lambda (x) (fail-callback x)) '(1 2))",
      ),
    )
    false
  } catch {
    @scheme.Invalid("callback failed") => true
    _ => false
  }
  assert_true(failure)
}

///|
test "SDK higher-order callbacks honor runtime cancellation" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  runtime.define_native("cancel-after-first", fn(rt, args) raise {
    @scheme.arity(args, 1, "cancel-after-first")
    rt.set_cancelled(fn() { true })
    args[0]
  })
  let cancelled = try {
    ignore(
      runtime.eval(
        "(%morphir-sdk \"morphir/SDK:list#map\" (lambda (x) (cancel-after-first x)) '(1 2))",
      ),
    )
    false
  } catch {
    @scheme.Limit("cancelled") => true
    _ => false
  }
  assert_true(cancelled)
}

///|
test "SDK equality rejects callable values inside collections" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  let refused = try {
    ignore(
      runtime.eval(
        "(%morphir-sdk \"morphir/SDK:basics#equal\" (list (lambda (x) x)) (list (lambda (x) x)))",
      ),
    )
    false
  } catch {
    @scheme.Invalid(message) => message.contains("does not support functions")
    _ => false
  }
  assert_true(refused)
}

///|
test "SDK preserves isolated UTF-16 units across chained calls" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  let source = "(%morphir-sdk \"morphir/SDK:string#length\" (%morphir-sdk \"morphir/SDK:basics#append\" (%morphir-sdk \"morphir/SDK:string#slice\" 0 1 \"😀\") \"x\"))"
  assert_eq(@scheme.value_to_string(runtime.eval(source)), "2")
}

///|
test "SDK rejects forged fixed-width values outside their range" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  let refused = try {
    ignore(
      runtime.eval(
        "(%morphir-sdk \"morphir/SDK:int#from-int8\" (%morphir-tag \"morphir/SDK:int#int8\" 128))",
      ),
    )
    false
  } catch {
    @scheme.Invalid(message) => message.contains("out of range")
    _ => false
  }
  assert_true(refused)
}

///|
test "Dict comparison errors carry the SDK value name" {
  let runtime = @scheme.Runtime::new()
  install(runtime)
  let source = "(%morphir-sdk \"morphir/SDK:dict#from-list\" (list (vector (%morphir-sdk \"morphir/SDK:basics#divide\" 0.0 0.0) 1) (vector 0.0 2)))"
  let refused = try {
    ignore(runtime.eval(source))
    false
  } catch {
    @scheme.Invalid(message) =>
      message.contains("morphir/SDK:dict#from-list") &&
      message.contains("invalid comparison")
    _ => false
  }
  assert_true(refused)
}

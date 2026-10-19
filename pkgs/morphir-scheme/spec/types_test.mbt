///|
fn ty(text : String) -> @ir.Type raise {
  @spec.read_type_text(text, package_name="morphir/SDK", module_path="list")
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
fn error_of(text : String) -> String {
  try {
    ignore(ty(text))
    ""
  } catch {
    @spec.SpecError(line~, column~, message~) => "\{line}:\{column} \{message}"
    _ => "other"
  }
}

///|
test "variables carry their constraint class" {
  guard ty("comparable-key") is Variable(attrs, name) else { fail("variable") }
  assert_eq(name.to_canonical(), "comparable-key")
  assert_eq(
    attrs.constraints.get("typeclass"),
    Some(@ir.Data::Text("comparable")),
  )
  guard ty("a") is Variable(plain, _) else { fail("variable") }
  assert_true(plain.constraints.is_empty())
}

///|
test "references resolve in the package or name a full FQName" {
  guard ty("basics#int") is Reference(_, name, []) else { fail("reference") }
  assert_eq(name, fq("morphir/SDK:basics#int"))
  guard ty("(list#list a)") is Reference(_, list_name, [Variable(_, _)]) else {
    fail("applied")
  }
  assert_eq(list_name, fq("morphir/SDK:list#list"))
  guard ty("acme/app:money#money") is Reference(_, other, []) else {
    fail("full")
  }
  assert_eq(other, fq("acme/app:money#money"))
}

///|
test "functions are curried and right-associative" {
  let t = ty("(-> a b c)")
  guard t
    is Function(_, Variable(_, a), Function(_, Variable(_, b), Variable(_, c))) else {
    fail("curried")
  }
  assert_eq([a, b, c].map(n => n.to_canonical()), ["a", "b", "c"])
}

///|
test "tuples, records, extensible records and unit" {
  assert_true(ty("(tuple a b)") is Tuple(_, [_, _]))
  guard ty("(record (total basics#int))") is Record(_, fields) else {
    fail("record")
  }
  assert_eq(fields.keys().map(n => n.to_canonical()).collect(), ["total"])
  assert_true(ty("(record r (total basics#int))") is ExtensibleRecord(_, _, _))
  assert_true(ty("()") is Unit(_))
}

///|
test "native union syntax preserves alternatives and rejects insufficient arity" {
  let t = ty("(union a (union a b))")
  guard t is Union(_, [Variable(_, _), Union(_, [_, _])]) else {
    fail("union structure lost")
  }
  assert_eq(
    @spec.print_type(t, package_name=@ir.Path::parse("morphir/SDK")),
    "(union a (union a b))",
  )
  assert_true(error_of("(union)").contains("at least two"))
  assert_true(error_of("(union a)").contains("at least two"))
}

///|
test "bad forms are refused with a position" {
  assert_eq(error_of("(->)"), "1:1 a function type needs at least two types")
  assert_eq(
    error_of("lessThan"),
    "1:1 name `lessThan` is not canonical (use `less-than`)",
  )
  assert_eq(error_of("(tuple a)"), "1:1 a tuple needs at least two types")
  assert_eq(error_of("(frob a)"), "1:1 unknown type form `frob`")
  assert_eq(
    error_of("(val-family! a)"),
    "1:1 `val-family!` is reserved for macros",
  )
  assert_eq(error_of("\"text\""), "1:1 expected a type")
}

///|
test "bad package or module names raise instead of panicking" {
  let package_error = try {
    ignore(
      @spec.read_type_text("a", package_name="Bad Name!", module_path="list"),
    )
    ""
  } catch {
    @spec.SpecError(line~, column~, message~) => "\{line}:\{column} \{message}"
  }
  assert_eq(package_error, "1:1 invalid package name `Bad Name!`")
  let module_error = try {
    ignore(
      @spec.read_type_text(
        "a",
        package_name="morphir/SDK",
        module_path="Bad Name!",
      ),
    )
    ""
  } catch {
    @spec.SpecError(line~, column~, message~) => "\{line}:\{column} \{message}"
  }
  assert_eq(module_error, "1:1 invalid module name `Bad Name!`")
}

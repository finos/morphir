///|
fn solver() -> Solver {
  Solver::new(fn(_, _) { None })
}

///|
/// A rigid variable whose classes come from its name prefix.
fn rigid(name : String) -> Ty {
  Rigid(name, class_of_text(name))
}

///|
let int : Ty = Con("morphir/SDK:basics#int", [])

///|
let float : Ty = Con("morphir/SDK:basics#float", [])

///|
let string : Ty = Con("morphir/SDK:string#string", [])

///|
let char : Ty = Con("morphir/SDK:char#char", [])

///|
fn list(t : Ty) -> Ty {
  Con("morphir/SDK:list#list", [t])
}

///|
fn code(f : () -> Unit raise Mismatch) -> String {
  try {
    f()
    ""
  } catch {
    Mismatch(c, _, _) => c
  }
}

///|
fn record(fields : Array[(String, Ty)], tail : Ty?) -> Ty {
  Rec(Map::from_array(fields), tail)
}

///|
fn state(s : Solver, t : Ty) -> (Int32, Array[String]) {
  guard s.prune(t) is Meta(id) else { abort("not an unbound meta") }
  guard s.metas[id] is Unbound(level~, classes~) else { abort("linked meta") }
  (level, classes)
}

///|
/// The code of unifying a fresh meta of `class` with `t`.
fn instance(class : String, t : Ty) -> String {
  let s = solver()
  code(() => s.unify(s.fresh(1, [class]), t))
}

///|
test "class joins" {
  assert_eq(join(["comparable"], ["appendable"]), Some(["compappend"]))
  assert_eq(join(["number"], ["comparable"]), Some(["number"]))
  assert_eq(join(["number"], ["appendable"]), None)
  assert_eq(join([], ["number"]), Some(["number"]))
}

///|
test "class joins: every row of the lattice, in both orders" {
  let rows : Array[(Array[String], Array[String], Array[String]?)] = [
    ([], [], Some([])),
    ([], ["comparable"], Some(["comparable"])),
    ([], ["appendable"], Some(["appendable"])),
    ([], ["compappend"], Some(["compappend"])),
    (["number"], ["number"], Some(["number"])),
    (["comparable"], ["comparable"], Some(["comparable"])),
    (["appendable"], ["appendable"], Some(["appendable"])),
    (["compappend"], ["compappend"], Some(["compappend"])),
    (["comparable"], ["appendable"], Some(["compappend"])),
    (["number"], ["comparable"], Some(["number"])),
    (["compappend"], ["comparable"], Some(["compappend"])),
    (["compappend"], ["appendable"], Some(["compappend"])),
    (["number"], ["appendable"], None),
    (["number"], ["compappend"], None),
  ]
  for row in rows {
    let (a, b, expected) = row
    assert_eq(join(a, b), expected)
    assert_eq(join(b, a), expected)
  }
}

///|
test "number metas accept Int and Float and refuse String" {
  let s = solver()
  let n = s.fresh(1, ["number"])
  s.unify(n, float)
  assert_eq(s.prune(n), float)
  let m = s.fresh(1, ["number"])
  assert_eq(code(() => s.unify(m, string)), "no_instance")
}

///|
test "instances: every row of the instance table" {
  let fun = Fun(int, int)
  // number
  assert_eq(instance("number", int), "")
  assert_eq(instance("number", float), "")
  assert_eq(instance("number", string), "no_instance")
  assert_eq(instance("number", char), "no_instance")
  assert_eq(instance("number", list(int)), "no_instance")
  // comparable
  assert_eq(instance("comparable", int), "")
  assert_eq(instance("comparable", float), "")
  assert_eq(instance("comparable", char), "")
  assert_eq(instance("comparable", string), "")
  assert_eq(instance("comparable", list(int)), "")
  assert_eq(instance("comparable", list(fun)), "no_instance")
  assert_eq(instance("comparable", Tup([int, string])), "")
  assert_eq(instance("comparable", Tup([int, string, char])), "")
  assert_eq(instance("comparable", Tup([int, fun])), "no_instance")
  assert_eq(instance("comparable", fun), "no_instance")
  assert_eq(instance("comparable", UnitTy), "no_instance")
  assert_eq(instance("comparable", record([], None)), "no_instance")
  assert_eq(
    instance("comparable", Con("morphir/SDK:decimal#decimal", [])),
    "no_instance",
  )
  // appendable
  assert_eq(instance("appendable", string), "")
  assert_eq(instance("appendable", list(fun)), "")
  assert_eq(instance("appendable", int), "no_instance")
  assert_eq(instance("appendable", char), "no_instance")
  // compappend
  assert_eq(instance("compappend", string), "")
  assert_eq(instance("compappend", int), "no_instance")
  assert_eq(instance("compappend", char), "no_instance")
}

///|
test "a tuple of 4 comparables has no comparable instance" {
  assert_eq(instance("comparable", Tup([int, int, int, int])), "no_instance")
}

///|
test "compappend accepts List Int and refuses List (Int -> Int)" {
  assert_eq(instance("compappend", list(int)), "")
  assert_eq(instance("compappend", list(Fun(int, int))), "no_instance")
}

///|
test "comparable lists propagate to the element" {
  let s = solver()
  let c = s.fresh(1, ["comparable"])
  let e = s.fresh(1, [])
  s.unify(c, list(e))
  // The element must now be comparable: unifying it with a function fails.
  assert_eq(code(() => s.unify(e, Fun(int, int))), "no_instance")
}

///|
test "comparable tuples propagate to the elements" {
  let s = solver()
  let a = s.fresh(1, [])
  let b = s.fresh(1, ["appendable"])
  s.unify(s.fresh(1, ["comparable"]), Tup([a, b]))
  assert_eq(state(s, a).1, ["comparable"])
  assert_eq(state(s, b).1, ["compappend"])
}

///|
test "two metas merge their classes and keep the lower level" {
  let s = solver()
  let a = s.fresh(3, ["comparable"])
  let b = s.fresh(1, ["appendable"])
  s.unify(a, b)
  assert_eq(state(s, a), (1, ["compappend"]))
  assert_eq(state(s, b), (1, ["compappend"]))
  assert_eq(code(() => s.unify(a, int)), "no_instance")
  s.unify(b, string)
  assert_eq(s.prune(a), string)
  let n = s.fresh(1, ["number"])
  assert_eq(code(() => s.unify(n, s.fresh(1, ["appendable"]))), "no_instance")
  s.unify(n, n)
}

///|
test "binding a meta lowers the levels of the metas inside the type" {
  let s = solver()
  let outer = s.fresh(1, [])
  let inner = s.fresh(4, [])
  let row = s.fresh(5, [])
  s.unify(outer, Fun(list(inner), record([("x", int)], Some(row))))
  assert_eq(state(s, inner).0, 1)
  assert_eq(state(s, row).0, 1)
  let low = s.fresh(0, [])
  let high = s.fresh(2, [])
  s.unify(Tup([high]), low)
  assert_eq(state(s, high).0, 0)
}

///|
test "occurs check and rigid variables" {
  let s = solver()
  let a = s.fresh(1, [])
  assert_eq(code(() => s.unify(a, list(a))), "occurs")
  assert_eq(code(() => s.unify(rigid("a"), int)), "rigid_variable")
  s.unify(rigid("a"), rigid("a"))
}

///|
test "rigid variables: other cases" {
  let s = solver()
  assert_eq(code(() => s.unify(rigid("a"), rigid("b"))), "rigid_variable")
  assert_eq(code(() => s.unify(int, rigid("a"))), "rigid_variable")
  let m = s.fresh(1, [])
  s.unify(m, rigid("a"))
  assert_eq(s.prune(m), rigid("a"))
  let r = s.fresh(1, [])
  s.unify(rigid("b"), r)
  assert_eq(s.prune(r), rigid("b"))
}

///|
test "a rigid number satisfies comparable" {
  let s = solver()
  s.unify(s.fresh(1, ["comparable"]), rigid("number"))
  s.unify(s.fresh(1, ["number"]), rigid("number-a"))
  s.unify(s.fresh(1, []), rigid("number"))
}

///|
test "a rigid satisfies a class only when its own class is at least as strong" {
  // A body that narrows an annotated variable is `rigid_variable` (spec sections 4 and 6).
  assert_eq(instance("number", rigid("comparable")), "rigid_variable")
  assert_eq(instance("comparable", rigid("a")), "rigid_variable")
  assert_eq(instance("comparable", rigid("appendable")), "rigid_variable")
  assert_eq(instance("comparable", rigid("compappend")), "")
  assert_eq(instance("appendable", rigid("compappend")), "")
  assert_eq(instance("compappend", rigid("comparable")), "rigid_variable")
  // The classes that the rigid carries win over its name prefix.
  let s = solver()
  s.unify(s.fresh(1, ["comparable"]), Rigid("x", ["number"]))
  assert_eq(
    code(() => s.unify(s.fresh(1, ["number"]), Rigid("number", []))),
    "rigid_variable",
  )
}

///|
test "a class failure at a rigid leaf is rigid_variable" {
  // `\x -> 1` checked against the rigid `a -> a`.
  let s = solver()
  let x = s.fresh(1, [])
  let one = s.fresh(1, ["number"])
  assert_eq(
    code(() => s.unify(Fun(rigid("a"), rigid("a")), Fun(x, one))),
    "rigid_variable",
  )
  // The failing leaf is a rigid inside a list or a tuple.
  assert_eq(instance("comparable", list(rigid("a"))), "rigid_variable")
  assert_eq(instance("compappend", list(rigid("a"))), "rigid_variable")
  assert_eq(instance("comparable", Tup([int, rigid("a")])), "rigid_variable")
  // The first failing leaf decides.
  assert_eq(
    instance("comparable", Tup([Fun(int, int), rigid("a")])),
    "no_instance",
  )
  assert_eq(instance("comparable", list(rigid("comparable"))), "")
}

///|
test "structural unification" {
  let s = solver()
  let a = s.fresh(1, [])
  let b = s.fresh(1, [])
  s.unify(Fun(a, int), Fun(string, b))
  assert_eq(s.prune(a), string)
  assert_eq(s.prune(b), int)
  s.unify(Tup([a, UnitTy]), Tup([string, UnitTy]))
  s.unify(UnitTy, UnitTy)
  assert_eq(code(() => s.unify(Tup([int]), Tup([int, int]))), "type_mismatch")
  assert_eq(code(() => s.unify(Fun(int, int), int)), "type_mismatch")
  assert_eq(code(() => s.unify(UnitTy, int)), "type_mismatch")
  assert_eq(code(() => s.unify(int, string)), "type_mismatch")
  assert_eq(
    code(() => s.unify(list(int), Con("morphir/SDK:list#list", []))),
    "type_mismatch",
  )
  assert_eq(code(() => s.unify(list(int), list(string))), "type_mismatch")
}

///|
test "a mismatch carries the two pruned types" {
  let s = solver()
  let a = s.fresh(1, [])
  s.unify(a, int)
  let found = try {
    s.unify(a, string)
    None
  } catch {
    Mismatch(c, e, f) => Some((c, e, f))
  }
  assert_eq(found, Some(("type_mismatch", int, string)))
}

///|
test "records unify through rows" {
  let s = solver()
  let row = s.fresh(1, [])
  let open : Ty = Rec(Map::from_array([("total", int)]), Some(row))
  let closed : Ty = Rec(Map::from_array([("total", int), ("id", string)]), None)
  s.unify(open, closed)
  guard s.prune(row) is Rec(rest, None) else {
    fail("row solved to the remaining fields")
  }
  assert_eq(rest.keys().collect(), ["id"])
  let small : Ty = Rec(Map::from_array([("id", string)]), None)
  assert_eq(
    code(() => s.unify(Rec(Map::from_array([("total", int)]), None), small)),
    "missing_field",
  )
}

///|
test "rows: both closed" {
  let s = solver()
  let a = s.fresh(1, [])
  s.unify(
    record([("x", a), ("y", int)], None),
    record([("y", int), ("x", string)], None),
  )
  assert_eq(s.prune(a), string)
  assert_eq(
    code(() => {
      s.unify(record([("x", int)], None), record([("x", string)], None))
    }),
    "type_mismatch",
  )
  assert_eq(
    code(() => {
      s.unify(
        record([("x", int), ("y", int)], None),
        record([("x", int)], None),
      )
    }),
    "missing_field",
  )
}

///|
test "rows: open with closed, and the mirror case" {
  let s = solver()
  let r1 = s.fresh(1, [])
  let x = s.fresh(1, [])
  s.unify(
    record([("x", x)], Some(r1)),
    record([("x", int), ("y", string)], None),
  )
  assert_eq(s.prune(x), int)
  assert_eq(s.prune(r1), record([("y", string)], None))
  let r2 = s.fresh(1, [])
  s.unify(
    record([("x", int), ("y", string)], None),
    record([("y", string)], Some(r2)),
  )
  assert_eq(s.prune(r2), record([("x", int)], None))
  let r3 = s.fresh(1, [])
  assert_eq(
    code(() => {
      s.unify(record([("z", int)], Some(r3)), record([("x", int)], None))
    }),
    "missing_field",
  )
  let r4 = s.fresh(1, [])
  assert_eq(
    code(() => {
      s.unify(record([("x", int)], None), record([("z", int)], Some(r4)))
    }),
    "missing_field",
  )
  let r5 = s.fresh(1, [])
  s.unify(record([("x", int)], Some(r5)), record([("x", int)], None))
  assert_eq(s.prune(r5), record([], None))
}

///|
test "rows: two open rows share a fresh row" {
  let s = solver()
  let r1 = s.fresh(1, [])
  let r2 = s.fresh(2, [])
  s.unify(
    record([("a", int), ("c", char)], Some(r1)),
    record([("b", string), ("c", char)], Some(r2)),
  )
  guard s.prune(r1) is Rec(f1, Some(Meta(p1))) else { fail("r1 is a row") }
  guard s.prune(r2) is Rec(f2, Some(Meta(p2))) else { fail("r2 is a row") }
  assert_eq(f1.to_array(), [("b", string)])
  assert_eq(f2.to_array(), [("a", int)])
  assert_eq(p1, p2)
  assert_eq(state(s, Meta(p1)), (1, []))
  // Both records now have the same type.
  let whole = record([("a", int), ("b", string), ("c", char)], Some(Meta(p1)))
  assert_eq(s.prune(record([("a", int), ("c", char)], Some(r1))), whole)
}

///|
test "two open rows with the same tail and different fields give type_mismatch" {
  let s = solver()
  let r = s.fresh(1, [])
  assert_eq(
    code(() => {
      s.unify(record([("a", int)], Some(r)), record([("b", int)], Some(r)))
    }),
    "type_mismatch",
  )
  s.unify(record([("a", int)], Some(r)), record([("a", int)], Some(r)))
}

///|
test "rows: rigid tails" {
  let s = solver()
  let tail = Some(rigid("a"))
  s.unify(record([("x", int)], tail), record([("x", int)], tail))
  assert_eq(
    code(() => s.unify(record([], tail), record([("x", int)], None))),
    "rigid_variable",
  )
  let r = s.fresh(1, [])
  s.unify(record([("x", int)], tail), record([], Some(r)))
  assert_eq(s.prune(r), record([("x", int)], tail))
  assert_eq(
    code(() => s.unify(record([], tail), record([], Some(rigid("b"))))),
    "rigid_variable",
  )
}

///|
test "prune flattens record tails" {
  let s = solver()
  let r1 = s.fresh(1, [])
  let r2 = s.fresh(1, [])
  s.unify(r1, record([("b", int)], Some(r2)))
  assert_eq(
    s.prune(record([("a", string)], Some(r1))),
    record([("a", string), ("b", int)], Some(r2)),
  )
  s.unify(r2, record([("c", char)], None))
  assert_eq(
    s.prune(record([("a", string)], Some(r1))),
    record([("a", string), ("b", int), ("c", char)], None),
  )
}

///|
test "a record with no fields and an open tail is its tail" {
  let s = solver()
  assert_eq(s.prune(record([], Some(rigid("a")))), rigid("a"))
  s.unify(record([], Some(rigid("a"))), rigid("a"))
  let r = s.fresh(1, [])
  assert_eq(s.prune(record([], Some(r))), r)
}

///|
test "metas refuse records under a class" {
  assert_eq(instance("appendable", record([("x", int)], None)), "no_instance")
}

///|
test "aliases expand during unification" {
  let s = Solver::new(fn(name, args) {
    if name == "acme/app:orders#amount" && args.is_empty() {
      Some(Con("morphir/SDK:basics#int", []))
    } else {
      None
    }
  })
  s.unify(Con("acme/app:orders#amount", []), int)
  assert_eq(
    code(() => s.unify(Con("acme/app:orders#amount", []), string)),
    "type_mismatch",
  )
}

///|
test "aliases expand on either side, against any type and under a class" {
  let s = Solver::new(fn(name, args) {
    match (name, args) {
      ("acme/app:orders#amount", []) => Some(int)
      ("acme/app:orders#pair", [a]) => Some(Tup([a, a]))
      ("acme/app:orders#pred", [a]) => Some(Fun(a, string))
      _ => None
    }
  })
  s.unify(int, Con("acme/app:orders#amount", []))
  let m = s.fresh(1, [])
  s.unify(Con("acme/app:orders#pred", [int]), Fun(m, string))
  assert_eq(s.prune(m), int)
  s.unify(Tup([string, string]), Con("acme/app:orders#pair", [string]))
  s.unify(s.fresh(1, ["number"]), Con("acme/app:orders#amount", []))
  s.unify(s.fresh(1, ["comparable"]), Con("acme/app:orders#pair", [int]))
  assert_eq(
    code(() => s.unify(Con("acme/app:orders#pred", [int]), int)),
    "type_mismatch",
  )
  // A nominal type that does not expand is not an instance.
  assert_eq(
    code(() => s.unify(s.fresh(1, ["number"]), Con("acme/app:orders#id", []))),
    "no_instance",
  )
}

///|
test "problems compare structurally" {
  let p = InferenceProblem::{
    code: "type_mismatch",
    node: "acme/app:orders#total",
    message: "expected Int, found String",
    expected: None,
    found: None,
    source: None,
  }
  let e : Error = InferenceFailed([p])
  guard e is InferenceFailed(problems) else { fail("not an inference failure") }
  assert_eq(problems, [p])
  assert_true(InferenceFailed([p]) == InferenceFailed([p]))
}

///|
test "an unknown class has no instance" {
  for t in [int, float, char, string, list(int), Tup([int, string])] {
    assert_eq(instance("orderable", t), "no_instance")
  }
}

///|
/// A solver with `Token a = Int`, which ignores its parameter, `Twice a = List a`, which keeps it, and the
/// nominal `Box a`.
fn alias_solver() -> Solver {
  Solver::new(fn(name, args) {
    match (name, args) {
      ("acme/app:m#token", [_]) => Some(int)
      ("acme/app:m#twice", [a]) => Some(list(a))
      _ => None
    }
  })
}

///|
fn token(t : Ty) -> Ty {
  Con("acme/app:m#token", [t])
}

///|
test "non-injective aliases: the same alias expands instead of comparing arguments" {
  let s = alias_solver()
  s.unify(token(string), token(Con(BOOL, [])))
  s.unify(token(string), int)
  s.unify(int, token(string))
  // The argument of an alias that ignores it stays unconstrained.
  let m = s.fresh(1, [])
  s.unify(token(m), token(string))
  s.unify(token(m), token(int))
  assert_true(s.prune(m) is Meta(_))
  // An alias that keeps its argument still compares it, through the expansion.
  assert_eq(
    code(() => {
      s.unify(Con("acme/app:m#twice", [string]), Con("acme/app:m#twice", [int]))
    }),
    "type_mismatch",
  )
  // A nominal type keeps the argument comparison.
  assert_eq(
    code(() => {
      s.unify(
        Con("acme/app:m#box", [string]),
        Con("acme/app:m#box", [Con(BOOL, [])]),
      )
    }),
    "type_mismatch",
  )
}

///|
test "non-injective aliases: the occurs check looks through an alias that drops the meta" {
  let s = alias_solver()
  let a = s.fresh(1, [])
  s.unify(a, token(a))
  assert_eq(s.prune(a), int)
  let b = s.fresh(1, [])
  s.unify(list(token(b)), b)
  assert_eq(s.prune(b), list(int))
  // An alias that keeps the meta is still infinite.
  let c = s.fresh(1, [])
  assert_eq(code(() => s.unify(c, Con("acme/app:m#twice", [c]))), "occurs")
  // A nominal type is not expanded.
  let d = s.fresh(1, [])
  assert_eq(code(() => s.unify(d, Con("acme/app:m#box", [d]))), "occurs")
}

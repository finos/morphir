///|
fn Solver::new(expand : (String, Array[Ty]) -> Ty?) -> Solver {
  { metas: [], expand, }
}

///|
/// A new unbound meta at `level` with the class set `classes`.
fn Solver::fresh(self : Solver, level : Int32, classes : Array[String]) -> Ty {
  let id = self.metas.length()
  self.metas.push(Unbound(level~, classes~))
  Meta(id)
}

///|
/// Follows meta links. A record whose tail is solved to a record is flattened into one record, and a record
/// with no fields and an open tail is the tail.
fn Solver::prune(self : Solver, t : Ty) -> Ty {
  match t {
    Meta(id) =>
      match self.metas[id] {
        Link(target) => {
          let pruned = self.prune(target)
          self.metas[id] = Link(pruned)
          pruned
        }
        Unbound(..) => t
      }
    Rec(fields, Some(tail)) =>
      match self.prune(tail) {
        Rec(more, rest) => {
          let merged = fields.copy()
          for name, field in more {
            if !merged.contains(name) {
              merged[name] = field
            }
          }
          match rest {
            Some(tail) => row(merged, tail)
            None => Rec(merged, None)
          }
        }
        pruned => row(fields, pruned)
      }
    _ => t
  }
}

///|
/// Whether the meta `id` occurs in `t`.
fn Solver::occurs(self : Solver, id : Int32, t : Ty) -> Bool {
  match self.prune(t) {
    Meta(other) => other == id
    Con(_, items) | Tup(items) => items.iter().any(fn(x) { self.occurs(id, x) })
    Fun(input, output) => self.occurs(id, input) || self.occurs(id, output)
    Rec(fields, tail) =>
      fields.values().any(fn(x) { self.occurs(id, x) }) ||
      (tail is Some(row) && self.occurs(id, row))
    Rigid(_, _) | Gen(_) | UnitTy => false
  }
}

///|
/// Lowers the level of every unbound meta in `t` to at most `level`.
fn Solver::adjust_levels(self : Solver, level : Int32, t : Ty) -> Unit {
  match self.prune(t) {
    Meta(id) =>
      if self.metas[id] is Unbound(level=own, classes~) && own > level {
        self.metas[id] = Unbound(level~, classes~)
      }
    Con(_, items) | Tup(items) =>
      items.each(fn(x) { self.adjust_levels(level, x) })
    Fun(input, output) => {
      self.adjust_levels(level, input)
      self.adjust_levels(level, output)
    }
    Rec(fields, tail) => {
      fields.values().each(fn(x) { self.adjust_levels(level, x) })
      if tail is Some(row) {
        self.adjust_levels(level, row)
      }
    }
    Rigid(_, _) | Gen(_) | UnitTy => ()
  }
}

///|
/// Unifies `expected` with `found`.
fn Solver::unify(
  self : Solver,
  expected : Ty,
  found : Ty,
) -> Unit raise Mismatch {
  let e = self.prune(expected)
  let f = self.prune(found)
  match (e, f) {
    (Meta(a), Meta(b)) => self.merge(a, b, e, f)
    (Meta(a), _) => self.bind(a, f, e, f)
    (_, Meta(b)) => self.bind(b, e, e, f)
    (Rigid(a, _), Rigid(b, _)) if a == b => ()
    (Gen(a), Gen(b)) if a == b => ()
    (Con(n1, a1), Con(n2, a2)) if n1 == n2 => {
      // An alias may ignore a parameter, as `Token a = Int`, so equal alias names do not mean equal
      // arguments. Expand both sides; only nominal types compare their arguments.
      if (self.expand)(n1, a1) is Some(x1) && (self.expand)(n2, a2) is Some(x2) {
        return self.unify(x1, x2)
      }
      if a1.length() != a2.length() {
        raise Mismatch("type_mismatch", e, f)
      }
      for i, x in a1 {
        self.unify(x, a2[i])
      }
    }
    (Fun(a1, r1), Fun(a2, r2)) => {
      self.unify(a1, a2)
      self.unify(r1, r2)
    }
    (Tup(x1), Tup(x2)) if x1.length() == x2.length() =>
      for i, x in x1 {
        self.unify(x, x2[i])
      }
    (UnitTy, UnitTy) => ()
    (Rec(f1, t1), Rec(f2, t2)) => self.unify_rows(f1, t1, f2, t2, e, f)
    _ => self.unify_expanded(e, f)
  }
}

///|
/// Links two different metas. The classes join and the lower level wins.
fn Solver::merge(
  self : Solver,
  a : Int32,
  b : Int32,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  if a == b {
    return
  }
  guard self.metas[a] is Unbound(level=la, classes=ca) &&
    self.metas[b] is Unbound(level=lb, classes=cb) else {
    abort("merge: metas must be unbound after pruning")
  }
  guard join(ca, cb) is Some(classes) else {
    raise Mismatch("no_instance", e, f)
  }
  self.metas[b] = Unbound(level=if la < lb { la } else { lb }, classes~)
  self.metas[a] = Link(Meta(b))
}

///|
/// Binds the meta `id` to the non-meta type `t`. When `id` occurs in `t`, the aliases of `t` are expanded first,
/// and `id` is bound to the expansion if it no longer occurs there.
fn Solver::bind(
  self : Solver,
  id : Int32,
  t : Ty,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  let t = if self.occurs(id, t) {
    // The meta may occur only under alias arguments that the expansion drops, as in `a ~ Token a` with
    // `Token a = Int`.
    let expanded = self.expand_all(t)
    if self.occurs(id, expanded) {
      raise Mismatch("occurs", e, f)
    }
    expanded
  } else {
    t
  }
  guard self.metas[id] is Unbound(level~, classes~) else {
    abort("bind: meta must be unbound after pruning")
  }
  self.adjust_levels(level, t)
  if self.satisfies(classes, t) is Some(code) {
    raise Mismatch(code, e, f)
  }
  self.metas[id] = Link(t)
}

///|
/// `t` with every alias expanded, at every depth. Cyclic aliases do not expand, so this ends.
fn Solver::expand_all(self : Solver, t : Ty) -> Ty {
  match self.prune(t) {
    Con(name, args) =>
      match (self.expand)(name, args) {
        Some(expanded) => self.expand_all(expanded)
        None => Con(name, args.map(a => self.expand_all(a)))
      }
    Fun(input, output) => Fun(self.expand_all(input), self.expand_all(output))
    Tup(items) => Tup(items.map(a => self.expand_all(a)))
    Rec(fields, tail) => {
      let out : Map[String, Ty] = Map([])
      for name, field in fields {
        out[name] = self.expand_all(field)
      }
      Rec(out, tail)
    }
    pruned => pruned
  }
}

///|
/// The fallback when the shapes differ: expand an alias on either side and retry, else fail.
fn Solver::unify_expanded(self : Solver, e : Ty, f : Ty) -> Unit raise Mismatch {
  if e is Con(name, args) && (self.expand)(name, args) is Some(expanded) {
    return self.unify(expanded, f)
  }
  if f is Con(name, args) && (self.expand)(name, args) is Some(expanded) {
    return self.unify(e, expanded)
  }
  let code = if e is Rigid(_, _) || f is Rigid(_, _) {
    "rigid_variable"
  } else {
    "type_mismatch"
  }
  raise Mismatch(code, e, f)
}

///|
/// Unifies two records through their rows. `t1` and `t2` are pruned tails.
fn Solver::unify_rows(
  self : Solver,
  f1 : Map[String, Ty],
  t1 : Ty?,
  f2 : Map[String, Ty],
  t2 : Ty?,
  e : Ty,
  f : Ty,
) -> Unit raise Mismatch {
  let only1 = without(f1, f2)
  let only2 = without(f2, f1)
  match (t1, t2) {
    (None, None) =>
      if !only1.is_empty() || !only2.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
    (Some(r1), None) => {
      if !only1.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
      self.unify(r1, Rec(only2, None))
    }
    (None, Some(r2)) => {
      if !only2.is_empty() {
        raise Mismatch("missing_field", e, f)
      }
      self.unify(Rec(only1, None), r2)
    }
    (Some(r1), Some(r2)) =>
      if r1 == r2 {
        if !only1.is_empty() || !only2.is_empty() {
          raise Mismatch("type_mismatch", e, f)
        }
      } else {
        let rho = self.fresh(self.row_level(r1, r2), [])
        self.unify(r1, row(only2, rho))
        self.unify(row(only1, rho), r2)
      }
  }
  for name, field in f1 {
    if f2.get(name) is Some(other) {
      self.unify(field, other)
    }
  }
}

///|
/// The fields of `a` whose names are not in `b`, in the order of `a`.
fn without(a : Map[String, Ty], b : Map[String, Ty]) -> Map[String, Ty] {
  let out : Map[String, Ty] = Map([])
  for name, field in a {
    if !b.contains(name) {
      out[name] = field
    }
  }
  out
}

///|
/// A record of `fields` with the open tail `tail`. With no fields it is the tail itself.
fn row(fields : Map[String, Ty], tail : Ty) -> Ty {
  if fields.is_empty() {
    tail
  } else {
    Rec(fields, Some(tail))
  }
}

///|
/// The level for a fresh row between two tails: the lower level of the tails that are metas.
fn Solver::row_level(self : Solver, r1 : Ty, r2 : Ty) -> Int32 {
  let levels = [r1, r2].filter_map(fn(r) {
    match r {
      Meta(id) =>
        match self.metas[id] {
          Unbound(level~, ..) => Some(level)
          Link(_) => None
        }
      _ => None
    }
  })
  match levels {
    [] => 0
    [level] => level
    [a, b, ..] => if a < b { a } else { b }
  }
}

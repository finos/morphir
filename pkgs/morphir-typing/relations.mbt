///|
pub(all) enum RelationReason {
  UnresolvedVariable
  UnsupportedConstraint
  UnsupportedExtension
  CyclicAlias
  LimitExceeded
  UnsupportedShape
} derive(Eq, Debug)

///|
pub(all) enum TypeRelation {
  Proven
  Refuted
  Unknown(RelationReason)
} derive(Eq, Debug)

///|
pub extend TypeRelation with Eq::{equal, not_equal}

///|
pub extend TypeRelation with @debug.Debug::{to_repr}

///|
pub extend RelationReason with Eq::{equal, not_equal}

///|
pub extend RelationReason with @debug.Debug::{to_repr}

///|
/// Semantic relations share inference's alias visibility and nominal identities.
/// The bounded proof checks at most 4096 pairs and 128 nested levels.
pub struct TypeContext {
  priv env : Env
}

///|
pub fn TypeContext::from(
  file : @ir.IRFile,
  deps : Map[@ir.PackageName, @ir.PackageSpecification],
) -> TypeContext {
  { env: Env::from(deps, file), }
}

///|
pub fn TypeContext::assignable(
  self : TypeContext,
  source : @ir.Type,
  destination : @ir.Type,
) -> TypeRelation {
  let pending = [source, destination]
  let seen : Map[String, Bool] = Map([])
  let mut visits = 0
  while pending.pop() is Some(t) {
    visits += 1
    if visits > 4096 {
      return Unknown(LimitExceeded)
    }
    if self.env.unresolved([t]) is Some(_) {
      return Unknown(UnsupportedShape)
    }
    for name in t.references() {
      let key = name.to_canonical()
      if self.env.cyclic_aliases.contains(key) {
        return Unknown(CyclicAlias)
      }
      if !seen.contains(key) {
        seen[key] = true
        if self.env.types.get(key) is Some(Alias(_, body)) {
          pending.push(body)
        }
      }
    }
  }
  let solver = Solver::new((n, xs) => self.env.expand(n, xs))
  let vars = (n, a) => Rigid(n, classes_of(n, a))
  solver.assignable(to_ty(source, vars), to_ty(destination, vars))
}

///|
/// Scoped variable names are identities here. Use TypeScope for alpha-renaming.
pub fn TypeContext::equivalent(
  self : TypeContext,
  left : @ir.Type,
  right : @ir.Type,
) -> TypeRelation {
  relation_all([self.assignable(left, right), self.assignable(right, left)])
}

///|
fn relation_all(xs : Array[TypeRelation]) -> TypeRelation {
  let mut result = Proven
  for x in xs {
    match x {
      Refuted => return Refuted
      Unknown(_) => result = x
      Proven => ()
    }
  }
  result
}

///|
fn relation_any(xs : Array[TypeRelation]) -> TypeRelation {
  let mut result = Refuted
  for x in xs {
    match x {
      Proven => return Proven
      Unknown(_) => result = x
      Refuted => ()
    }
  }
  result
}

///|
/// Follow links without path compression or speculative solver mutations.
fn Solver::peek(self : Solver, t : Ty) -> Ty {
  match t {
    Meta(i) =>
      match self.metas[i] {
        Link(t) => self.peek(t)
        _ => t
      }
    _ => t
  }
}

///|
fn Solver::assignable(self : Solver, source : Ty, target : Ty) -> TypeRelation {
  self.relate(source, target, { val: 4096, }, 0)
}

///|
/// Keep alias-site and body attributes as separate conjunctions.
fn Solver::relation_head(
  self : Solver,
  t : Ty,
  budget : Ref[Int32],
  depth : Int32,
) -> (Ty, Array[@ir.TypeAttributes])? {
  if budget.val <= 0 || depth > 128 {
    return None
  }
  budget.val -= 1
  match self.peek(t) {
    Attributed(a, inner) =>
      match self.relation_head(inner, budget, depth + 1) {
        Some((body, attrs)) => Some((body, [a, ..attrs]))
        None => None
      }
    Con(n, xs) as body =>
      match (self.expand)(n, xs) {
        Some(inner) => self.relation_head(inner, budget, depth + 1)
        None => Some((body, []))
      }
    t => Some((t, []))
  }
}

///|
fn attributed_all(t : Ty, attrs : Array[@ir.TypeAttributes]) -> Ty {
  attrs.fold(init=t, (t, a) => Attributed(a, t))
}

///|
fn attributes_entail(
  source : Array[@ir.TypeAttributes],
  target : Array[@ir.TypeAttributes],
) -> TypeRelation {
  for a in target {
    let a = obligations(a)
    for k, v in a.constraints {
      if !source.any(s => s.constraints.get(k) == Some(v)) {
        return Unknown(UnsupportedConstraint)
      }
    }
    for k, v in a.extensions {
      if !source.any(s => s.extensions.get(k) == Some(v)) {
        return Unknown(UnsupportedExtension)
      }
    }
  }
  Proven
}

///|
fn Solver::relate(
  self : Solver,
  source : Ty,
  target : Ty,
  budget : Ref[Int32],
  depth : Int32,
) -> TypeRelation {
  if budget.val <= 0 || depth > 128 {
    return Unknown(LimitExceeded)
  }
  budget.val -= 1
  guard self.relation_head(source, budget, depth) is Some((s, sa)) &&
    self.relation_head(target, budget, depth) is Some((t, ta)) else {
    return Unknown(LimitExceeded)
  }
  if s is Union(xs) {
    if xs.length() < 2 {
      return Unknown(UnsupportedShape)
    }
    return relation_all(
      xs.map(x => self.relate(attributed_all(x, sa), target, budget, depth + 1)),
    )
  }
  if t is Union(xs) {
    if xs.length() < 2 {
      return Unknown(UnsupportedShape)
    }
    return relation_any(
      xs.map(x => self.relate(source, attributed_all(x, ta), budget, depth + 1)),
    )
  }
  let attrs = attributes_entail(sa, ta)
  if attrs != Proven {
    return attrs
  }
  if s == t {
    return Proven
  }
  let go = (x, y) => self.relate(x, y, budget, depth + 1)
  match (s, t) {
    (Meta(_), _) | (_, Meta(_)) | (Gen(_), _) | (_, Gen(_)) =>
      Unknown(UnresolvedVariable)
    (Rigid(_, _), _) | (_, Rigid(_, _)) => Unknown(UnresolvedVariable)
    (Con(n, xs), Con(m, ys)) if n == m && xs.length() == ys.length() =>
      relation_all(
        xs.mapi((i, x) => relation_all([go(x, ys[i]), go(ys[i], x)])),
      )
    (Tup(xs), Tup(ys)) if xs.length() == ys.length() =>
      relation_all(xs.mapi((i, x) => go(x, ys[i])))
    (Rec(xs, None), Rec(ys, None)) if xs.length() == ys.length() => {
      let checks = []
      for n, x in xs {
        guard ys.get(n) is Some(y) else { return Refuted }
        checks.push(go(x, y))
      }
      relation_all(checks)
    }
    (Rec(_, Some(_)), _) | (_, Rec(_, Some(_))) => Unknown(UnsupportedShape)
    (Fun(a, b), Fun(c, d)) => relation_all([go(c, a), go(b, d)])
    _ => Refuted
  }
}

///|
fn Solver::semantic_boundary(self : Solver, t : Ty, depth~ : Int32 = 0) -> Bool {
  if depth > 128 {
    return true
  }
  match self.peek(t) {
    Union(_) => true
    Attributed(a, t) =>
      obligations(a) != @ir.TypeAttributes::default() ||
      self.semantic_boundary(t, depth=depth + 1)
    Con(n, xs) =>
      match (self.expand)(n, xs) {
        Some(t) => self.semantic_boundary(t, depth=depth + 1)
        None => xs.any(t => self.semantic_boundary(t, depth=depth + 1))
      }
    Tup(xs) => xs.any(t => self.semantic_boundary(t, depth=depth + 1))
    Fun(x, y) =>
      self.semantic_boundary(x, depth=depth + 1) ||
      self.semantic_boundary(y, depth=depth + 1)
    Rec(fs, tail) =>
      fs.values().any(t => self.semantic_boundary(t, depth=depth + 1)) ||
      (tail is Some(t) && self.semantic_boundary(t, depth=depth + 1))
    _ => false
  }
}

///|
fn Infer::check_type(
  self : Infer,
  path : String,
  expected : Ty,
  found : Ty,
) -> Unit raise Located {
  if self.solver.peek(expected) is Meta(_) {
    return self.unify(path, expected, found)
  }
  if !self.solver.semantic_boundary(expected) &&
    !self.solver.semantic_boundary(found) {
    return self.unify(path, expected, found)
  }
  let budget : Ref[Int32] = { val: 4096, }
  if self.solver.relation_head(expected, budget, 0) is Some((e, ea)) &&
    self.solver.relation_head(found, budget, 0) is Some((f, fa)) &&
    attributes_entail(fa, ea) == Proven {
    match (e, f) {
      (Tup(xs), Tup(ys)) if xs.length() == ys.length() => {
        for i, x in xs {
          self.check_type(path, x, ys[i])
        }
        return
      }
      (Rec(xs, None), Rec(ys, None)) if xs.length() == ys.length() => {
        for n, x in xs {
          guard ys.get(n) is Some(y) else {
            raise MismatchAt(path, Mismatch("type_mismatch", expected, found))
          }
          self.check_type(path, x, y)
        }
        return
      }
      (Con(n, xs), Con(m, ys)) if n == m && xs.length() == ys.length() => {
        for i, x in xs {
          self.unify(path, x, ys[i])
        }
        return
      }
      (Fun(a, b), Fun(c, d)) => {
        self.check_type(path, c, a)
        self.check_type(path, b, d)
        return
      }
      _ => ()
    }
  }
  match self.solver.assignable(found, expected) {
    Proven => ()
    Refuted =>
      raise MismatchAt(path, Mismatch("type_mismatch", expected, found))
    Unknown(_) =>
      raise UnknownAt(
        path,
        Unknown(
          "unsupported", "Union checking requires concrete type evidence or supported obligations",
        ),
      )
  }
}

///|
fn Infer::check_value(
  self : Infer,
  v : @ir.Value,
  expected : Ty,
  path : String,
) -> Ty raise Located {
  let finish = (t : Ty) => {
    self.fact(value_attributes(v).inferred_type, t, path)
    self.types[path] = t
    t
  }
  if self.solver.semantic_boundary(expected) && v is IfThenElse(_, c, yes, no) {
    self.unify(
      path,
      Con(BOOL, []),
      self.value(c, @identities.path_condition(path)),
    )
    ignore(self.check_value(yes, expected, @identities.path_then(path)))
    ignore(self.check_value(no, expected, @identities.path_else(path)))
    self.fact(value_attributes(v).inferred_type, expected, path)
    self.types[path] = expected
    return expected
  }
  if self.solver.semantic_boundary(expected) {
    let continuation = match v {
      LetDefinition(_, name, def, rest) =>
        Some(self.value_let(name, def, rest, path, expected=Some(expected)))
      LetRecursion(_, defs, rest) =>
        Some(
          self.value_let_recursion(defs, rest, path, expected=Some(expected)),
        )
      Destructure(_, pattern, value, rest) =>
        Some(
          self.value_destructure(
            pattern,
            value,
            rest,
            path,
            expected=Some(expected),
          ),
        )
      _ => None
    }
    if continuation is Some(t) {
      return finish(t)
    }
    if v is PatternMatch(_, subject, cases) {
      let st = self.value(subject, @identities.path_subject(path))
      for i, pair in cases {
        self.scoped(() => {
          let pt = self.pattern(pair.0, @identities.path_case_pattern(path, i))
          self.unify(@identities.path_case_pattern(path, i), st, pt)
          ignore(
            self.check_value(
              pair.1,
              expected,
              @identities.path_case_body(path, i),
            ),
          )
        })
      }
      return finish(expected)
    }
    if self.solver.relation_head(expected, { val: 4096, }, 0)
      is Some((shape, attributes)) &&
      attributes_entail([], attributes) == Proven {
      match (v, shape) {
        (List(_, values), Con(LIST, [element])) => {
          for i, value in values {
            ignore(
              self.check_value(value, element, @identities.path_item(path, i)),
            )
          }
          return finish(expected)
        }
        (Tuple(_, values), Tup(types)) if values.length() == types.length() => {
          for i, value in values {
            ignore(
              self.check_value(value, types[i], @identities.path_item(path, i)),
            )
          }
          return finish(expected)
        }
        (Record(_, values), Rec(types, None)) if values.length() ==
          types.length() => {
          for name, value in values {
            guard types.get(name.to_canonical()) is Some(t) else {
              raise MismatchAt(
                path,
                Mismatch("type_mismatch", expected, UnitTy),
              )
            }
            ignore(
              self.check_value(value, t, @identities.path_field(path, name)),
            )
          }
          return finish(expected)
        }
        (Lambda(_, pattern, body), Fun(parameter, result)) => {
          self.scoped(() => {
            let pt = self.pattern(pattern, @identities.path_pattern(path))
            self.unify(@identities.path_pattern(path), parameter, pt)
            ignore(self.check_value(body, result, @identities.path_body(path)))
          })
          return finish(expected)
        }
        _ => ()
      }
    }
  }
  let found = self.value(v, path)
  self.check_type(path, expected, found)
  found
}

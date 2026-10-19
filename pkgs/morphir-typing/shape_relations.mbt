///|
fn copy_renaming(r : Renaming) -> Renaming {
  { ..r, ab: r.ab.copy(), ba: r.ba.copy(), }
}

///|
/// Attribute-ignoring legacy shape view. Never use this as refinement evidence.
fn shape_members(t : @ir.Type, depth~ : Int32 = 0) -> Array[@ir.Type] {
  if depth > 128 {
    return [t]
  }
  match t {
    Union(_, xs) => {
      let out = []
      for t in xs {
        out.append(shape_members(t, depth=depth + 1))
      }
      out
    }
    _ => [t]
  }
}

///|
/// Every surviving bijection is retained across the remaining tree and later scope checks.
fn shape_candidates(
  pairs : Array[(@ir.Type, @ir.Type)],
  initial : Array[Renaming],
  budget : Ref[Int32],
  depth : Int32,
) -> Array[Renaming] {
  if depth > 128 || budget.val <= 0 {
    return []
  }
  let mut states = initial
  for (a, b) in pairs {
    let next = []
    for state in states {
      budget.val -= 1
      if budget.val <= 0 {
        return []
      }
      next.append(shape_pair(a, b, state, budget, depth + 1))
      if next.length() > 256 {
        return []
      }
    }
    states = next
    if states.is_empty() {
      return []
    }
  }
  states
}

///|
fn shape_coverage(
  xs : Array[@ir.Type],
  ys : Array[@ir.Type],
  states : Array[Renaming],
  budget : Ref[Int32],
  depth : Int32,
  reverse : Bool,
) -> Array[Renaming] {
  let mut states = states
  for x in xs {
    let next = []
    for state in states {
      for y in ys {
        let pair = if reverse { (y, x) } else { (x, y) }
        next.append(shape_candidates([pair], [state], budget, depth + 1))
        if next.length() > 256 {
          return []
        }
      }
    }
    states = next
  }
  states
}

///|
fn shape_pair(
  a : @ir.Type,
  b : @ir.Type,
  state : Renaming,
  budget : Ref[Int32],
  depth : Int32,
) -> Array[Renaming] {
  if depth > 128 || budget.val <= 0 {
    return []
  }
  if a is Union(_, _) || b is Union(_, _) {
    let xs = shape_members(a)
    let ys = shape_members(b)
    let states = shape_coverage(xs, ys, [state], budget, depth, false)
    return shape_coverage(ys, xs, states, budget, depth, true)
  }
  let r = copy_renaming(state)
  let arrays = (xs : Array[@ir.Type], ys : Array[@ir.Type]) => {
    if xs.length() != ys.length() {
      []
    } else {
      shape_candidates(xs.mapi((i, x) => (x, ys[i])), [r], budget, depth + 1)
    }
  }
  let fields = (xs : Map[@ir.Name, @ir.Type], ys : Map[@ir.Name, @ir.Type]) => {
    if xs.length() != ys.length() {
      return []
    }
    let pairs = []
    let names = xs.keys().collect()
    names.sort()
    for n in names {
      guard ys.get(n) is Some(y) else { return [] }
      pairs.push((xs[n], y))
    }
    shape_candidates(pairs, [r], budget, depth + 1)
  }
  match (a, b) {
    (Variable(c, x), Variable(d, y)) =>
      if same_variable(x, c, y, d, r) {
        [r]
      } else {
        []
      }
    (Reference(_, n, xs), Reference(_, m, ys)) if n == m => arrays(xs, ys)
    (Tuple(_, []) | Unit(_), Tuple(_, []) | Unit(_)) => [r]
    (Tuple(_, xs), Tuple(_, ys)) => arrays(xs, ys)
    (Function(_, a, b), Function(_, c, d)) =>
      shape_candidates([(a, c), (b, d)], [r], budget, depth + 1)
    (Record(_, xs), Record(_, ys)) => fields(xs, ys)
    (ExtensibleRecord(a, x, xs), ExtensibleRecord(b, y, ys)) =>
      if same_variable(x, a, y, b, r) {
        fields(xs, ys)
      } else {
        []
      }
    _ => []
  }
}

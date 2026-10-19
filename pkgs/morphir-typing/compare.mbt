///|
/// Whether `a` and `b` are the same type after a bijective renaming of their variables. Attributes do not count,
/// and a tuple of no items is the unit type. A record row variable is a variable.
///
/// This compares one pair of types alone. To compare the types of one declaration, use `TypeScope`.
pub fn types_equivalent(a : @ir.Type, b : @ir.Type) -> Bool {
  !shape_candidates(
    [(a, b)],
    [{ ab: Map([]), ba: Map([]), classes: false, }],
    { val: 4096, },
    0,
  ).is_empty()
}

///|
/// The renaming of type variables that the types of one declaration share. Inference names the variables of
/// one declaration consistently, so every type of the declaration is compared under one bijection:
///
/// - the variables of the declaration's signature (those without the unknown marker) map to themselves;
/// - any other variable pairs with one variable, and the pair holds for every later type;
/// - two paired variables have the same class set, from the `typeclass` constraint or the name prefix.
pub struct TypeScope {
  priv mut candidates : Array[Renaming]
}

///|
/// The scope of the declaration `def`, with its signature variables mapped to themselves.
pub fn TypeScope::of_definition(def : @ir.ValueDefinition) -> TypeScope {
  let renaming : Renaming = { ab: Map([]), ba: Map([]), classes: true, }
  for name in rigid_names(def) {
    renaming.ab[name] = name
    renaming.ba[name] = name
  }
  { candidates: [renaming], }
}

///|
/// Whether `a`, a type of the declaration, is equivalent to `b` in this scope. When they are, the new variable
/// pairs are kept. When they are not, the scope does not change.
pub fn TypeScope::equivalent(
  self : TypeScope,
  a : @ir.Type,
  b : @ir.Type,
) -> Bool {
  let candidates = shape_candidates(
    [(a, b)],
    self.candidates,
    { val: 4096, },
    0,
  )
  guard !candidates.is_empty() else { return false }
  self.candidates = candidates
  true
}

///|
/// A bijection between the variables of two sides. `ab` maps the variables of `a` to those of `b`, and `ba` is
/// its inverse. With `classes`, paired variables must have the same class set.
priv struct Renaming {
  ab : Map[String, String]
  ba : Map[String, String]
  classes : Bool
}

///|
/// Pairs the variable `x` of `a` with the variable `y` of `b`, or checks the pair made before. `c1` and `c2` are
/// the attributes of the variables (of the record, for a row variable).
fn same_variable(
  x : @ir.Name,
  c1 : @ir.TypeAttributes,
  y : @ir.Name,
  c2 : @ir.TypeAttributes,
  r : Renaming,
) -> Bool {
  let x = x.to_canonical()
  let y = y.to_canonical()
  if r.classes && classes_of(x, c1) != classes_of(y, c2) {
    return false
  }
  let ab = r.ab
  let ba = r.ba
  match (ab.get(x), ba.get(y)) {
    (None, None) => {
      ab[x] = y
      ba[y] = x
      true
    }
    (Some(y2), Some(x2)) => y2 == y && x2 == x
    _ => false
  }
}

///|
/// Alias expansion for legacy attribute-ignoring shape comparisons only.
/// This discards occurrence attributes when substituting; semantic proofs use Env::expand instead.
/// A cyclic alias and an alias with the wrong arity stay as references.
fn Env::expand_shape(self : Env, t : @ir.Type) -> @ir.Type {
  match t {
    Reference(attrs, name, args) => {
      let args = args.map(a => self.expand_shape(a))
      let key = name.to_canonical()
      match self.types.get(key) {
        Some(Alias(params, body)) if !self.cyclic_aliases.contains(key) &&
          params.length() == args.length() => {
          let bound : Map[String, @ir.Type] = Map([])
          for i, p in params {
            bound[p] = args[i]
          }
          self.expand_shape(substitute_shape(body, bound))
        }
        _ => Reference(attrs, name, args)
      }
    }
    Tuple(attrs, items) => Tuple(attrs, items.map(a => self.expand_shape(a)))
    Union(attrs, items) => Union(attrs, items.map(a => self.expand_shape(a)))
    Record(attrs, fields) =>
      Record(attrs, map_fields(fields, a => self.expand_shape(a)))
    ExtensibleRecord(attrs, row, fields) =>
      ExtensibleRecord(
        attrs,
        row,
        map_fields(fields, a => self.expand_shape(a)),
      )
    Function(attrs, input, output) =>
      Function(attrs, self.expand_shape(input), self.expand_shape(output))
    Variable(_, _) | Unit(_) => t
  }
}

///|
/// `t` with each variable in `bound` replaced. A row variable is renamed when it is bound to a variable.
pub fn substitute_type(
  t : @ir.Type,
  bound : Map[String, @ir.Type],
) -> @ir.Type raise TypeSubstitutionError {
  let sub = (t : @ir.Type) => substitute_type(t, bound)
  let fields = (fs : Map[@ir.Name, @ir.Type]) => {
    let out = Map([])
    for n, t in fs {
      out[n] = sub(t)
    }
    out
  }
  match t {
    Variable(attrs, name) =>
      match bound.get(name.to_canonical()) {
        Some(arg) =>
          match merge_attributes(attrs, type_attributes(arg)) {
            Some(a) => with_attributes(arg, a)
            None => raise AttributeConflict
          }
        None => t
      }
    Reference(attrs, name, args) => Reference(attrs, name, args.map(sub))
    Tuple(attrs, items) => Tuple(attrs, items.map(sub))
    Union(attrs, items) => Union(attrs, items.map(sub))
    Record(attrs, fs) => Record(attrs, fields(fs))
    ExtensibleRecord(attrs, row, fs) => {
      let (attrs, row) = match bound.get(row.to_canonical()) {
        Some(Variable(a, other)) =>
          match merge_attributes(attrs, a) {
            Some(combined) => (combined, other)
            None => raise AttributeConflict
          }
        _ => (attrs, row)
      }
      ExtensibleRecord(attrs, row, fields(fs))
    }
    Function(attrs, input, output) => Function(attrs, sub(input), sub(output))
    Unit(_) => t
  }
}

///|
fn map_fields(
  fields : Map[@ir.Name, @ir.Type],
  f : (@ir.Type) -> @ir.Type,
) -> Map[@ir.Name, @ir.Type] {
  let out : Map[@ir.Name, @ir.Type] = Map([])
  for name, field in fields {
    out[name] = f(field)
  }
  out
}

///|
/// Substitution used only by legacy shape comparison; not a semantic or output transformation.
fn substitute_shape(t : @ir.Type, bound : Map[String, @ir.Type]) -> @ir.Type {
  match t {
    Variable(_, name) =>
      match bound.get(name.to_canonical()) {
        Some(arg) => arg
        None => t
      }
    Reference(attrs, name, args) =>
      Reference(attrs, name, args.map(a => substitute_shape(a, bound)))
    Tuple(attrs, items) =>
      Tuple(attrs, items.map(a => substitute_shape(a, bound)))
    Union(attrs, items) =>
      Union(attrs, items.map(a => substitute_shape(a, bound)))
    Record(attrs, fields) =>
      Record(attrs, map_fields(fields, a => substitute_shape(a, bound)))
    ExtensibleRecord(attrs, row, fields) => {
      let row = match bound.get(row.to_canonical()) {
        Some(Variable(_, other)) => other
        _ => row
      }
      ExtensibleRecord(
        attrs,
        row,
        map_fields(fields, a => substitute_shape(a, bound)),
      )
    }
    Function(attrs, input, output) =>
      Function(
        attrs,
        substitute_shape(input, bound),
        substitute_shape(output, bound),
      )
    Unit(_) => t
  }
}

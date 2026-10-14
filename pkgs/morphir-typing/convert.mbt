///|
const TYPECLASS = "typeclass"

///|
/// Whether a variable carries the unknown marker.
fn is_unknown(attrs : @ir.TypeAttributes) -> Bool {
  attrs.is_unknown()
}

///|
/// The class set of a variable: its `typeclass` constraint, else its name prefix.
fn classes_of(name : String, attrs : @ir.TypeAttributes) -> Array[String] {
  match attrs.constraints.get(TYPECLASS) {
    Some(Text(class)) => [class]
    _ => class_of_text(name)
  }
}

///|
/// Converts an IR type. `vars` gives the type of each variable, by canonical name, including the row variable
/// of an extensible record (with the record's attributes).
fn to_ty(t : @ir.Type, vars : (String, @ir.TypeAttributes) -> Ty) -> Ty {
  match t {
    Variable(attrs, name) => vars(name.to_canonical(), attrs)
    Reference(_, name, args) =>
      Con(name.to_canonical(), args.map(a => to_ty(a, vars)))
    Tuple(_, []) | Unit(_) => UnitTy
    Tuple(_, items) => Tup(items.map(a => to_ty(a, vars)))
    Record(_, fields) => Rec(fields_to_ty(fields, vars), None)
    ExtensibleRecord(attrs, row, fields) =>
      Rec(fields_to_ty(fields, vars), Some(vars(row.to_canonical(), attrs)))
    Function(_, input, output) => Fun(to_ty(input, vars), to_ty(output, vars))
  }
}

///|
fn fields_to_ty(
  fields : Map[@ir.Name, @ir.Type],
  vars : (String, @ir.TypeAttributes) -> Ty,
) -> Map[String, Ty] {
  let out : Map[String, Ty] = Map([])
  for name, field in fields {
    out[name.to_canonical()] = to_ty(field, vars)
  }
  out
}

///|
/// The curried function type of a signature: `inputs -> output`.
fn curry(inputs : Array[Ty], output : Ty) -> Ty {
  let mut t = output
  for i = inputs.length() - 1; i >= 0; i = i - 1 {
    t = Fun(inputs[i], t)
  }
  t
}

///|
/// The scheme of a declared signature. Every variable becomes a `Gen`, keyed by canonical name in first-seen
/// order, with its classes from `typeclass` or the name prefix.
fn poly_of_signature(
  inputs : Array[(@ir.Name, @ir.Type)],
  output : @ir.Type,
) -> Poly {
  let ids : Map[String, Int] = Map([])
  let gens : Array[Array[String]] = []
  let vars = fn(name : String, attrs : @ir.TypeAttributes) -> Ty {
    match ids.get(name) {
      Some(id) => Gen(id)
      None => {
        ids[name] = gens.length()
        gens.push(classes_of(name, attrs))
        Gen(gens.length() - 1)
      }
    }
  }
  let ins = inputs.map(input => to_ty(input.1, vars))
  let body = curry(ins, to_ty(output, vars))
  { gens, body, }
}

///|
/// Rebuilds `t` after pruning each node. `leaf` maps each `Meta`, `Rigid` and `Gen`.
fn Solver::rebuild(self : Solver, t : Ty, leaf : (Ty) -> Ty) -> Ty {
  match self.prune(t) {
    Meta(_) | Rigid(_, _) | Gen(_) as v => leaf(v)
    Con(name, args) => Con(name, args.map(a => self.rebuild(a, leaf)))
    Fun(input, output) =>
      Fun(self.rebuild(input, leaf), self.rebuild(output, leaf))
    Tup(items) => Tup(items.map(a => self.rebuild(a, leaf)))
    Rec(fields, tail) => {
      let out : Map[String, Ty] = Map([])
      for name, field in fields {
        out[name] = self.rebuild(field, leaf)
      }
      Rec(out, tail.map(r => self.rebuild(r, leaf)))
    }
    UnitTy => UnitTy
  }
}

///|
/// A new instance of `p`: each `Gen` becomes a fresh meta at `level` with the classes of the `Gen`.
fn Solver::instantiate(self : Solver, p : Poly, level : Int) -> Ty {
  if p.gens.is_empty() {
    return p.body
  }
  let metas = p.gens.map(classes => self.fresh(level, classes))
  self.rebuild(p.body, v => if v is Gen(i) { metas[i] } else { v })
}

///|
/// Quantifies every unbound meta whose level is greater than `level`, in first-seen order. It also quantifies
/// the rigid variables named in `rigids`. A let definition uses this for the variables that its own signature
/// declares.
fn Solver::generalize_with(
  self : Solver,
  t : Ty,
  level : Int,
  rigids : Array[String],
) -> Poly {
  let metas : Map[Int, Int] = Map([])
  let named : Map[String, Int] = Map([])
  let gens : Array[Array[String]] = []
  let body = self.rebuild(t, v => {
    match v {
      Meta(id) =>
        match (self.metas[id], metas.get(id)) {
          (_, Some(g)) => Gen(g)
          (Unbound(level=own, classes~), None) if own > level => {
            metas[id] = gens.length()
            gens.push(classes)
            Gen(gens.length() - 1)
          }
          _ => v
        }
      Rigid(name, classes) if rigids.contains(name) =>
        match named.get(name) {
          Some(g) => Gen(g)
          None => {
            named[name] = gens.length()
            gens.push(classes)
            Gen(gens.length() - 1)
          }
        }
      _ => v
    }
  })
  { gens, body, }
}

///|
/// The key of the rigid variable `name` that the declaration `owner` declares: `<owner>|<name>`. Inside
/// inference a signature rigid belongs to its declaration, so the `a` of one declaration is never the `a` of
/// another. An empty owner gives the name itself.
fn rigid_key(owner : String, name : String) -> String {
  if owner == "" {
    name
  } else {
    owner + "|" + name
  }
}

///|
/// The key of the `n`th let-annotation rigid whose scope key is `key`: `<key>#<n>`. Two annotations that use the
/// same name, such as two let-rec siblings, then declare two variables. `rigid_name` drops the `#<n>`.
fn let_rigid_key(key : String, n : Int) -> String {
  key + "#" + n.to_string()
}

///|
/// The scope key of a rigid key: the key without the `#<n>` of a let-annotation rigid.
fn scope_key(key : String) -> String {
  let start = match owner_end(key) {
    Some(i) => i + 1
    None => 0
  }
  for i = start; i < key.length(); i = i + 1 {
    if key.code_unit_at(i) == '#' {
      return key.unsafe_substring(start=0, end=i)
    }
  }
  key
}

///|
/// The position of the `|` that ends the owner of a rigid key, if the key has an owner. Names and FQNames do
/// not contain `|`.
fn owner_end(key : String) -> Int? {
  for i = key.length() - 1; i >= 0; i = i - 1 {
    if key.code_unit_at(i) == '|' {
      return Some(i)
    }
  }
  None
}

///|
/// The name of a rigid key without its owner and without the `#<n>` of a let-annotation rigid.
fn rigid_name(key : String) -> String {
  let base = scope_key(key)
  match owner_end(base) {
    Some(i) => base.unsafe_substring(start=i + 1, end=base.length())
    None => base
  }
}

///|
/// The owner of a rigid key, or `""`.
fn rigid_owner(key : String) -> String {
  match owner_end(key) {
    Some(i) => key.unsafe_substring(start=0, end=i)
    None => ""
  }
}

///|
/// Names the variables of internal types and converts the types to IR. One namer keeps the names it gives, so
/// that every type of one declaration uses the same names.
priv struct Namer {
  /// The declaration whose rigid variables keep their names. A rigid of another declaration is named like a
  /// meta. With `""`, every rigid keeps its name.
  owner : String
  /// The name of each meta. A `Gen(i)` is keyed `-1 - i`.
  names : Map[Int, String]
  /// The name of each rigid of another declaration, by key.
  foreign : Map[String, String]
  used : Map[String, Bool]
}

///|
fn Namer::new(owner? : String = "") -> Namer {
  { owner, names: Map([]), foreign: Map([]), used: Map([]), }
}

///|
/// Whether the rigid `key` keeps its own name in this namer.
fn Namer::owns(self : Namer, key : String) -> Bool {
  self.owner == "" || rigid_owner(key) == "" || rigid_owner(key) == self.owner
}

///|
/// Marks `name` as taken, for example by a rigid variable of the signature.
fn Namer::reserve(self : Namer, name : String) -> Unit {
  self.used[name] = true
}

///|
/// The first free name `<prefix>a`, `<prefix>b`, …, `<prefix>z`, `<prefix>a1`, ….
fn Namer::next(self : Namer, prefix : String) -> String {
  let letters = "abcdefghijklmnopqrstuvwxyz".to_array()
  for k = 0; ; k = k + 1 {
    let letter = letters[k % 26].to_string()
    let round = k / 26
    let candidate = prefix + letter + (if round == 0 { "" } else { "\{round}" })
    if !self.used.contains(candidate) {
      self.used[candidate] = true
      return candidate
    }
  }
}

///|
/// The name of the meta (or `Gen`) keyed `key`. A constrained one takes its class: `comparable-a`.
fn Namer::meta_name(self : Namer, key : Int, classes : Array[String]) -> String {
  match self.names.get(key) {
    Some(name) => name
    None => {
      let name = match classes {
        [class, ..] => self.next(class + "-")
        [] => self.next("")
      }
      self.names[key] = name
      name
    }
  }
}

///|
/// Converts `t` to IR. Unbound metas are named on first sight. A rigid of the namer's declaration keeps its own
/// name, without its owner.
fn Namer::to_ir(self : Namer, s : Solver, t : Ty) -> @ir.Type {
  self.reserve_rigids(s, t)
  self.convert(s, t)
}

///|
/// Marks the name of every rigid variable of the namer's declaration in `t` as taken.
fn Namer::reserve_rigids(self : Namer, s : Solver, t : Ty) -> Unit {
  s.rebuild(t, v => {
    if v is Rigid(key, _) && self.owns(key) {
      self.reserve(rigid_name(key))
    }
    v
  })
  |> ignore
}

///|
fn Namer::convert(self : Namer, s : Solver, t : Ty) -> @ir.Type {
  let attrs : @ir.TypeAttributes = Default::default()
  match s.prune(t) {
    Meta(_) | Rigid(_, _) | Gen(_) as v => self.variable(s, v)
    Con(name, args) =>
      Reference(attrs, parse_fqname(name), args.map(a => self.convert(s, a)))
    Fun(input, output) =>
      Function(attrs, self.convert(s, input), self.convert(s, output))
    Tup(items) => Tuple(attrs, items.map(a => self.convert(s, a)))
    UnitTy => Unit(attrs)
    Rec(fields, tail) => {
      // The row is named before the fields, as Elm writes `{ a | total : b }`.
      let row = match tail.map(r => s.prune(r)) {
        Some(Meta(_) | Rigid(_, _) | Gen(_) as v) => Some(self.var_name(s, v).0)
        _ => None
      }
      let names = fields.keys().collect()
      names.sort()
      let out : Map[@ir.Name, @ir.Type] = Map([])
      for name in names {
        if fields.get(name) is Some(field) {
          out[parse_name(name)] = self.convert(s, field)
        }
      }
      match row {
        Some(row) => ExtensibleRecord(attrs, parse_name(row), out)
        None => Record(attrs, out)
      }
    }
  }
}

///|
/// A variable for a `Meta`, `Rigid` or `Gen`. A constrained variable carries the `typeclass` constraint.
fn Namer::variable(self : Namer, s : Solver, v : Ty) -> @ir.Type {
  let (name, classes) = self.var_name(s, v)
  let constraints : Map[String, @ir.Data] = Map([])
  if classes is [class, ..] {
    constraints[TYPECLASS] = Text(class)
  }
  Variable(
    { source: None, constraints, extensions: Map([]), },
    parse_name(name),
  )
}

///|
/// The name and the class set of a `Meta`, `Rigid` or `Gen`.
fn Namer::var_name(self : Namer, s : Solver, v : Ty) -> (String, Array[String]) {
  match v {
    Meta(id) => {
      let classes = match s.metas[id] {
        Unbound(classes~, ..) => classes
        Link(_) => []
      }
      (self.meta_name(id, classes), classes)
    }
    Rigid(key, classes) if self.owns(key) => (rigid_name(key), classes)
    Rigid(key, classes) => {
      let name = match self.foreign.get(key) {
        Some(name) => name
        None => {
          let name = match classes {
            [class, ..] => self.next(class + "-")
            [] => self.next("")
          }
          self.foreign[key] = name
          name
        }
      }
      (name, classes)
    }
    Gen(i) => (self.meta_name(-1 - i, []), [])
    _ => abort("Namer::var_name: not a variable")
  }
}

///|
/// Parses a canonical name that this module made or read from IR.
fn parse_name(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => abort("not a canonical name: \{text}")
  }
}

///|
/// Parses a canonical FQName that this module made from IR.
fn parse_fqname(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => abort("not a canonical FQName: \{text}")
  }
}

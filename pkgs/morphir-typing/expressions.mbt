///|
const BOOL = "morphir/SDK:basics#bool"

///|
const DECIMAL = "morphir/SDK:decimal#decimal"

///|
const DOCUMENT = "morphir/SDK:document#document"

///|
/// A name that does not resolve. The code is `unknown_reference` or `missing_dependency`, or `unsupported` for a
/// construct that the environment cannot type. The second field is the name.
priv suberror Unknown {
  Unknown(String, String)
}

///|
/// A failure at the logical path of the node whose rule failed. `ClassAt` holds a `typeclass` that is not one of
/// the four classes.
priv suberror Located {
  MismatchAt(String, Mismatch)
  UnknownAt(String, Unknown)
  ClassAt(String, String)
}

///|
/// The state of inference over the values of one binding group.
priv struct Infer {
  solver : Solver
  env : Env
  /// The local variables in scope, by canonical name.
  mut locals : Map[String, Poly]
  /// The level of new metas. A let definition is inferred one level deeper.
  level : Int
  /// The type of each node, by logical path.
  types : Map[String, Ty]
  /// The monomorphic types of the binding group being solved, by canonical FQName.
  current : Map[String, Ty]
  /// The signature types of each definition, inputs then output, by the logical path of the definition.
  signatures : Map[String, Array[Ty]]
  /// The canonical FQName of the declaration being inferred. It owns the rigid variables that its signature,
  /// its let annotations and its holes declare. Empty outside a declaration.
  owner : Ref[String]
  /// The rigid variables in scope, by `rigid_key(owner, name)`: the signature of the declaration being inferred
  /// and the enclosing let annotations. A later occurrence of a variable in scope is that `Rigid`, with its
  /// classes, whatever its own attributes say.
  rigid_scope : Map[String, Ty]
  /// The number of let-annotation rigids made so far. Each one gets a unique key (see `let_rigid_key`).
  let_rigids : Ref[Int]
  /// When set, an existing `inferred_type` on a node is a fact: it is unified with the node's type.
  facts : Bool
}

///|
fn Infer::new(env : Env, level : Int, facts? : Bool = false) -> Infer {
  {
    solver: Solver::new((name, args) => env.expand(name, args)),
    env,
    locals: Map([]),
    level,
    types: Map([]),
    current: Map([]),
    signatures: Map([]),
    owner: { val: "", },
    rigid_scope: Map([]),
    let_rigids: { val: 0, },
    facts,
  }
}

///|
/// The same state, one level deeper. The maps are shared.
fn Infer::deeper(self : Infer) -> Infer {
  { ..self, level: self.level + 1, }
}

///|
fn Infer::fresh(self : Infer) -> Ty {
  self.solver.fresh(self.level, [])
}

///|
/// Unifies `expected` with `found`. A failure is located at `path`.
fn Infer::unify(
  self : Infer,
  path : String,
  expected : Ty,
  found : Ty,
) -> Unit raise Located {
  self.solver.unify(expected, found) catch {
    m => raise MismatchAt(path, m)
  }
}

///|
/// Fails for a global name that does not resolve: `unknown_reference` when its package is known, else
/// `missing_dependency`.
fn[T] Infer::unknown(
  self : Infer,
  path : String,
  name : @ir.FQName,
) -> T raise Located {
  let code = if self.env.packages.contains(name.package_name.to_canonical()) {
    "unknown_reference"
  } else {
    "missing_dependency"
  }
  raise UnknownAt(path, Unknown(code, name.to_canonical()))
}

///|
/// Fails at `path` for the first type reference in `types` that does not resolve, with the same codes as
/// `unknown`.
fn Infer::check_types(
  self : Infer,
  types : Array[@ir.Type],
  path : String,
) -> Unit raise Located {
  if self.env.unresolved(types) is Some((code, name)) {
    raise UnknownAt(path, Unknown(code, name))
  }
}

///|
/// Runs `body` in a nested scope: the locals that it binds are gone afterwards.
fn[T] Infer::scoped(
  self : Infer,
  body : () -> T raise Located,
) -> T raise Located {
  let saved = self.locals
  self.locals = saved.copy()
  defer {
    self.locals = saved
  }
  body()
}

///|
/// Binds a local monomorphically.
fn Infer::bind(self : Infer, name : @ir.Name, t : Ty) -> Unit {
  self.locals[name.to_canonical()] = { gens: [], body: t, }
}

///|
/// Infers the type of `v` at `path` and records it in `types`.
fn Infer::value(self : Infer, v : @ir.Value, path : String) -> Ty raise Located {
  let t = match v {
    Literal(_, lit) => self.value_literal(lit, path)
    Constructor(_, name) => self.value_constructor(name, path)
    Tuple(_, items) => self.value_tuple(items, path)
    List(_, items) => self.value_list(items, path)
    Record(_, fields) => self.value_record(fields, path)
    Variable(_, name) => self.value_variable(name, path)
    Reference(_, name) => self.value_reference(name, path)
    Field(_, record, name) => self.value_field(record, name, path)
    FieldFunction(_, name) => self.value_field_function(name)
    Apply(_, f, a) => self.value_apply(f, a, path)
    Lambda(_, p, body) => self.value_lambda(p, body, path)
    LetDefinition(_, name, def, rest) => self.value_let(name, def, rest, path)
    LetRecursion(_, defs, rest) => self.value_let_recursion(defs, rest, path)
    Destructure(_, p, value, rest) =>
      self.value_destructure(p, value, rest, path)
    IfThenElse(_, c, t, e) => self.value_if(c, t, e, path)
    PatternMatch(_, subject, cases) => self.value_case(subject, cases, path)
    UpdateRecord(_, record, fields) => self.value_update(record, fields, path)
    Unit(_) => UnitTy
    Hole(_, _, declared) => self.value_hole(declared, path)
  }
  self.fact(value_attributes(v).inferred_type, t, path)
  self.types[path] = t
  t
}

///|
fn Infer::value_literal(
  self : Infer,
  lit : @ir.Literal,
  path : String,
) -> Ty raise Located {
  match lit {
    BoolLiteral(_) => Con(BOOL, [])
    CharLiteral(_) => Con(CHAR, [])
    StringLiteral(_) => Con(STRING, [])
    IntegerLiteral(_) => self.solver.fresh(self.level, [NUMBER])
    FloatLiteral(_) => Con(FLOAT, [])
    DecimalLiteral(_) => Con(DECIMAL, [])
    DocumentLiteral(_) =>
      if self.env.types.contains(DOCUMENT) {
        Con(DOCUMENT, [])
      } else {
        raise UnknownAt(path, Unknown("unsupported", DOCUMENT))
      }
  }
}

///|
fn Infer::value_constructor(
  self : Infer,
  name : @ir.FQName,
  path : String,
) -> Ty raise Located {
  match self.env.constructors.get(name.to_canonical()) {
    Some(p) => self.global(p, path)
    None => self.unknown(path, name)
  }
}

///|
/// A reference resolves in the current binding group first, then in the values of the environment.
fn Infer::value_reference(
  self : Infer,
  name : @ir.FQName,
  path : String,
) -> Ty raise Located {
  let key = name.to_canonical()
  if self.current.get(key) is Some(t) {
    return t
  }
  match self.env.values.get(key) {
    Some(p) => self.global(p, path)
    None => self.unknown(path, name)
  }
}

///|
/// A new instance of the scheme of a global name, used at `path`. A scheme with a class that is not one of the
/// four classes is `unsupported`.
fn Infer::global(self : Infer, p : Poly, path : String) -> Ty raise Located {
  if p.unknown_class() is Some(class) {
    raise ClassAt(path, class)
  }
  self.solver.instantiate(p, self.level)
}

///|
fn Infer::value_variable(
  self : Infer,
  name : @ir.Name,
  path : String,
) -> Ty raise Located {
  match self.locals.get(name.to_canonical()) {
    Some(p) => self.solver.instantiate(p, self.level)
    None =>
      raise UnknownAt(path, Unknown("unknown_reference", name.to_canonical()))
  }
}

///|
/// The function must have a function type. A type that cannot be one, after alias expansion, is `arity`.
fn Infer::value_apply(
  self : Infer,
  f : @ir.Value,
  a : @ir.Value,
  path : String,
) -> Ty raise Located {
  let ft = self.value(f, @identities.path_function(path))
  let at = self.value(a, @identities.path_argument(path))
  let result = self.fresh()
  let expected = Fun(at, result)
  match self.expand_all(ft) {
    Con(_, _) | Tup(_) | Rec(_, _) | UnitTy as t =>
      raise MismatchAt(path, Mismatch("arity", expected, t))
    _ => ()
  }
  self.unify(@identities.path_argument(path), ft, expected)
  result
}

///|
/// Prunes `t` and expands aliases at its head. Cyclic aliases do not expand, so this ends.
fn Infer::expand_all(self : Infer, t : Ty) -> Ty {
  let mut t = self.solver.prune(t)
  while t is Con(name, args) && self.env.expand(name, args) is Some(expanded) {
    t = self.solver.prune(expanded)
  }
  t
}

///|
fn Infer::value_lambda(
  self : Infer,
  p : @ir.Pattern,
  body : @ir.Value,
  path : String,
) -> Ty raise Located {
  self.scoped(() => {
    let pt = self.pattern(p, @identities.path_pattern(path))
    let bt = self.value(body, @identities.path_body(path))
    Fun(pt, bt)
  })
}

///|
fn Infer::value_if(
  self : Infer,
  c : @ir.Value,
  t : @ir.Value,
  e : @ir.Value,
  path : String,
) -> Ty raise Located {
  let ct = self.value(c, @identities.path_condition(path))
  self.unify(@identities.path_condition(path), Con(BOOL, []), ct)
  let tt = self.value(t, @identities.path_then(path))
  let et = self.value(e, @identities.path_else(path))
  self.unify(@identities.path_else(path), tt, et)
  tt
}

///|
fn Infer::value_list(
  self : Infer,
  items : Array[@ir.Value],
  path : String,
) -> Ty raise Located {
  let element = self.fresh()
  for i, item in items {
    let t = self.value(item, @identities.path_item(path, i))
    self.unify(@identities.path_item(path, i), element, t)
  }
  Con(LIST, [element])
}

///|
/// A tuple of no items is the unit type.
fn Infer::value_tuple(
  self : Infer,
  items : Array[@ir.Value],
  path : String,
) -> Ty raise Located {
  if items.is_empty() {
    return UnitTy
  }
  let types = []
  for i, item in items {
    types.push(self.value(item, @identities.path_item(path, i)))
  }
  Tup(types)
}

///|
/// A hole is a todo: it stands for code that is not written yet, so it must not fail the run by itself. Its
/// declared type is converted by the rule of `todo_type`. Without a declared type, the hole is a fresh meta.
fn Infer::value_hole(
  self : Infer,
  declared : @ir.Type?,
  path : String,
) -> Ty raise Located {
  match declared {
    Some(t) => self.todo_type(t, path)
    None => self.fresh()
  }
}

///|
/// A declared type as a `Ty`, by the hole rule: a variable in scope is that rigid variable; any other variable is
/// a fresh meta for this occurrence, with the classes of its `typeclass` or its name prefix; a marked variable is
/// a meta. One name is one meta within the type.
fn Infer::todo_type(
  self : Infer,
  t : @ir.Type,
  path : String,
) -> Ty raise Located {
  if unknown_class([t]) is Some(class) {
    raise ClassAt(path, class)
  }
  self.check_types([t], path)
  let owner = self.owner.val
  let vars : Map[String, Ty] = Map([])
  to_ty(t, (name, attrs) => {
    match vars.get(name) {
      Some(v) => v
      None => {
        let key = rigid_key(owner, name)
        let v = match self.rigid_scope.get(key) {
          Some(rigid) if !is_unknown(attrs) => rigid
          _ => self.solver.fresh(self.level, classes_of(name, attrs))
        }
        vars[name] = v
        v
      }
    }
  })
}

///|
/// When facts are on, unifies the fact `fact` of the node at `path` with its inferred type `t`. A failure is
/// `annotation_mismatch`, with the fact as expected and the inferred type as found.
fn Infer::fact(
  self : Infer,
  fact : @ir.Type?,
  t : Ty,
  path : String,
) -> Unit raise Located {
  guard self.facts && fact is Some(declared) else { return }
  let f = self.todo_type(declared, path)
  self.solver.unify(f, t) catch {
    _ => raise MismatchAt(path, Mismatch("annotation_mismatch", f, t))
  }
}

///|
fn value_attributes(v : @ir.Value) -> @ir.ValueAttributes {
  match v {
    Literal(a, _)
    | Constructor(a, _)
    | Tuple(a, _)
    | List(a, _)
    | Record(a, _)
    | Variable(a, _)
    | Reference(a, _)
    | Field(a, _, _)
    | FieldFunction(a, _)
    | Apply(a, _, _)
    | Lambda(a, _, _)
    | LetDefinition(a, _, _, _)
    | LetRecursion(a, _, _)
    | Destructure(a, _, _, _)
    | IfThenElse(a, _, _, _)
    | PatternMatch(a, _, _)
    | UpdateRecord(a, _, _)
    | Unit(a)
    | Hole(a, _, _) => a
  }
}

///|
fn pattern_attributes(p : @ir.Pattern) -> @ir.ValueAttributes {
  match p {
    WildcardPattern(a)
    | AsPattern(a, _, _)
    | TuplePattern(a, _)
    | ConstructorPattern(a, _, _)
    | EmptyListPattern(a)
    | HeadTailPattern(a, _, _)
    | LiteralPattern(a, _)
    | UnitPattern(a) => a
  }
}

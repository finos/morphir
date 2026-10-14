///|
/// A fresh meta at the current level for each variable of `types` that carries the unknown marker, by canonical
/// name. All occurrences of one name share the meta.
fn Infer::marked_metas(
  self : Infer,
  types : Array[@ir.Type],
) -> Map[String, Ty] {
  let metas : Map[String, Ty] = Map([])
  for t in types {
    to_ty(t, (name, attrs) => {
      if is_unknown(attrs) && !metas.contains(name) {
        metas[name] = self.solver.fresh(self.level, classes_of(name, attrs))
      }
      UnitTy
    })
    |> ignore
  }
  metas
}

///|
/// Converts a declared type. A variable in `metas` is that meta. Any other variable is rigid and belongs to
/// `owner`: `rigid` gets `rigid_key(owner, name)` and the classes of this occurrence, and gives the `Rigid`.
fn Infer::declared(
  self : Infer,
  t : @ir.Type,
  metas : Map[String, Ty],
  owner : String,
  rigid : (String, Array[String]) -> Ty,
) -> Ty {
  ignore(self)
  to_ty(t, (name, attrs) => {
    match metas.get(name) {
      Some(meta) => meta
      None => rigid(rigid_key(owner, name), classes_of(name, attrs))
    }
  })
}

///|
/// The inputs, the declared output and the body to infer of a definition. Native and incomplete bodies use
/// their signature only.
fn definition_parts(
  def : @ir.ValueDefinition,
) -> (Array[(@ir.Name, @ir.Type)], @ir.Type?, @ir.Value?) {
  match def {
    ExpressionBody(inputs, output, body) => (inputs, Some(output), Some(body))
    NativeBody(inputs, output, _) => (inputs, Some(output), None)
    ExternalBody(inputs, output, _, fallback) =>
      (inputs, Some(output), fallback)
    IncompleteBody(inputs, output, _, _) => (inputs, output, None)
  }
}

///|
/// Infers a definition at the current level. Its body is at `path_body(path)`. The declared input and output types
/// constrain it: marked variables are metas, and other variables are rigid and belong to the current declaration.
/// A rigid variable that is not yet in `rigid_scope` is declared here, with a unique key: it is added to the scope
/// and returned. The result is the curried type of the definition. A `typeclass` that is not one of the four
/// classes is `unsupported` at `path`, and a type reference that does not resolve fails at `path`.
fn Infer::definition(
  self : Infer,
  def : @ir.ValueDefinition,
  path : String,
) -> (Ty, Array[Ty]) raise Located {
  let (inputs, output, body) = definition_parts(def)
  let signature = inputs.map(input => input.1)
  if output is Some(t) {
    signature.push(t)
  }
  if unknown_class(signature) is Some(class) {
    raise ClassAt(path, class)
  }
  self.check_types(signature, path)
  let metas = self.marked_metas(signature)
  let owned : Array[Ty] = []
  let scope = self.rigid_scope
  let rigid = fn(key : String, classes : Array[String]) -> Ty {
    match scope.get(key) {
      Some(declared) => declared
      None => {
        self.let_rigids.val += 1
        let declared = Rigid(let_rigid_key(key, self.let_rigids.val), classes)
        owned.push(declared)
        scope[key] = declared
        declared
      }
    }
  }
  let owner = self.owner.val
  let ins = inputs.map(input => self.declared(input.1, metas, owner, rigid))
  let out = match output {
    Some(t) => self.declared(t, metas, owner, rigid)
    None => self.fresh()
  }
  self.signatures[path] = [..ins, out]
  if body is Some(body) {
    self.scoped(() => {
      for i, input in inputs {
        self.bind(input.0, ins[i])
      }
      let bt = self.value(body, @identities.path_body(path))
      self.unify(@identities.path_body(path), out, bt)
    })
  }
  (curry(ins, out), owned)
}

///|
/// Fails when a rigid variable in `owned` occurs in the type of a local or of the current group: the variable
/// would escape the definition that declares it.
fn Infer::check_escape(
  self : Infer,
  owned : Array[Ty],
  path : String,
) -> Unit raise Located {
  let outer = self.locals.values().map(p => p.body).collect()
  outer.append(self.current.values().collect())
  for rigid in owned {
    for t in outer {
      if self.solver.mentions_rigid(t, rigid_of(rigid)) {
        raise MismatchAt(path, Mismatch("rigid_variable", rigid, t))
      }
    }
  }
}

///|
/// The key of a `Rigid`.
fn rigid_of(t : Ty) -> String {
  guard t is Rigid(key, _) else { abort("rigid_of: not a rigid variable") }
  key
}

///|
/// Whether the rigid variable `name` occurs in `t`.
fn Solver::mentions_rigid(self : Solver, t : Ty, name : String) -> Bool {
  match self.prune(t) {
    Rigid(other, _) => other == name
    Con(_, items) | Tup(items) =>
      items.iter().any(x => self.mentions_rigid(x, name))
    Fun(input, output) =>
      self.mentions_rigid(input, name) || self.mentions_rigid(output, name)
    Rec(fields, tail) =>
      fields.values().any(x => self.mentions_rigid(x, name)) ||
      (tail is Some(row) && self.mentions_rigid(row, name))
    Meta(_) | Gen(_) | UnitTy => false
  }
}

///|
/// Removes the rigid variables that a let signature declared from the scope. A later annotation that uses the
/// same name declares a new variable.
fn Infer::release(self : Infer, owned : Array[Ty]) -> Unit {
  for rigid in owned {
    self.rigid_scope.remove(scope_key(rigid_of(rigid)))
  }
}

///|
/// `let name = def in rest`: the definition is inferred one level deeper and generalized at this level.
fn Infer::value_let(
  self : Infer,
  name : @ir.Name,
  def : @ir.ValueDefinition,
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  let (t, owned) = self
    .deeper()
    .definition(def, @identities.path_definition(path))
  self.check_escape(owned, path)
  let poly = self.solver.generalize_with(t, self.level, owned.map(rigid_of))
  self.release(owned)
  self.scoped(() => {
    self.locals[name.to_canonical()] = poly
    self.value(rest, @identities.path_in(path))
  })
}

///|
/// A recursive group. A definition with a complete annotation has the scheme of its annotation in the whole
/// group, as a declared top-level value does, so the group can use it at several types. Every other name has a
/// meta one level deeper while the group is solved, and these names are generalized together. Each annotation
/// declares its own variables: the `a` of one sibling is not the `a` of another. A `typeclass` that is not one
/// of the four classes, in any annotation, fails the group before inference starts.
fn Infer::value_let_recursion(
  self : Infer,
  defs : Map[@ir.Name, @ir.ValueDefinition],
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  for name, def in defs {
    if unknown_class(signature_types(def)) is Some(class) {
      raise ClassAt(@identities.path_definitions(path, name), class)
    }
  }
  let inner = self.deeper()
  let monos : Map[@ir.Name, Ty] = Map([])
  let annotated : Map[@ir.Name, Poly] = Map([])
  for name, def in defs {
    match self.annotation_scheme(def) {
      Some(p) => annotated[name] = p
      None => monos[name] = inner.fresh()
    }
  }
  let owned : Array[Ty] = []
  inner.scoped(() => {
    for name, mono in monos {
      inner.bind(name, mono)
    }
    for name, p in annotated {
      inner.locals[name.to_canonical()] = p
    }
    for name, def in defs {
      let (t, own) = inner.definition(
        def,
        @identities.path_definitions(path, name),
      )
      owned.append(own)
      inner.release(own)
      if monos.get(name) is Some(mono) {
        inner.unify(@identities.path_definitions_body(path, name), mono, t)
      }
    }
  })
  self.check_escape(owned, path)
  let rigids = owned.map(rigid_of)
  let polys = monos
    .iter()
    .map(item => {
      (item.0, self.solver.generalize_with(item.1, self.level, rigids))
    })
    .collect()
  for name, p in annotated {
    polys.push((name, p))
  }
  self.scoped(() => {
    for item in polys {
      self.locals[item.0.to_canonical()] = item.1
    }
    self.value(rest, @identities.path_in(path))
  })
}

///|
/// The scheme of a let definition with a complete annotation: inputs and an output without the unknown marker.
/// A variable in scope is that rigid variable; every other variable is quantified, with the classes of its first
/// occurrence. `None` when the annotation is not complete.
fn Infer::annotation_scheme(self : Infer, def : @ir.ValueDefinition) -> Poly? {
  let (inputs, output, _) = definition_parts(def)
  guard output is Some(output) else { return None }
  if signature_types(def).iter().any(has_marker) {
    return None
  }
  let owner = self.owner.val
  let ids : Map[String, Int] = Map([])
  let gens : Array[Array[String]] = []
  let vars = fn(name : String, attrs : @ir.TypeAttributes) -> Ty {
    match self.rigid_scope.get(rigid_key(owner, name)) {
      Some(rigid) => rigid
      None =>
        match ids.get(name) {
          Some(id) => Gen(id)
          None => {
            ids[name] = gens.length()
            gens.push(classes_of(name, attrs))
            Gen(gens.length() - 1)
          }
        }
    }
  }
  let ins = inputs.map(input => to_ty(input.1, vars))
  Some({ gens, body: curry(ins, to_ty(output, vars)), })
}

///|
/// `let p = value in rest`: the pattern takes the type of the value, and binds monomorphically.
fn Infer::value_destructure(
  self : Infer,
  p : @ir.Pattern,
  value : @ir.Value,
  rest : @ir.Value,
  path : String,
) -> Ty raise Located {
  let vt = self.value(value, @identities.path_value(path))
  self.scoped(() => {
    let pt = self.pattern(p, @identities.path_pattern(path))
    self.unify(@identities.path_pattern(path), pt, vt)
    self.value(rest, @identities.path_in(path))
  })
}

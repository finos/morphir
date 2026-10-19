///|
/// Rebuilds a declaration with the same path steps as inference. `node` sees each `Value` and `Pattern` before
/// its children, and `signature` sees each definition before its body.
priv struct Walker {
  node : (@ir.ValueAttributes, String) -> @ir.ValueAttributes
  signature : (@ir.ValueDefinition, String) -> @ir.ValueDefinition
}

///|
/// A definition at `path`. Only expression bodies and external fallbacks have a body to walk.
fn Walker::definition(
  self : Walker,
  def : @ir.ValueDefinition,
  path : String,
) -> @ir.ValueDefinition {
  match (self.signature)(def, path) {
    ExpressionBody(inputs, output, body) =>
      ExpressionBody(
        inputs,
        output,
        self.value(body, @identities.path_body(path)),
      )
    ExternalBody(inputs, output, bindings, Some(fallback)) =>
      ExternalBody(
        inputs,
        output,
        bindings,
        Some(self.value(fallback, @identities.path_body(path))),
      )
    other => other
  }
}

///|
fn Walker::value(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Literal(a, lit) => Literal((self.node)(a, path), lit)
    Constructor(a, name) => Constructor((self.node)(a, path), name)
    Variable(a, name) => Variable((self.node)(a, path), name)
    Reference(a, name) => Reference((self.node)(a, path), name)
    FieldFunction(a, name) => FieldFunction((self.node)(a, path), name)
    Unit(a) => Unit((self.node)(a, path))
    Hole(a, reason, t) => Hole((self.node)(a, path), reason, t)
    Tuple(a, items) => {
      let a = (self.node)(a, path)
      Tuple(
        a,
        items.mapi((i, x) => self.value(x, @identities.path_item(path, i))),
      )
    }
    List(a, items) => {
      let a = (self.node)(a, path)
      List(
        a,
        items.mapi((i, x) => self.value(x, @identities.path_item(path, i))),
      )
    }
    Record(a, fields) => {
      let a = (self.node)(a, path)
      Record(a, self.fields(fields, path))
    }
    Field(a, record, name) => {
      let a = (self.node)(a, path)
      Field(a, self.value(record, @identities.path_record(path)), name)
    }
    UpdateRecord(a, record, fields) => {
      let a = (self.node)(a, path)
      let record = self.value(record, @identities.path_record(path))
      UpdateRecord(a, record, self.fields(fields, path))
    }
    _ => self.compound(v, path)
  }
}

///|
fn Walker::fields(
  self : Walker,
  fields : Map[@ir.Name, @ir.Value],
  path : String,
) -> Map[@ir.Name, @ir.Value] {
  let out : Map[@ir.Name, @ir.Value] = Map([])
  for name, field in fields {
    out[name] = self.value(field, @identities.path_field(path, name))
  }
  out
}

///|
/// The values with a scope or with several kinds of child.
fn Walker::compound(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Apply(a, f, x) => {
      let a = (self.node)(a, path)
      let f = self.value(f, @identities.path_function(path))
      Apply(a, f, self.value(x, @identities.path_argument(path)))
    }
    Lambda(a, p, body) => {
      let a = (self.node)(a, path)
      let p = self.pattern(p, @identities.path_pattern(path))
      Lambda(a, p, self.value(body, @identities.path_body(path)))
    }
    LetDefinition(a, name, def, rest) => {
      let a = (self.node)(a, path)
      let def = self.definition(def, @identities.path_definition(path))
      LetDefinition(a, name, def, self.value(rest, @identities.path_in(path)))
    }
    LetRecursion(a, defs, rest) => {
      let a = (self.node)(a, path)
      let out : Map[@ir.Name, @ir.ValueDefinition] = Map([])
      for name, def in defs {
        out[name] = self.definition(
          def,
          @identities.path_definitions(path, name),
        )
      }
      LetRecursion(a, out, self.value(rest, @identities.path_in(path)))
    }
    Destructure(a, p, value, rest) => {
      let a = (self.node)(a, path)
      let p = self.pattern(p, @identities.path_pattern(path))
      let value = self.value(value, @identities.path_value(path))
      Destructure(a, p, value, self.value(rest, @identities.path_in(path)))
    }
    IfThenElse(a, c, t, e) => {
      let a = (self.node)(a, path)
      let c = self.value(c, @identities.path_condition(path))
      let t = self.value(t, @identities.path_then(path))
      IfThenElse(a, c, t, self.value(e, @identities.path_else(path)))
    }
    PatternMatch(a, subject, cases) => {
      let a = (self.node)(a, path)
      let subject = self.value(subject, @identities.path_subject(path))
      let cases = cases.mapi((i, c) => {
        let p = self.pattern(c.0, @identities.path_case_pattern(path, i))
        (p, self.value(c.1, @identities.path_case_body(path, i)))
      })
      PatternMatch(a, subject, cases)
    }
    _ => v
  }
}

///|
fn Walker::pattern(
  self : Walker,
  p : @ir.Pattern,
  path : String,
) -> @ir.Pattern {
  match p {
    WildcardPattern(a) => WildcardPattern((self.node)(a, path))
    EmptyListPattern(a) => EmptyListPattern((self.node)(a, path))
    UnitPattern(a) => UnitPattern((self.node)(a, path))
    LiteralPattern(a, lit) => LiteralPattern((self.node)(a, path), lit)
    AsPattern(a, inner, name) => {
      let a = (self.node)(a, path)
      AsPattern(a, self.pattern(inner, @identities.path_pattern(path)), name)
    }
    TuplePattern(a, items) => {
      let a = (self.node)(a, path)
      TuplePattern(
        a,
        items.mapi((i, x) => self.pattern(x, @identities.path_item(path, i))),
      )
    }
    ConstructorPattern(a, name, args) => {
      let a = (self.node)(a, path)
      let args = args.mapi((i, x) => {
        self.pattern(x, @identities.path_arg(path, i))
      })
      ConstructorPattern(a, name, args)
    }
    HeadTailPattern(a, head, tail) => {
      let a = (self.node)(a, path)
      let head = self.pattern(head, @identities.path_head(path))
      HeadTailPattern(a, head, self.pattern(tail, @identities.path_tail(path)))
    }
  }
}

///|
/// The source location of the node at `path` in the declaration `d`, if the node has one.
fn source_at(d : Decl, path : String) -> @ir.SourceLocation? {
  let mut found = None
  let walker : Walker = {
    node: (a, p) => {
      if p == path {
        found = a.source
      }
      a
    },
    signature: (def, _) => def,
  }
  walker.definition(d.def, d.root) |> ignore
  found
}

///|
/// The new definition of each declaration whose group succeeded, by canonical FQName. In Check, an existing
/// `inferred_type` that is not equivalent to the inferred type in the declaration's `TypeScope` is
/// `annotation_mismatch`.
fn Driver::output(self : Driver) -> Map[String, @ir.ValueDefinition] {
  let out : Map[String, @ir.ValueDefinition] = Map([])
  for i, d in self.decls {
    if self.solved.get(i) is Some(infer) {
      out[d.key] = self.fill(d, infer)
    }
  }
  out
}

///|
/// Writes the solved types into the declaration `d`. One namer names every type of the declaration, after it
/// has reserved every rigid name that the types use.
fn Driver::fill(self : Driver, d : Decl, infer : Infer) -> @ir.ValueDefinition {
  let s = infer.solver
  let namer = Namer::new(owner=d.key)
  let prefix = d.root + "/"
  for path, t in infer.types {
    if path.has_prefix(prefix) {
      namer.reserve_rigids(s, t)
    }
  }
  for path, types in infer.signatures {
    if path == d.root || path.has_prefix(prefix) {
      types.each(t => namer.reserve_rigids(s, t))
    }
  }
  let scope = TypeScope::of_definition(d.def)
  let walker : Walker = {
    node: (a, path) => self.fill_node(infer, namer, scope, a, path),
    signature: (def, path) => fill_signature(infer, namer, def, path),
  }
  let result = walker.definition(d.def, d.root)
  if namer.conflicts.val {
    self.problems.push(
      problem(
        "unsupported",
        d.root,
        "Conflicting type attributes cannot be represented on one IR node",
        None,
      ),
    )
  }
  result
}

///|
/// Sets the inferred type of one node. The old type was a fact during inference in both modes. In Check, also
/// compares the solution with the old type. Every node of one declaration is compared in the declaration's `scope`.
fn Driver::fill_node(
  self : Driver,
  infer : Infer,
  namer : Namer,
  scope : TypeScope,
  a : @ir.ValueAttributes,
  path : String,
) -> @ir.ValueAttributes {
  guard infer.types.get(path) is Some(t) else { return a }
  let inferred = namer.to_ir(infer.solver, t)
  if self.mode is Check &&
    a.inferred_type is Some(old) &&
    !scope.equivalent(
      self.env.expand_shape(old),
      self.env.expand_shape(inferred),
    ) {
    let (old_text, inferred_text) = distinct_texts(old, inferred)
    self.problems.push({
      code: "annotation_mismatch",
      node: path,
      message: "the node has the type \{old_text}, but inference gives \{inferred_text}",
      expected: Some(inferred),
      found: Some(old),
      source: a.source,
    })
  }
  let retained = match a.inferred_type {
    Some(old) if !has_marker(old) &&
      types_equivalent(
        self.env.expand_shape(old),
        self.env.expand_shape(inferred),
      ) => old
    Some(old) => retain_solved_attributes(old, inferred, namer.conflicts)
    None => inferred
  }
  { ..a, inferred_type: Some(retained), }
}

///|
/// Replaces each signature type that has a marked variable with its solution. Definitions without a body keep
/// their signature.
fn fill_signature(
  infer : Infer,
  namer : Namer,
  def : @ir.ValueDefinition,
  path : String,
) -> @ir.ValueDefinition {
  guard infer.signatures.get(path) is Some(solved) else { return def }
  let solve = fn(t : @ir.Type, i : Int32) -> @ir.Type {
    if has_marker(t) {
      retain_solved_attributes(
        t,
        namer.to_ir(infer.solver, solved[i]),
        namer.conflicts,
      )
    } else {
      t
    }
  }
  let last = solved.length() - 1
  let fill_inputs = fn(inputs : Array[(@ir.Name, @ir.Type)]) {
    inputs.mapi((i, input) => (input.0, solve(input.1, i)))
  }
  match def {
    ExpressionBody(inputs, output, body) =>
      ExpressionBody(fill_inputs(inputs), solve(output, last), body)
    ExternalBody(inputs, output, bindings, Some(_) as fallback) =>
      ExternalBody(fill_inputs(inputs), solve(output, last), bindings, fallback)
    _ => def
  }
}

///|
/// `file` with the definitions in `defs`, by canonical FQName.
fn rebuild_file(
  file : @ir.IRFile,
  defs : Map[String, @ir.ValueDefinition],
) -> @ir.IRFile {
  let distribution : @ir.Distribution = match file.distribution {
    Library(name, deps, def) =>
      Library(name, deps, rebuild_package(name, def, defs))
    Application(name, bundled, def, entries) =>
      Application(name, bundled, rebuild_package(name, def, defs), entries)
    Specs(_, _, _) => return file
  }
  @ir.IRFile::new(distribution, format_version=file.format_version) catch {
    _ => abort("the format version of the file is not valid")
  }
}

///|
fn rebuild_package(
  pkg_name : @ir.PackageName,
  def : @ir.PackageDefinition,
  defs : Map[String, @ir.ValueDefinition],
) -> @ir.PackageDefinition {
  let modules : Map[@ir.ModuleName, @ir.AccessControlled[@ir.ModuleDefinition]] = Map([],
  )
  for module_, m in def.modules {
    let values : Map[
      @ir.Name,
      @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
    ] = Map([])
    for name, v in m.value.values {
      values[name] = match defs.get(fq_text(pkg_name, module_, name)) {
        Some(new) => { ..v, value: { ..v.value, value: new, }, }
        None => v
      }
    }
    modules[module_] = { ..m, value: { ..m.value, values, }, }
  }
  { modules, }
}

///|
/// The problems of a `Specs` file: each type reference in its signatures and type bodies must resolve.
fn Env::check_specification(
  self : Env,
  pkg_name : @ir.PackageName,
  spec : @ir.PackageSpecification,
) -> Array[InferenceProblem] {
  let out : Array[InferenceProblem] = []
  for module_, m in spec.modules {
    for name, t in m.types {
      let types = match t.value.body {
        TypeAliasSpecification(_, body) => [body]
        CustomTypeSpecification(_, ctors) => constructor_types(ctors)
        OpaqueTypeSpecification(_) | DerivedTypeSpecification(_, _) => []
      }
      self.check_references(
        types,
        "type:" + fq_text(pkg_name, module_, name),
        out,
      )
    }
    for name, v in m.values {
      let types = [..v.value.inputs.map(input => input.1), v.value.output]
      self.check_references(
        types,
        "value:" + fq_text(pkg_name, module_, name),
        out,
      )
    }
  }
  out
}

///|
/// The problems of the type definitions of a library or an application: each type reference in an alias body or
/// a constructor argument must resolve. Value signatures, let signatures and holes are checked when their
/// declaration is inferred.
fn Env::check_type_definitions(
  self : Env,
  pkg_name : @ir.PackageName,
  def : @ir.PackageDefinition,
) -> Array[InferenceProblem] {
  let out : Array[InferenceProblem] = []
  for module_, m in def.modules {
    for name, t in m.value.types {
      let types = match t.value.value {
        TypeAliasDefinition(_, body) => [body]
        CustomTypeDefinition(_, ctors) => constructor_types(ctors.value)
        IncompleteTypeDefinition(_, _, _) => []
      }
      self.check_references(
        types,
        "type:" + fq_text(pkg_name, module_, name),
        out,
      )
    }
  }
  out
}

///|
/// The problems of the public interface of a bundled dependency definition: each type reference in a public type
/// body or a public value signature must resolve. A reference to a private type of the same package resolves,
/// because the package defines it. Bundled bodies are trusted: inference does not infer them.
fn Env::check_bundled(
  self : Env,
  pkg_name : @ir.PackageName,
  def : @ir.PackageDefinition,
) -> Array[InferenceProblem] {
  let own : Map[String, Int32] = Map([])
  for module_, m in def.modules {
    for name, t in m.value.types {
      own[fq_text(pkg_name, module_, name)] = match t.value.value {
        TypeAliasDefinition(params, _)
        | CustomTypeDefinition(params, _)
        | IncompleteTypeDefinition(params, _, _) => params.length()
      }
    }
  }
  let out : Array[InferenceProblem] = []
  for module_, m in def.modules {
    guard m.access is Public else { continue }
    for name, t in m.value.types {
      guard t.access is Public else { continue }
      let types = match t.value.value {
        TypeAliasDefinition(_, body) => [body]
        CustomTypeDefinition(_, ctors) if ctors.access is Public =>
          constructor_types(ctors.value)
        CustomTypeDefinition(_, _) | IncompleteTypeDefinition(_, _, _) => []
      }
      self.check_references(
        types,
        "type:" + fq_text(pkg_name, module_, name),
        out,
        own~,
      )
    }
    for name, v in m.value.values {
      guard v.access is Public else { continue }
      self.check_references(
        signature_types(v.value.value),
        "value:" + fq_text(pkg_name, module_, name),
        out,
        own~,
      )
    }
  }
  out
}

///|
/// The argument types of every constructor.
fn constructor_types(ctors : @ir.Constructors) -> Array[@ir.Type] {
  ctors.values().flat_map(args => args.map(a => a.1).iter()).collect()
}

///|
/// Adds a problem at `path` for the first type reference in `types` that does not resolve. A type in `own`, by
/// canonical FQName with its arity, resolves too.
fn Env::check_references(
  self : Env,
  types : Array[@ir.Type],
  path : String,
  out : Array[InferenceProblem],
  own~ : Map[String, Int32] = Map([]),
) -> Unit {
  if self.unresolved(types, own~) is Some((code, key)) {
    out.push(problem(code, path, unknown_message(code, key), None))
  }
}

///|
/// The first type reference in `types` that does not resolve, with its code: `unknown_reference` when its
/// package has a specification or a definition, else `missing_dependency`. A reference that resolves but has
/// another number of arguments than the type takes is `arity`. A type in `own`, by canonical FQName with its
/// arity, resolves too.
fn Env::unresolved(
  self : Env,
  types : Array[@ir.Type],
  own~ : Map[String, Int32] = Map([]),
) -> (String, String)? {
  let refs : Array[(String, Int32)] = []
  types.each(t => counted_references_of(t, refs))
  for ref_ in refs {
    let (key, count) = ref_
    match self.types.get(key) {
      Some(Alias(params, _)) =>
        if params.length() != count {
          return Some(("arity", key))
        }
      Some(Nominal(arity)) => if arity != count { return Some(("arity", key)) }
      None if own.get(key) is Some(arity) =>
        if arity != count {
          return Some(("arity", key))
        }
      None => {
        let name = parse_fqname(key)
        let code = if self.packages.contains(name.package_name.to_canonical()) {
          "unknown_reference"
        } else {
          "missing_dependency"
        }
        return Some((code, key))
      }
    }
  }
  None
}

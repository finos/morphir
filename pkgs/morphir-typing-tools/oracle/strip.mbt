// Helpers for the oracle tests. They walk declarations with the logical path steps of
// `pkgs/morphir-typing/paths.mbt`, so that a path here names the same node as a path in an inference problem.

///|
/// Rebuilds a declaration. `node` sees each `Value` and `Pattern` before its children, with its path and
/// whether it is a `Literal` value. `signature` sees each definition, with its path, before its body.
priv struct Walker {
  node : (@ir.ValueAttributes, String, Bool) -> @ir.ValueAttributes
  signature : (@ir.ValueDefinition, String) -> @ir.ValueDefinition
}

///|
fn step(path : String, child : String) -> String {
  path + "/" + child
}

///|
/// A definition at `path`. Inference walks only expression bodies and external fallbacks, so this does too.
fn Walker::definition(
  self : Walker,
  def : @ir.ValueDefinition,
  path : String,
) -> @ir.ValueDefinition {
  match (self.signature)(def, path) {
    ExpressionBody(inputs, output, body) =>
      ExpressionBody(inputs, output, self.value(body, step(path, "body")))
    ExternalBody(inputs, output, bindings, Some(fallback)) =>
      ExternalBody(
        inputs,
        output,
        bindings,
        Some(self.value(fallback, step(path, "body"))),
      )
    other => other
  }
}

///|
fn Walker::leaf(
  self : Walker,
  a : @ir.ValueAttributes,
  path : String,
) -> @ir.ValueAttributes {
  (self.node)(a, path, false)
}

///|
fn Walker::value(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Literal(a, lit) => Literal((self.node)(a, path, true), lit)
    Constructor(a, name) => Constructor(self.leaf(a, path), name)
    Variable(a, name) => Variable(self.leaf(a, path), name)
    Reference(a, name) => Reference(self.leaf(a, path), name)
    FieldFunction(a, name) => FieldFunction(self.leaf(a, path), name)
    Unit(a) => Unit(self.leaf(a, path))
    Hole(a, reason, t) => Hole(self.leaf(a, path), reason, t)
    Tuple(a, items) => {
      let a = self.leaf(a, path)
      Tuple(a, items.mapi((i, x) => self.value(x, step(path, "items/\{i}"))))
    }
    List(a, items) => {
      let a = self.leaf(a, path)
      List(a, items.mapi((i, x) => self.value(x, step(path, "items/\{i}"))))
    }
    Record(a, fields) => {
      let a = self.leaf(a, path)
      Record(a, self.fields(fields, path))
    }
    Field(a, record, name) => {
      let a = self.leaf(a, path)
      Field(a, self.value(record, step(path, "record")), name)
    }
    UpdateRecord(a, record, fields) => {
      let a = self.leaf(a, path)
      let record = self.value(record, step(path, "record"))
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
    out[name] = self.value(field, step(path, "fields/" + name.to_canonical()))
  }
  out
}

///|
/// The values with a scope or with several kinds of child.
fn Walker::compound(self : Walker, v : @ir.Value, path : String) -> @ir.Value {
  match v {
    Apply(a, f, x) => {
      let a = self.leaf(a, path)
      let f = self.value(f, step(path, "function"))
      Apply(a, f, self.value(x, step(path, "argument")))
    }
    Lambda(a, p, body) => {
      let a = self.leaf(a, path)
      let p = self.pattern(p, step(path, "pattern"))
      Lambda(a, p, self.value(body, step(path, "body")))
    }
    LetDefinition(a, name, def, rest) => {
      let a = self.leaf(a, path)
      let def = self.definition(def, step(path, "definition"))
      LetDefinition(a, name, def, self.value(rest, step(path, "in")))
    }
    LetRecursion(a, defs, rest) => {
      let a = self.leaf(a, path)
      let out : Map[@ir.Name, @ir.ValueDefinition] = Map([])
      for name, def in defs {
        out[name] = self.definition(
          def,
          step(path, "definitions/" + name.to_canonical()),
        )
      }
      LetRecursion(a, out, self.value(rest, step(path, "in")))
    }
    Destructure(a, p, value, rest) => {
      let a = self.leaf(a, path)
      let p = self.pattern(p, step(path, "pattern"))
      let value = self.value(value, step(path, "value"))
      Destructure(a, p, value, self.value(rest, step(path, "in")))
    }
    IfThenElse(a, c, t, e) => {
      let a = self.leaf(a, path)
      let c = self.value(c, step(path, "condition"))
      let t = self.value(t, step(path, "then"))
      IfThenElse(a, c, t, self.value(e, step(path, "else")))
    }
    PatternMatch(a, subject, cases) => {
      let a = self.leaf(a, path)
      let subject = self.value(subject, step(path, "subject"))
      let cases = cases.mapi((i, c) => {
        let p = self.pattern(c.0, step(path, "cases/\{i}/pattern"))
        (p, self.value(c.1, step(path, "cases/\{i}/body")))
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
    WildcardPattern(a) => WildcardPattern(self.leaf(a, path))
    EmptyListPattern(a) => EmptyListPattern(self.leaf(a, path))
    UnitPattern(a) => UnitPattern(self.leaf(a, path))
    LiteralPattern(a, lit) => LiteralPattern(self.leaf(a, path), lit)
    AsPattern(a, inner, name) => {
      let a = self.leaf(a, path)
      AsPattern(a, self.pattern(inner, step(path, "pattern")), name)
    }
    TuplePattern(a, items) => {
      let a = self.leaf(a, path)
      TuplePattern(
        a,
        items.mapi((i, x) => self.pattern(x, step(path, "items/\{i}"))),
      )
    }
    ConstructorPattern(a, name, args) => {
      let a = self.leaf(a, path)
      let args = args.mapi((i, x) => self.pattern(x, step(path, "args/\{i}")))
      ConstructorPattern(a, name, args)
    }
    HeadTailPattern(a, head, tail) => {
      let a = self.leaf(a, path)
      let head = self.pattern(head, step(path, "head"))
      HeadTailPattern(a, head, self.pattern(tail, step(path, "tail")))
    }
  }
}

///|
/// Applies `walk` to every value declaration of `file`, with the declaration's root path
/// `value:<package>:<module>#<name>`, and rebuilds the file.
fn map_declarations(
  file : @ir.IRFile,
  walk : (@ir.ValueDefinition, String) -> @ir.ValueDefinition,
) -> @ir.IRFile {
  let rebuild = fn(
    pkg_name : @ir.PackageName,
    def : @ir.PackageDefinition,
  ) -> @ir.PackageDefinition {
    let modules : Map[
      @ir.ModuleName,
      @ir.AccessControlled[@ir.ModuleDefinition],
    ] = Map([])
    for module_, m in def.modules {
      let values : Map[
        @ir.Name,
        @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
      ] = Map([])
      for name, v in m.value.values {
        let fq : @ir.FQName = {
          package_name: pkg_name,
          module_name: module_,
          local_name: name,
        }
        let new = walk(v.value.value, "value:" + fq.to_canonical())
        values[name] = { ..v, value: { ..v.value, value: new, }, }
      }
      modules[module_] = { ..m, value: { ..m.value, values, }, }
    }
    { modules, }
  }
  let distribution : @ir.Distribution = match file.distribution {
    Library(name, deps, def) => Library(name, deps, rebuild(name, def))
    Application(name, bundled, def, entries) =>
      Application(name, bundled, rebuild(name, def), entries)
    Specs(_, _, _) => return file
  }
  @ir.IRFile::new(distribution, format_version=file.format_version) catch {
    _ => abort("the format version of the file is not valid")
  }
}

///|
/// Visits every node and signature of `file` without changing it. `signature` also sees whether the definition
/// is a let definition.
fn visit(
  file : @ir.IRFile,
  node : (@ir.ValueAttributes, String, Bool) -> Unit,
  signature : (@ir.ValueDefinition, String, Bool) -> Unit,
) -> Unit {
  map_declarations(file, (def, root) => {
    let walker : Walker = {
      node: (a, path, literal) => {
        node(a, path, literal)
        a
      },
      signature: (def, path) => {
        signature(def, path, path != root)
        def
      },
    }
    walker.definition(def, root)
  })
  |> ignore
}

///|
/// `file` with no node types for inference to use, for criterion B. Every `inferred_type` that inference walks is
/// `None`. Signatures stay: the let placeholders of a classic fixture already have the marker from the migration.
/// Classic IR does not separate annotated signatures from inferred ones, so a stripped top-level signature would
/// give a type that is correctly more general than the Elm annotation.
pub fn strip_node_types(file : @ir.IRFile) -> @ir.IRFile {
  let walker : Walker = {
    node: (a, _, _) => { ..a, inferred_type: None, },
    signature: (def, _) => def,
  }
  map_declarations(file, (def, root) => walker.definition(def, root))
}

///|
/// `file` with no types for inference to use, for criterion A. It is `strip_node_types`, and also every
/// top-level signature type is an unknown variable: `t-0`, `t-1`, … in order, counted per declaration. An
/// incomplete definition with no output type keeps `None`. Inference must then solve every signature and type
/// every node.
pub fn strip_full(file : @ir.IRFile) -> @ir.IRFile {
  map_declarations(strip_node_types(file), (def, _) => {
    let mut counter = 0
    let unknown = fn(_ : @ir.Type) -> @ir.Type {
      let t = @typing.unknown_type(@ir.Name::from_words(["t", "\{counter}"]))
      counter += 1
      t
    }
    let inputs = fn(xs : Array[(@ir.Name, @ir.Type)]) {
      xs.map(x => (x.0, unknown(x.1)))
    }
    match def {
      ExpressionBody(xs, out, body) => {
        let xs = inputs(xs)
        ExpressionBody(xs, unknown(out), body)
      }
      NativeBody(xs, out, info) => {
        let xs = inputs(xs)
        NativeBody(xs, unknown(out), info)
      }
      ExternalBody(xs, out, bindings, fallback) => {
        let xs = inputs(xs)
        ExternalBody(xs, unknown(out), bindings, fallback)
      }
      IncompleteBody(xs, out, why, value) => {
        let xs = inputs(xs)
        IncompleteBody(xs, out.map(unknown), why, value)
      }
    }
  })
}

///|
/// The signature types of a definition, keyed `<path>:input/<i>` and `<path>:output`.
fn signature_entries(
  def : @ir.ValueDefinition,
  path : String,
) -> Array[(String, @ir.Type)] {
  let (xs, out) = match def {
    ExpressionBody(xs, out, _)
    | NativeBody(xs, out, _)
    | ExternalBody(xs, out, _, _) => (xs, Some(out))
    IncompleteBody(xs, out, _, _) => (xs, out)
  }
  let entries = xs.mapi((i, x) => (path + ":input/\{i}", x.1))
  if out is Some(t) {
    entries.push((path + ":output", t))
  }
  entries
}

///|
/// `file` with the `inferred_type` of its first `Literal` value changed: to `String`, or to `Int` when it was
/// `String`. The result also holds the logical path of that node.
pub fn mutate_first_literal_type(file : @ir.IRFile) -> (@ir.IRFile, String) {
  let string_type : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:string#string") catch {
      _ => abort("string#string")
    },
    [],
  )
  let int_type : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("morphir/SDK:basics#int") catch {
      _ => abort("basics#int")
    },
    [],
  )
  let mut found : String? = None
  let walker : Walker = {
    node: (a, path, literal) => {
      guard literal && found is None else { return a }
      found = Some(path)
      let replacement = match a.inferred_type {
        Some(t) if @typing.types_equivalent(t, string_type) => int_type
        _ => string_type
      }
      { ..a, inferred_type: Some(replacement), }
    },
    signature: (def, _) => def,
  }
  let mutated = map_declarations(file, (def, path) => {
    walker.definition(def, path)
  })
  guard found is Some(path) else { abort("the file has no literal") }
  (mutated, path)
}

///|
/// The number of `Value` and `Pattern` nodes of `file` with no `inferred_type`.
pub fn count_untyped(file : @ir.IRFile) -> Int32 {
  let mut count = 0
  visit(file, (a, _, _) => if a.inferred_type is None { count += 1 }, (_, _, _) => {
    ()
  })
  count
}

///|
/// The variable names of `t`, row variables included, in first-seen order. With `unmarked`, a variable with the
/// unknown marker is left out (a row variable reads the marker of its record).
fn variables_of(
  t : @ir.Type,
  out : Array[String],
  unmarked~ : Bool = false,
) -> Unit {
  let add = fn(attrs : @ir.TypeAttributes, name : @ir.Name) {
    let marked = attrs.extensions.get("morphir.inference")
      is Some(Text("unknown"))
    if !(unmarked && marked) && !out.contains(name.to_canonical()) {
      out.push(name.to_canonical())
    }
  }
  let go = fn(x : @ir.Type) { variables_of(x, out, unmarked~) }
  match t {
    Variable(attrs, name) => add(attrs, name)
    Unit(_) => ()
    Reference(_, _, items) | Tuple(_, items) | Union(_, items) => items.each(go)
    Record(_, fields) => fields.values().each(go)
    ExtensibleRecord(attrs, row, fields) => {
      add(attrs, row)
      fields.values().each(go)
    }
    Function(_, input, output) => {
      go(input)
      go(output)
    }
  }
}

///|
/// `t` with `change` applied to each variable named `name`. A row variable is not changed.
fn map_variable(
  t : @ir.Type,
  name : String,
  change : (@ir.TypeAttributes, @ir.Name) -> @ir.Type,
) -> @ir.Type {
  let go = fn(x : @ir.Type) { map_variable(x, name, change) }
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for field, x in fields {
      out[field] = go(x)
    }
    out
  }
  match t {
    Variable(attrs, n) if n.to_canonical() == name => change(attrs, n)
    Variable(_, _) | Unit(_) => t
    Reference(attrs, n, args) => Reference(attrs, n, args.map(go))
    Tuple(attrs, items) => Tuple(attrs, items.map(go))
    Union(attrs, items) => Union(attrs, items.map(go))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) =>
      ExtensibleRecord(attrs, row, go_fields(fields))
    Function(attrs, input, output) => Function(attrs, go(input), go(output))
  }
}

///|
/// Changes the type of the first node, in walk order, that `pick` accepts. `pick` sees the node type and the
/// top-level signature of its declaration, and gives the new type or `None`. The result also holds the logical
/// path of that node.
fn mutate_first_node(
  file : @ir.IRFile,
  what : String,
  pick : (@ir.Type, @ir.ValueDefinition) -> @ir.Type?,
) -> (@ir.IRFile, String) {
  let mut found : String? = None
  let mutated = map_declarations(file, (top, root) => {
    let walker : Walker = {
      node: (a, path, _) => {
        guard found is None && a.inferred_type is Some(t) else { return a }
        guard pick(t, top) is Some(replacement) else { return a }
        found = Some(path)
        { ..a, inferred_type: Some(replacement), }
      },
      signature: (def, _) => def,
    }
    walker.definition(top, root)
  })
  guard found is Some(path) else { abort("the file has no node with \{what}") }
  (mutated, path)
}

///|
/// The variables of the top-level signature of `def` that do not carry the unknown marker.
fn signature_variables(def : @ir.ValueDefinition) -> Array[String] {
  let out : Array[String] = []
  for entry in signature_entries(def, "") {
    variables_of(entry.1, out, unmarked=true)
  }
  out
}

///|
/// `file` with the first node type that has a signature variable of its declaration changed: that variable is
/// renamed to `swapped`, and keeps its attributes. Inference gives the node the signature's own variable, so
/// check must report the node. The result also holds the logical path of that node.
pub fn mutate_first_rigid(file : @ir.IRFile) -> (@ir.IRFile, String) {
  mutate_first_node(file, "a signature variable", (t, top) => {
    let rigids = signature_variables(top)
    let names : Array[String] = []
    variables_of(t, names)
    guard names.iter().find_first(n => rigids.contains(n)) is Some(name) else {
      return None
    }
    Some(
      map_variable(t, name, (attrs, _) => {
        Variable(attrs, @ir.Name::from_words(["swapped"]))
      }),
    )
  })
}

///|
/// `file` with the first node type that has a variable with a `typeclass` constraint changed: the constraint
/// is dropped from that variable, and the name stays. The variable is chosen only when its name gives no
/// class, so the variable loses its class. The result also holds the logical path of that node.
pub fn drop_first_class(file : @ir.IRFile) -> (@ir.IRFile, String) {
  let classed = fn(t : @ir.Type) -> String? {
    let mut found : String? = None
    let names : Array[String] = []
    variables_of(t, names)
    for name in names {
      let prefixed = ["number", "comparable", "appendable", "compappend"]
        .iter()
        .any(c => name.has_prefix(c))
      guard !prefixed && found is None else { continue }
      map_variable(t, name, (attrs, n) => {
        if attrs.constraints.contains("typeclass") {
          found = Some(name)
        }
        Variable(attrs, n)
      })
      |> ignore
    }
    found
  }
  mutate_first_node(file, "a typeclass constraint", (t, _) => {
    guard classed(t) is Some(name) else { return None }
    Some(
      map_variable(t, name, (attrs, n) => {
        let constraints = attrs.constraints.copy()
        constraints.remove("typeclass")
        Variable({ ..attrs, constraints, }, n)
      }),
    )
  })
}

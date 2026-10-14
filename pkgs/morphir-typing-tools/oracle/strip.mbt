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
/// Whether `name` is a morphir-elm placeholder: `t-` followed by digits, as in `t-8`. The migration decides.
fn is_placeholder(name : @ir.Name) -> Bool {
  @migration.is_classic_placeholder(name)
}

///|
/// Whether `t` has a placeholder variable.
fn has_placeholder(t : @ir.Type) -> Bool {
  match t {
    Variable(_, name) => is_placeholder(name)
    Unit(_) => false
    Reference(_, _, items) | Tuple(_, items) =>
      items.iter().any(has_placeholder)
    Record(_, fields) => fields.values().any(has_placeholder)
    ExtensibleRecord(_, row, fields) =>
      is_placeholder(row) || fields.values().any(has_placeholder)
    Function(_, input, output) =>
      has_placeholder(input) || has_placeholder(output)
  }
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
/// Every node type and signature type of `file`, by logical path, in walk order.
fn typed_entries(file : @ir.IRFile) -> Array[(String, @ir.Type?)] {
  let out : Array[(String, @ir.Type?)] = []
  visit(file, (a, path, _) => out.push((path, a.inferred_type)), (def, path, _) => {
    for entry in signature_entries(def, path) {
      out.push((entry.0, Some(entry.1)))
    }
  })
  out
}

///|
/// The paths of the let-signature types of `file` that have a morphir-elm placeholder variable, in walk order.
fn placeholder_paths(file : @ir.IRFile) -> Array[String] {
  let out : Array[String] = []
  visit(file, (_, _, _) => (), (def, path, is_let) => {
    for entry in signature_entries(def, path) {
      if is_let && has_placeholder(entry.1) {
        out.push(entry.0)
      }
    }
  })
  out
}

///|
/// `want` and `have` with each position that is a placeholder in `want` replaced by `()` on both sides, so that
/// only the rest of the types is compared. A placeholder row variable compares only the fields that `want`
/// lists: `have` keeps only those fields, and both become closed records. Where the shapes differ, the types
/// stay as they are, and the comparison fails.
fn mask_placeholders(want : @ir.Type, have : @ir.Type) -> (@ir.Type, @ir.Type) {
  let hole : @ir.Type = Unit(Default::default())
  let fields = fn(
    want : Map[@ir.Name, @ir.Type],
    have : Map[@ir.Name, @ir.Type],
  ) -> (Map[@ir.Name, @ir.Type], Map[@ir.Name, @ir.Type]) {
    let w : Map[@ir.Name, @ir.Type] = Map([])
    let h : Map[@ir.Name, @ir.Type] = Map([])
    for name, t in want {
      match have.get(name) {
        Some(u) => {
          let (a, b) = mask_placeholders(t, u)
          w[name] = a
          h[name] = b
        }
        None => w[name] = t
      }
    }
    (w, h)
  }
  match (want, have) {
    (Variable(_, name), _) if is_placeholder(name) => (hole, hole)
    (Reference(a, n, xs), Reference(b, m, ys)) if xs.length() == ys.length() => {
      let pairs = xs.mapi((i, x) => mask_placeholders(x, ys[i]))
      (
        Reference(a, n, pairs.map(p => p.0)),
        Reference(b, m, pairs.map(p => p.1)),
      )
    }
    (Tuple(a, xs), Tuple(b, ys)) if xs.length() == ys.length() => {
      let pairs = xs.mapi((i, x) => mask_placeholders(x, ys[i]))
      (Tuple(a, pairs.map(p => p.0)), Tuple(b, pairs.map(p => p.1)))
    }
    (Function(a, i1, o1), Function(b, i2, o2)) => {
      let (wi, hi) = mask_placeholders(i1, i2)
      let (wo, ho) = mask_placeholders(o1, o2)
      (Function(a, wi, wo), Function(b, hi, ho))
    }
    (ExtensibleRecord(a, row, fs), Record(b, gs) | ExtensibleRecord(b, _, gs)) if is_placeholder(
        row,
      ) => {
      let (w, h) = fields(fs, gs)
      (Record(a, w), Record(b, h))
    }
    (Record(a, fs), Record(b, gs)) if fs.length() == gs.length() => {
      let (w, h) = fields(fs, gs)
      (Record(a, w), Record(b, h))
    }
    (ExtensibleRecord(a, r1, fs), ExtensibleRecord(b, r2, gs)) if fs.length() ==
      gs.length() => {
      let (w, h) = fields(fs, gs)
      (ExtensibleRecord(a, r1, w), ExtensibleRecord(b, r2, h))
    }
    _ => (want, have)
  }
}

///|
/// The type aliases that `file` can use: those of the SDK, of the file's dependencies and of the file's own
/// package, by canonical FQName.
fn aliases_of(file : @ir.IRFile) -> Map[String, (Array[String], @ir.Type)] {
  let out : Map[String, (Array[String], @ir.Type)] = Map([])
  let add_spec = fn(
    pkg_name : @ir.PackageName,
    spec : @ir.PackageSpecification,
  ) {
    for module_, m in spec.modules {
      for name, t in m.types {
        if t.value.body is TypeAliasSpecification(params, body) {
          let fq : @ir.FQName = {
            package_name: pkg_name,
            module_name: module_,
            local_name: name,
          }
          out[fq.to_canonical()] = (params.map(p => p.to_canonical()), body)
        }
      }
    }
  }
  let add_def = fn(pkg_name : @ir.PackageName, def : @ir.PackageDefinition) {
    for module_, m in def.modules {
      for name, t in m.value.types {
        if t.value.value is TypeAliasDefinition(params, body) {
          let fq : @ir.FQName = {
            package_name: pkg_name,
            module_name: module_,
            local_name: name,
          }
          out[fq.to_canonical()] = (params.map(p => p.to_canonical()), body)
        }
      }
    }
  }
  add_spec(@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification())
  match file.distribution {
    Library(name, deps, def) => {
      for dep, spec in deps {
        add_spec(dep, spec)
      }
      add_def(name, def)
    }
    Application(name, bundled, def, _) => {
      for dep, dep_def in bundled {
        add_def(dep, dep_def)
      }
      add_def(name, def)
    }
    Specs(name, deps, spec) => {
      for dep, dep_spec in deps {
        add_spec(dep, dep_spec)
      }
      add_spec(name, spec)
    }
  }
  out
}

///|
/// `t` with every alias reference expanded. An alias that is already being expanded stays a reference, so a
/// cyclic alias ends.
fn expand(
  aliases : Map[String, (Array[String], @ir.Type)],
  t : @ir.Type,
  active : Array[String],
) -> @ir.Type {
  let go = fn(x : @ir.Type) { expand(aliases, x, active) }
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for name, field in fields {
      out[name] = go(field)
    }
    out
  }
  match t {
    Reference(attrs, name, args) => {
      let args = args.map(go)
      let key = name.to_canonical()
      match aliases.get(key) {
        Some((params, body)) if params.length() == args.length() &&
          !active.contains(key) => {
          let bound : Map[String, @ir.Type] = Map([])
          for i, p in params {
            bound[p] = args[i]
          }
          expand(aliases, substitute(body, bound), [..active, key])
        }
        _ => Reference(attrs, name, args)
      }
    }
    Tuple(attrs, items) => Tuple(attrs, items.map(go))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) =>
      ExtensibleRecord(attrs, row, go_fields(fields))
    Function(attrs, input, output) => Function(attrs, go(input), go(output))
    Variable(_, _) | Unit(_) => t
  }
}

///|
/// `t` with each variable in `bound` replaced. A row variable bound to a variable is renamed.
fn substitute(t : @ir.Type, bound : Map[String, @ir.Type]) -> @ir.Type {
  let go = fn(x : @ir.Type) { substitute(x, bound) }
  let go_fields = fn(fields : Map[@ir.Name, @ir.Type]) {
    let out : Map[@ir.Name, @ir.Type] = Map([])
    for name, field in fields {
      out[name] = go(field)
    }
    out
  }
  match t {
    Variable(_, name) =>
      match bound.get(name.to_canonical()) {
        Some(arg) => arg
        None => t
      }
    Reference(attrs, name, args) => Reference(attrs, name, args.map(go))
    Tuple(attrs, items) => Tuple(attrs, items.map(go))
    Record(attrs, fields) => Record(attrs, go_fields(fields))
    ExtensibleRecord(attrs, row, fields) => {
      let row = match bound.get(row.to_canonical()) {
        Some(Variable(_, other)) => other
        _ => row
      }
      ExtensibleRecord(attrs, row, go_fields(fields))
    }
    Function(attrs, input, output) => Function(attrs, go(input), go(output))
    Unit(_) => t
  }
}

///|
/// A type with full canonical names, for oracle output.
fn type_text(t : @ir.Type) -> String {
  let fields_text = fn(fields : Map[@ir.Name, @ir.Type]) {
    fields
    .iter()
    .map(f => f.0.to_canonical() + " : " + type_text(f.1))
    .collect()
    .join(", ")
  }
  match t {
    Variable(_, name) => name.to_canonical()
    Reference(_, name, []) => name.to_canonical()
    Reference(_, name, args) =>
      "(" + [name.to_canonical(), ..args.map(type_text)].join(" ") + ")"
    Tuple(_, items) => "(tuple " + items.map(type_text).join(" ") + ")"
    Record(_, fields) => "{ " + fields_text(fields) + " }"
    ExtensibleRecord(_, row, fields) =>
      "{ " + row.to_canonical() + " | " + fields_text(fields) + " }"
    Function(_, input, output) =>
      "(" + type_text(input) + " -> " + type_text(output) + ")"
    Unit(_) => "()"
  }
}

///|
fn option_text(t : @ir.Type?) -> String {
  match t {
    Some(t) => type_text(t)
    None => "no type"
  }
}

///|
/// The root path `value:<package>:<module>#<name>` of a logical path: the text before the first `/` or `:` after
/// the `#`.
fn root_of(path : String) -> String {
  let chars = path.to_array()
  guard chars.search('#') is Some(hash) else { return path }
  for i = hash + 1; i < chars.length(); i = i + 1 {
    if chars[i] == '/' || chars[i] == ':' {
      return String::from_array(chars[:i])
    }
  }
  path
}

///|
/// The `@typing.TypeScope` of each declaration of `file`, by root path.
fn scopes_of(file : @ir.IRFile) -> Map[String, @typing.TypeScope] {
  let out : Map[String, @typing.TypeScope] = Map([])
  map_declarations(file, (def, root) => {
    out[root] = @typing.TypeScope::of_definition(def)
    def
  })
  |> ignore
  out
}

///|
/// The differences between the types of `original` and of `filled`, one line per node or signature type:
/// `<path>: expected <t1>, found <t2>`. Types are compared after alias expansion, in the `@typing.TypeScope` of
/// their declaration in `original`: one renaming for the whole declaration, with its signature variables fixed
/// and classes compared. A path that `original` has and `filled` lacks is a difference too. A let-signature type
/// of `original` that has a morphir-elm placeholder (see `is_placeholder`) is compared outside its
/// placeholders (see `mask_placeholders`).
pub fn compare_types(
  original : @ir.IRFile,
  filled : @ir.IRFile,
) -> Array[String] {
  let aliases = aliases_of(original)
  let scopes = scopes_of(original)
  let expected = typed_entries(original)
  let masked = placeholder_paths(original)
  let found : Map[String, @ir.Type?] = Map::from_array(typed_entries(filled))
  let out : Array[String] = []
  for entry in expected {
    let (path, want) = entry
    let have = found.get(path)
    let same = match (want, have) {
      (Some(a), Some(Some(b))) => {
        let (a, b) = (expand(aliases, a, []), expand(aliases, b, []))
        let (a, b) = if masked.contains(path) {
          mask_placeholders(a, b)
        } else {
          (a, b)
        }
        match scopes.get(root_of(path)) {
          Some(scope) => scope.equivalent(a, b)
          None => abort("no declaration for \{path}")
        }
      }
      (None, Some(None)) => true
      _ => false
    }
    if !same {
      let have_text = match have {
        Some(t) => option_text(t)
        None => "no path"
      }
      out.push("\{path}: expected \{option_text(want)}, found \{have_text}")
    }
  }
  let known : Map[String, Bool] = Map::from_array(
    typed_entries(original).map(entry => (entry.0, true)),
  )
  for path, t in found {
    if !known.contains(path) {
      out.push("\{path}: expected no path, found \{option_text(t)}")
    }
  }
  out
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
pub fn count_untyped(file : @ir.IRFile) -> Int {
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
  unmarked? : Bool = false,
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
    Reference(_, _, items) | Tuple(_, items) => items.each(go)
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

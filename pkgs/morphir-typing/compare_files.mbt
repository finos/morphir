///|
/// The differences between the types of `expected` and of `actual`, one line per node type or signature type:
/// `<path>: expected <t1>, found <t2>`. A path is the logical path of a node, or `<path>:input/<i>` and
/// `<path>:output` for the signature of a definition. A path that only one side has is a difference too:
/// `found no path` or `expected no path`, and a node without a type prints as `no type`.
///
/// The types are compared after alias expansion, with the aliases of `dependencies`, of the file's own
/// dependencies and of its own package. The types of one declaration are compared in the `TypeScope` of that
/// declaration in `expected`: one renaming for the whole declaration, with its signature variables fixed and the
/// classes compared.
///
/// A morphir-elm placeholder (`t-<digits>`, see `is_classic_placeholder_name`) in a let-signature type of
/// `expected` is not compared: each placeholder position is `()` on both sides, and a placeholder row compares only
/// the fields that `expected` lists. With `mask_signatures`, the placeholders of top-level signatures are masked
/// in the same way, and they are not fixed in the scope. morphir-elm writes such a top-level signature from a
/// first inference pass, so it is not a declared type.
pub fn compare_types(
  expected : @ir.IRFile,
  actual : @ir.IRFile,
  dependencies : Map[@ir.PackageName, @ir.PackageSpecification],
  mask_signatures? : Bool = false,
) -> Array[String] {
  let env = Env::from(dependencies, expected)
  let scopes : Map[String, TypeScope] = Map([])
  for d in collect_declarations(expected) {
    let def = if mask_signatures { mark_placeholders(d.def) } else { d.def }
    scopes[d.root] = TypeScope::of_definition(def)
  }
  let (wanted, masked) = typed_entries(expected, mask_signatures)
  let (have, _) = typed_entries(actual, mask_signatures)
  let found : Map[String, @ir.Type?] = Map::from_array(have)
  let out : Array[String] = []
  for entry in wanted {
    let (path, want) = entry
    let same = match (want, found.get(path)) {
      (Some(a), Some(Some(b))) => {
        let (a, b) = (env.expand_ir(a), env.expand_ir(b))
        let (a, b) = if masked.contains(path) {
          mask_placeholders(a, b)
        } else {
          (a, b)
        }
        match scopes.get(declaration_of(path)) {
          Some(scope) => scope.equivalent(a, b)
          None => abort("no declaration for \{path}")
        }
      }
      (None, Some(None)) => true
      _ => false
    }
    if !same {
      let have_text = match found.get(path) {
        Some(t) => option_text(t)
        None => "no path"
      }
      out.push("\{path}: expected \{option_text(want)}, found \{have_text}")
    }
  }
  let known : Map[String, Bool] = Map::from_array(
    wanted.map(entry => (entry.0, true)),
  )
  for entry in have {
    if !known.contains(entry.0) {
      out.push("\{entry.0}: expected no path, found \{option_text(entry.1)}")
    }
  }
  out
}

///|
/// Every node type and signature type of `file`, by path, in walk order: the signature of a definition comes
/// before its body. Also the signature paths whose types have a morphir-elm placeholder and are masked: those of
/// let definitions, and with `top_level` those of the declarations too.
fn typed_entries(
  file : @ir.IRFile,
  top_level : Bool,
) -> (Array[(String, @ir.Type?)], Array[String]) {
  let entries : Array[(String, @ir.Type?)] = []
  let masked : Array[String] = []
  for d in collect_declarations(file) {
    let walker : Walker = {
      node: (a, path) => {
        entries.push((path, a.inferred_type))
        a
      },
      signature: (def, path) => {
        let mask = path != d.root || top_level
        for entry in signature_entries(def, path) {
          entries.push((entry.0, Some(entry.1)))
          if mask && has_placeholder(entry.1) {
            masked.push(entry.0)
          }
        }
        def
      },
    }
    walker.definition(d.def, d.root) |> ignore
  }
  (entries, masked)
}

///|
/// The signature types of a definition, keyed `<path>:input/<i>` and `<path>:output`.
fn signature_entries(
  def : @ir.ValueDefinition,
  path : String,
) -> Array[(String, @ir.Type)] {
  let (inputs, output, _) = definition_parts(def)
  let entries = inputs.mapi((i, x) => (path + ":input/\{i}", x.1))
  if output is Some(t) {
    entries.push((path + ":output", t))
  }
  entries
}

///|
/// The logical path of the declaration of `path`: the text before the first `/` or `:` after the `#`.
fn declaration_of(path : String) -> String {
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
fn is_placeholder(name : @ir.Name) -> Bool {
  @v4.is_classic_placeholder_name(name)
}

///|
/// Whether `t` has a placeholder variable or row variable.
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
/// `def` with the unknown marker on each placeholder of its top-level signature, so that `TypeScope` does not fix
/// them. The marker of a row variable is on its record.
fn mark_placeholders(def : @ir.ValueDefinition) -> @ir.ValueDefinition {
  let inputs = (xs : Array[(@ir.Name, @ir.Type)]) => {
    xs.map(x => (x.0, mark_type(x.1)))
  }
  match def {
    ExpressionBody(xs, out, body) =>
      ExpressionBody(inputs(xs), mark_type(out), body)
    NativeBody(xs, out, info) => NativeBody(inputs(xs), mark_type(out), info)
    ExternalBody(xs, out, bindings, fallback) =>
      ExternalBody(inputs(xs), mark_type(out), bindings, fallback)
    IncompleteBody(xs, out, why, value) =>
      IncompleteBody(inputs(xs), out.map(mark_type), why, value)
  }
}

///|
fn mark_type(t : @ir.Type) -> @ir.Type {
  match t {
    Variable(a, name) if is_placeholder(name) =>
      Variable(a.with_unknown(), name)
    Variable(_, _) | Unit(_) => t
    Reference(a, name, args) => Reference(a, name, args.map(mark_type))
    Tuple(a, items) => Tuple(a, items.map(mark_type))
    Record(a, fields) => Record(a, map_fields(fields, mark_type))
    ExtensibleRecord(a, row, fields) => {
      let a = if is_placeholder(row) { a.with_unknown() } else { a }
      ExtensibleRecord(a, row, map_fields(fields, mark_type))
    }
    Function(a, input, output) =>
      Function(a, mark_type(input), mark_type(output))
  }
}

///|
/// `want` and `have` with each position that is a placeholder in `want` replaced by `()` on both sides, so that
/// only the rest of the types is compared. A placeholder row variable compares only the fields that `want`
/// lists: `have` keeps only those fields, and both become closed records. Where the shapes differ, the types
/// stay as they are, and the comparison fails.
fn mask_placeholders(want : @ir.Type, have : @ir.Type) -> (@ir.Type, @ir.Type) {
  let hole : @ir.Type = Unit(Default::default())
  let fields = (want : Map[@ir.Name, @ir.Type], have : Map[@ir.Name, @ir.Type]) => {
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
/// A type with full canonical names, for comparison lines.
fn type_text(t : @ir.Type) -> String {
  let fields_text = (fields : Map[@ir.Name, @ir.Type]) => {
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

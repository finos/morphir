///|
/// Whether `name` is a morphir-elm let placeholder: `t-` and one or more digits, as in `t-8`.
///
/// morphir-elm writes a signature for every let definition. When the Elm source has no annotation for the let,
/// the signature keeps the variables that the frontend made before inference (`t8`, canonical `t-8`), and the
/// solved types are only on the nodes. Classic IR cannot say that these variables are unknown, so migration to
/// v4 marks them.
pub fn is_classic_placeholder(name : @current.Name) -> Bool {
  @current.is_classic_placeholder_name(name)
}

///|
/// `t` with the unknown marker on each classic placeholder variable. A placeholder row variable marks its
/// record, because inference reads a row variable's marker from the record's attributes.
fn mark_type(t : @current.Type) -> @current.Type {
  let fields = fn(fs : Map[@current.Name, @current.Type]) {
    let out : Map[@current.Name, @current.Type] = Map([])
    for n, f in fs {
      out[n] = mark_type(f)
    }
    out
  }
  match t {
    Variable(a, n) if is_classic_placeholder(n) => Variable(a.with_unknown(), n)
    Variable(_, _) | Unit(_) => t
    Reference(a, n, args) => Reference(a, n, args.map(mark_type))
    Tuple(a, items) => Tuple(a, items.map(mark_type))
    Union(a, items) => Union(a, items.map(mark_type))
    Record(a, fs) => Record(a, fields(fs))
    ExtensibleRecord(a, row, fs) => {
      let a = if is_classic_placeholder(row) { a.with_unknown() } else { a }
      ExtensibleRecord(a, row, fields(fs))
    }
    Function(a, x, y) => Function(a, mark_type(x), mark_type(y))
  }
}

///|
/// A definition with its signature marked (`let_signature`) and the let definitions of its body marked.
fn mark_definition(
  def : @current.ValueDefinition,
  let_signature : Bool,
) -> @current.ValueDefinition {
  let sig = fn(t : @current.Type) {
    if let_signature {
      mark_type(t)
    } else {
      t
    }
  }
  let ins = fn(xs : Array[(@current.Name, @current.Type)]) {
    xs.map(x => (x.0, sig(x.1)))
  }
  match def {
    ExpressionBody(xs, out, body) =>
      ExpressionBody(ins(xs), sig(out), mark_value(body))
    NativeBody(xs, out, info) => NativeBody(ins(xs), sig(out), info)
    ExternalBody(xs, out, bindings, body) =>
      ExternalBody(ins(xs), sig(out), bindings, body.map(mark_value))
    IncompleteBody(xs, out, why, body) =>
      IncompleteBody(ins(xs), out.map(sig), why, body.map(mark_value))
  }
}

///|
/// `v` with the signature of every let definition in it marked.
fn mark_value(v : @current.Value) -> @current.Value {
  let map_fields = fn(fs : Map[@current.Name, @current.Value]) {
    let out : Map[@current.Name, @current.Value] = Map([])
    for n, f in fs {
      out[n] = mark_value(f)
    }
    out
  }
  match v {
    LetDefinition(a, n, def, rest) =>
      LetDefinition(a, n, mark_definition(def, true), mark_value(rest))
    LetRecursion(a, defs, rest) => {
      let out : Map[@current.Name, @current.ValueDefinition] = Map([])
      for n, def in defs {
        out[n] = mark_definition(def, true)
      }
      LetRecursion(a, out, mark_value(rest))
    }
    Tuple(a, items) => Tuple(a, items.map(mark_value))
    List(a, items) => List(a, items.map(mark_value))
    Record(a, fs) => Record(a, map_fields(fs))
    Field(a, r, n) => Field(a, mark_value(r), n)
    Apply(a, f, x) => Apply(a, mark_value(f), mark_value(x))
    Lambda(a, p, body) => Lambda(a, p, mark_value(body))
    Destructure(a, p, x, rest) =>
      Destructure(a, p, mark_value(x), mark_value(rest))
    IfThenElse(a, c, t, e) =>
      IfThenElse(a, mark_value(c), mark_value(t), mark_value(e))
    PatternMatch(a, s, cases) =>
      PatternMatch(a, mark_value(s), cases.map(c => (c.0, mark_value(c.1))))
    UpdateRecord(a, r, fs) => UpdateRecord(a, mark_value(r), map_fields(fs))
    Literal(_, _)
    | Constructor(_, _)
    | Variable(_, _)
    | Reference(_, _)
    | FieldFunction(_, _)
    | Unit(_)
    | Hole(_, _, _) => v
  }
}

///|
/// A file migrated from classic IR, with its let placeholders marked. Top-level signatures are not changed.
fn mark_classic_let_placeholders(
  file : @current.IRFile,
) -> @current.IRFile raise {
  guard file.distribution is Library(name, deps, def) else { return file }
  let modules = def.modules.map(fn(_, m) {
    let values = m.value.values.map(fn(_, v) {
      {
        ..v,
        value: { ..v.value, value: mark_definition(v.value.value, false), },
      }
    })
    { ..m, value: { ..m.value, values, }, }
  })
  let def : @current.PackageDefinition = { modules, }
  @current.IRFile::new(
    Library(name, deps, def),
    format_version=file.format_version,
  )
}

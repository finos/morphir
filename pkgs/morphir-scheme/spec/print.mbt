///|
fn quote(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn print_reference(name : @ir.FQName, package_name : @ir.Path) -> String {
  let local_name = name.module_name.to_canonical() +
    "#" +
    name.local_name.to_canonical()
  if name.package_name == package_name {
    local_name
  } else {
    name.package_name.to_canonical() + ":" + local_name
  }
}

///|
fn print_fields(
  fields : Map[@ir.Name, @ir.Type],
  package_name : @ir.Path,
) -> Array[String] {
  fields
  .iter()
  .map(kv => "(\{kv.0.to_canonical()} \{print_type(kv.1, package_name~)})")
  .collect()
}

///|
pub fn print_type(t : @ir.Type, package_name~ : @ir.PackageName) -> String {
  match t {
    Variable(_, name) => name.to_canonical()
    Unit(_) => "()"
    Reference(_, name, []) => print_reference(name, package_name)
    Reference(_, name, args) =>
      "(" +
      [
        print_reference(name, package_name),
        ..args.map(a => print_type(a, package_name~)),
      ].join(" ") +
      ")"
    Tuple(_, items) =>
      "(" +
      ["tuple", ..items.map(a => print_type(a, package_name~))].join(" ") +
      ")"
    Union(_, items) =>
      "(union " + items.map(a => print_type(a, package_name~)).join(" ") + ")"
    Record(_, fields) =>
      "(" + ["record", ..print_fields(fields, package_name)].join(" ") + ")"
    ExtensibleRecord(_, base, fields) =>
      "(" +
      ["record", base.to_canonical(), ..print_fields(fields, package_name)].join(
        " ",
      ) +
      ")"
    Function(_, _, _) => {
      let parts : Array[String] = ["->"]
      let mut current = t
      while current is Function(_, argument, result) {
        parts.push(print_type(argument, package_name~))
        current = result
      }
      parts.push(print_type(current, package_name~))
      "(" + parts.join(" ") + ")"
    }
  }
}

///|
fn print_literal(literal : @ir.Literal) -> String {
  match literal {
    StringLiteral(s) => quote(s)
    IntegerLiteral(s) => s
    BoolLiteral(true) => "#t"
    BoolLiteral(false) => "#f"
    DecimalLiteral(s) => s
    FloatLiteral(d) => d.to_string()
    CharLiteral(c) => "#\\\{c}"
    DocumentLiteral(_) => "()"
  }
}

///|
fn print_data(value : @ir.Value) -> String {
  match value {
    Literal(_, literal) => print_literal(literal)
    List(_, items) => "(" + items.map(print_data).join(" ") + ")"
    _ => "()"
  }
}

///|
fn print_annotation(annotation : @ir.Annotation) -> String {
  match annotation {
    Compact(name, None) => "(annotation \{name.to_canonical()})"
    Compact(name, Some(text)) =>
      "(annotation \{name.to_canonical()} \{quote(text)})"
    Structured(name, args) => {
      let parts = ["annotation", name.to_canonical()]
      for arg in args {
        match arg {
          Positional(v) => parts.push(print_data(v))
          Named(_, v) => parts.push(print_data(v))
        }
      }
      "(" + parts.join(" ") + ")"
    }
  }
}

///|
fn print_type_item(
  name : @ir.Name,
  documented : @ir.Documented[@ir.TypeSpecification],
  package_name : @ir.Path,
) -> String {
  let spec = documented.value
  let (body, params) = match spec.body {
    OpaqueTypeSpecification(params) => ("(opaque)", params)
    TypeAliasSpecification(params, target) =>
      ("(alias \{print_type(target, package_name~)})", params)
    CustomTypeSpecification(params, ctors) => {
      let parts = ["custom"]
      for ctor in ctors {
        let (ctor_name, args) = ctor
        let inner = [
          ctor_name.to_canonical(),
          ..args.map(a => print_type(a.1, package_name~)),
        ]
        parts.push("(" + inner.join(" ") + ")")
      }
      ("(" + parts.join(" ") + ")", params)
    }
    DerivedTypeSpecification(params, details) =>
      (
        "(derived \{print_type(details.base_type, package_name~)} " +
        "\{print_reference(details.from_base_type, package_name)} " +
        "\{print_reference(details.to_base_type, package_name)})",
        params,
      )
  }
  let parts = ["(type", name.to_canonical()]
  if documented.doc is Some(text) {
    parts.push("(doc \{quote(text)})")
  }
  parts.push(body)
  for p in params {
    parts.push(p.to_canonical())
  }
  parts.join(" ") + ")"
}

///|
fn print_value_item(
  name : @ir.Name,
  documented : @ir.Documented[@ir.ValueSpecification],
  package_name : @ir.Path,
  indent : String,
) -> String {
  let spec = documented.value
  let params = spec.inputs
    .map(i => "(\{i.0.to_canonical()} \{print_type(i.1, package_name~)})")
    .join(" ")
  let out = StringBuilder()
  out.write_string(
    "(val \{name.to_canonical()} (\{params}) \{print_type(spec.output, package_name~)}",
  )
  if documented.doc is Some(text) {
    out.write_string("\n\{indent}  (doc \{quote(text)})")
  }
  for a in spec.annotations {
    out.write_string("\n\{indent}  \{print_annotation(a)}")
  }
  out.write_char(')')
  out.to_string()
}

///|
/// Prints a package in the canonical layout of the notation.
///
/// The round trip is lossless only for values that `read_package` produces.
/// The printer drops or changes these parts of other values:
/// - constructor argument names, which print as `arg-N` on reading;
/// - the names of `Named` annotation arguments;
/// - module annotations and type annotations;
/// - annotation data other than literals and lists (written as `()`);
/// - the text of a `Compact` annotation (written as an argument, so it reads back as `Structured`).
pub fn print_package(
  name : @ir.PackageName,
  spec : @ir.PackageSpecification,
) -> String {
  let out = StringBuilder()
  out.write_string("(package \{quote(name.to_canonical())}")
  for entry in spec.modules {
    let (path, module_) = entry
    out.write_string("\n  (module \{path.to_canonical()}")
    if module_.doc is Some(text) {
      out.write_string("\n    (doc \{quote(text)})")
    }
    for t in module_.types {
      out.write_string("\n    \{print_type_item(t.0, t.1, name)}")
    }
    for v in module_.values {
      out.write_string("\n    \{print_value_item(v.0, v.1, name, "    ")}")
    }
    out.write_char(')')
  }
  out.write_char(')')
  out.to_string()
}

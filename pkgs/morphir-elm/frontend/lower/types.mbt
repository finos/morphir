///|
let classes : Array[String] = [
  "compappend", "appendable", "comparable", "number",
]

///|
pub fn type_attributes(range : @ast.Range) -> @ir.TypeAttributes {
  {
    ..@ir.TypeAttributes::default(),
    source: Some({
      start_line: range.start.row,
      start_column: range.start.column,
      end_line: range.end.row,
      end_column: range.end.column,
    }),
  }
}

///|
fn variable(range : @ast.Range, name : String) -> @ir.Type {
  let attrs = type_attributes(range)
  match classes.iter().find_first(c => name.has_prefix(c)) {
    Some(class) => {
      let constraints = Map::from_array([("typeclass", @ir.Data::Text(class))])
      Variable({ ..attrs, constraints, }, @mapping.elm_name(name))
    }
    None => Variable(attrs, @mapping.elm_name(name))
  }
}

///|
pub fn lower_type(
  scope : @resolve.Scope,
  node : @ast.Node[@ast.TypeAnnotation],
  declared : Array[String]?,
) -> @ir.Type raise LowerError {
  let attrs = type_attributes(node.range)
  match node.value {
    GenericType(v) => {
      if declared is Some(names) && !names.contains(v) {
        raise LowerError(
          "elm.unbound_type_variable",
          "the type variable \{v} is not declared",
          Some(node.range),
        )
      }
      variable(node.range, v)
    }
    Typed(name, args) => {
      let fq = scope.resolve_type(name.value.0.to_owned(), name.value.1) catch {
        @resolve.ResolveError(code, message) =>
          raise LowerError(code, message, Some(name.range))
      }
      Reference(attrs, fq, lower_all(scope, args, declared))
    }
    Unit => Unit(attrs)
    Tupled(items) =>
      match items.length() {
        0 => Unit(attrs)
        1 => lower_type(scope, items[0], declared)
        _ => Tuple(attrs, lower_all(scope, items, declared))
      }
    Record(fields) => Record(attrs, lower_fields(scope, fields, declared))
    GenericRecord(row, fields) => {
      if declared is Some(names) && !names.contains(row.value) {
        raise LowerError(
          "elm.unbound_type_variable",
          "the type variable \{row.value} is not declared",
          Some(row.range),
        )
      }
      ExtensibleRecord(
        attrs,
        @mapping.elm_name(row.value),
        lower_fields(scope, fields.value, declared),
      )
    }
    FunctionTypeAnnotation(a, b) =>
      Function(
        attrs,
        lower_type(scope, a, declared),
        lower_type(scope, b, declared),
      )
  }
}

///|
fn lower_all(
  scope : @resolve.Scope,
  items : ArrayView[@ast.Node[@ast.TypeAnnotation]],
  declared : Array[String]?,
) -> Array[@ir.Type] raise LowerError {
  let out : Array[@ir.Type] = []
  for item in items {
    out.push(lower_type(scope, item, declared))
  }
  out
}

///|
fn lower_fields(
  scope : @resolve.Scope,
  fields : @ast.RecordDefinition,
  declared : Array[String]?,
) -> Map[@ir.Name, @ir.Type] raise LowerError {
  let out : Map[@ir.Name, @ir.Type] = Map::from_array([])
  for f in fields {
    out[@mapping.elm_name(f.value.name.value)] = lower_type(
      scope,
      f.value.type_annotation,
      declared,
    )
  }
  out
}

///|
pub fn lower_type_definition(
  scope : @resolve.Scope,
  declaration : @ast.Declaration,
) -> (String, @ir.TypeDefinition, String?)? raise LowerError {
  match declaration {
    AliasDeclaration(a) => {
      let generics = a.generics.iter().map(g => g.value).collect()
      let body = lower_type(scope, a.type_annotation, Some(generics))
      Some(
        (
          a.name.value,
          TypeAliasDefinition(generics.map(@mapping.elm_name), body),
          doc_text(a.documentation),
        ),
      )
    }
    CustomTypeDeclaration(t) => {
      let generics = t.generics.iter().map(g => g.value).collect()
      let ctors : Map[@ir.Name, Array[(@ir.Name, @ir.Type)]] = Map::from_array([])
      for c in t.constructors {
        let args : Array[(@ir.Name, @ir.Type)] = []
        for i, a in c.value.arguments {
          args.push(
            (
              @mapping.elm_name("arg" + (i + 1).to_string()),
              lower_type(scope, a, Some(generics)),
            ),
          )
        }
        ctors[@mapping.elm_name(c.value.name.value)] = args
      }
      Some(
        (
          t.name.value,
          CustomTypeDefinition(generics.map(@mapping.elm_name), {
            access: Public,
            value: ctors,
          }),
          doc_text(t.documentation),
        ),
      )
    }
    _ => None
  }
}

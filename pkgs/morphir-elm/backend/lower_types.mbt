///|
fn check_tuple_arity(
  count : Int32,
  at : String,
) -> Unit raise ElmGenerationError {
  if count < 2 || count > 3 {
    refuse(
      "tuple_arity",
      at,
      "Elm tuples have 2 or 3 elements, not " + count.to_string(),
    )
  }
}

///|
fn lower_type(
  ctx : Ctx,
  t : @ir.Type,
  at : String,
) -> @ast.TypeAnnotation raise ElmGenerationError {
  match t {
    Union(_, _) =>
      refuse(
        "unsupported_type", at, "Untagged unions are not supported by Elm generation",
      )
    Variable(attributes, name) =>
      match ctx.type_variables.get(name.to_canonical()) {
        Some(elm_name) => GenericType(elm_name)
        None =>
          GenericType(type_variable_name(name, constraint_of(attributes, at)))
      }
    Reference(_, name, args) =>
      match ctx.resolve(name, TypeName) {
        Qualified(qualifier, local_text) =>
          Typed(
            node((qualifier[:], local_text)),
            args.map(a => node(lower_type(ctx, a, at)))[:],
          )
        Op(op) =>
          refuse(
            "invalid_mapping",
            at,
            "type " + name.to_canonical() + " maps to operator " + op,
          )
      }
    Tuple(_, items) => {
      check_tuple_arity(items.length(), at)
      Tupled(items.map(i => node(lower_type(ctx, i, at)))[:])
    }
    Record(_, fields) => Record(record_fields(ctx, fields, at))
    ExtensibleRecord(_, variable, fields) =>
      GenericRecord(
        node(
          ctx.type_variables
          .get(variable.to_canonical())
          .unwrap_or(value_name(variable)),
        ),
        node(record_fields(ctx, fields, at)),
      )
    Function(_, input, output) =>
      FunctionTypeAnnotation(
        node(lower_type(ctx, input, at)),
        node(lower_type(ctx, output, at)),
      )
    Unit(_) => Unit
  }
}

///|
/// Two Morphir fields that print as one Elm field make a record Elm rejects.
fn check_field_collisions(
  names : Iter[@ir.Name],
  at : String,
) -> Unit raise ElmGenerationError {
  let seen : Map[String, Bool] = Map([])
  for name in names {
    let elm_name = value_name(name)
    if seen.contains(elm_name) {
      refuse("name_collision", at, "another record field is also " + elm_name)
    }
    seen[elm_name] = true
  }
}

///|
fn record_fields(
  ctx : Ctx,
  fields : Map[@ir.Name, @ir.Type],
  at : String,
) -> ArrayView[@ast.Node[@ast.RecordField]] raise ElmGenerationError {
  check_field_collisions(fields.keys(), at)
  let result = []
  for name, field_type in fields {
    result.push(
      node(@ast.RecordField::{
        name: node(value_name(name)),
        type_annotation: node(lower_type(ctx, field_type, at)),
      }),
    )
  }
  result[:]
}

///|
fn constructors_of(
  ctx : Ctx,
  constructors : @ir.Constructors,
  at : String,
) -> ArrayView[@ast.Node[@ast.ValueConstructor]] raise ElmGenerationError {
  let result = []
  for name, args in constructors {
    result.push(
      node(@ast.ValueConstructor::{
        name: node(type_name(name)),
        arguments: args.map(arg => node(lower_type(ctx, arg.1, at)))[:],
      }),
    )
  }
  result[:]
}

///|
/// Find the constraint of each type variable in `t`. A variable gets the constraint of any occurrence.
fn collect_constraints(
  t : @ir.Type,
  found : Map[String, (@ir.Name, String?)],
  at : String,
) -> Unit raise ElmGenerationError {
  match t {
    Union(_, _) =>
      refuse(
        "unsupported_type", at, "Untagged unions are not supported by Elm generation",
      )
    Variable(attributes, name) => {
      let key = name.to_canonical()
      let constraint = constraint_of(attributes, at)
      match (found.get(key), constraint) {
        (None, _) | (Some((_, None)), _) => found[key] = (name, constraint)
        (Some((_, Some(existing))), Some(other)) if existing != other =>
          refuse(
            "unsupported_constraint",
            at,
            "type variable " + key + " is both " + existing + " and " + other,
          )
        (Some(_), _) => ()
      }
    }
    Reference(_, _, args) =>
      for a in args {
        collect_constraints(a, found, at)
      }
    Tuple(_, items) =>
      for i in items {
        collect_constraints(i, found, at)
      }
    Record(_, fields) =>
      for _, f in fields {
        collect_constraints(f, found, at)
      }
    ExtensibleRecord(_, variable, fields) => {
      if !found.contains(variable.to_canonical()) {
        found[variable.to_canonical()] = (variable, None)
      }
      for _, f in fields {
        collect_constraints(f, found, at)
      }
    }
    Function(_, input, output) => {
      collect_constraints(input, found, at)
      collect_constraints(output, found, at)
    }
    Unit(_) => ()
  }
}

///|
/// Lower with one Elm name for each type variable of the declaration, so that the parameter list,
/// the body and every occurrence agree.
fn[T] Ctx::with_type_variables(
  self : Ctx,
  params : Array[@ir.Name],
  types : Array[@ir.Type],
  at : String,
  body : () -> T raise ElmGenerationError,
) -> T raise ElmGenerationError {
  let found : Map[String, (@ir.Name, String?)] = Map([])
  for p in params {
    found[p.to_canonical()] = (p, None)
  }
  for t in types {
    collect_constraints(t, found, at)
  }
  let names : Map[String, String] = Map([])
  for key, entry in found {
    names[key] = type_variable_name(entry.0, entry.1)
  }
  let saved = self.type_variables
  self.type_variables = names
  defer {
    self.type_variables = saved
  }
  body()
}

///|
fn generics(
  ctx : Ctx,
  params : Array[@ir.Name],
) -> ArrayView[@ast.Node[String]] {
  params.map(p => {
    node(ctx.type_variables.get(p.to_canonical()).unwrap_or(value_name(p)))
  })[:]
}

///|
fn custom_type(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  params : Array[@ir.Name],
  constructors : @ir.Constructors,
  at : String,
) -> @ast.Declaration raise ElmGenerationError {
  if constructors.is_empty() {
    refuse("placeholder", at, "a custom type needs at least one constructor")
  }
  let types = []
  for _, args in constructors {
    for arg in args {
      types.push(arg.1)
    }
  }
  ctx.with_type_variables(params, types, at, fn() raise ElmGenerationError {
    CustomTypeDeclaration({
      documentation: doc_comment(doc, []),
      name: node(type_name(name)),
      generics: generics(ctx, params),
      constructors: constructors_of(ctx, constructors, at),
    })
  })
}

///|
fn lower_alias(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  params : Array[@ir.Name],
  body : @ir.Type,
  at : String,
) -> @ast.Declaration raise ElmGenerationError {
  ctx.with_type_variables(params, [body], at, fn() raise ElmGenerationError {
    AliasDeclaration({
      documentation: doc_comment(doc, []),
      name: node(type_name(name)),
      generics: generics(ctx, params),
      type_annotation: node(lower_type(ctx, body, at)),
    })
  })
}

///|
fn lower_type_definition(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  definition : @ir.TypeDefinition,
  at : String,
) -> (@ast.Declaration, @ast.TopLevelExpose?) raise ElmGenerationError {
  match definition {
    TypeAliasDefinition(params, body) =>
      (
        lower_alias(ctx, name, doc, params, body, at),
        Some(TypeOrAliasExpose(type_name(name))),
      )
    CustomTypeDefinition(params, constructors) => {
      let declaration = custom_type(
        ctx,
        name,
        doc,
        params,
        constructors.value,
        at,
      )
      let expose : @ast.TopLevelExpose = if constructors.access is Public {
        TypeExpose({ name: type_name(name), open: Some(zero), })
      } else {
        TypeOrAliasExpose(type_name(name))
      }
      (declaration, Some(expose))
    }
    IncompleteTypeDefinition(_, _, _) =>
      refuse("placeholder", at, "an incomplete type definition has no Elm form")
  }
}

///|
fn lower_type_specification(
  ctx : Ctx,
  name : @ir.Name,
  doc : String?,
  spec : @ir.TypeSpecification,
  at : String,
) -> (@ast.Declaration, @ast.TopLevelExpose) raise ElmGenerationError {
  match spec.body {
    TypeAliasSpecification(params, body) =>
      (
        lower_alias(ctx, name, doc, params, body, at),
        TypeOrAliasExpose(type_name(name)),
      )
    OpaqueTypeSpecification(params) => {
      // A hidden constructor keeps the type opaque to other modules.
      let hidden = @ir.Name::parse(name.to_canonical() + "-opaque") catch {
        _ => refuse("print", at, "cannot name the opaque constructor")
      }
      let declaration = custom_type(
        ctx,
        name,
        doc,
        params,
        Map::from_array([(hidden, [])]),
        at,
      )
      (declaration, TypeOrAliasExpose(type_name(name)))
    }
    CustomTypeSpecification(params, constructors) =>
      (
        custom_type(ctx, name, doc, params, constructors, at),
        TypeExpose({ name: type_name(name), open: Some(zero), }),
      )
    DerivedTypeSpecification(_, _) =>
      refuse("derived_type", at, "derived types are not supported yet")
  }
}

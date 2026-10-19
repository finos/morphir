///|
fn type_attrs(tpe : @ir.Type) -> @ir.TypeAttributes {
  match tpe {
    Variable(a, _)
    | Reference(a, _, _)
    | Tuple(a, _)
    | Union(a, _)
    | Record(a, _)
    | ExtensibleRecord(a, _, _)
    | Function(a, _, _)
    | Unit(a) => a
  }
}

///|
fn lower_type(
  ctx : Lowering,
  tpe : @ir.Type,
  context : String,
  trail~ : Array[@ir.FQName] = [],
) -> Lowered raise {
  if !type_attrs(tpe).constraints.is_empty() {
    raise Invalid(
      "moonbit.unsupported_constraint", context, "Type constraints require a registered lowering",
    )
  }
  match tpe {
    Variable(_, _) =>
      raise Invalid(
        "moonbit.ambiguous_type", context, "Generic types require specialization before generation",
      )
    Union(_, _) =>
      raise Invalid(
        "moonbit.unsupported_type", context, "Untagged unions are not supported by MoonBit generation",
      )
    ExtensibleRecord(_, _, _) =>
      raise Invalid(
        "moonbit.unsupported_type", context, "Open records require specialization",
      )
    Function(_, a, b) =>
      Arrow(
        lower_type(ctx, a, context, trail~),
        lower_type(ctx, b, context, trail~),
      )
    Tuple(_, members) => {
      if members.length() < 2 {
        raise Invalid(
          "moonbit.unsupported_type", context, "Tuple arity must be at least two",
        )
      }
      Product(members.map(t => lower_type(ctx, t, context, trail~)))
    }
    Record(_, fields) => {
      let names = fields.keys().collect()
      names.sort()
      let lowered = names.map(n => {
        validate_name(n)
        (n, lower_type(ctx, fields[n], context, trail~))
      })
      let key = "T_r_" +
        hex(
          lowered.map(p => p.0.to_canonical() + ":" + lower_key(p.1)).join(";"),
        )
      allocate_fields(ctx.names, key, names)
      ctx.shapes[key] = lowered
      Shape(key, lowered)
    }
    Unit(_) => Atom(Scalar::Unit)
    Reference(_, name, args) => {
      ignore(value_name(name))
      match name.to_canonical() {
        "morphir/SDK:list#list" if args.length() == 1 =>
          Sequence(lower_type(ctx, args[0], context, trail~))
        "morphir/SDK:maybe#maybe" if args.length() == 1 =>
          Optional(lower_type(ctx, args[0], context, trail~))
        "morphir/SDK:result#result" if args.length() == 2 =>
          Outcome(
            lower_type(ctx, args[1], context, trail~),
            lower_type(ctx, args[0], context, trail~),
          )
        _ => {
          if !args.is_empty() {
            raise Invalid(
              "moonbit.unsupported_type", context, "Parameterized user types require specialization",
            )
          }
          match ctx.types.get(name) {
            Some(entry) => {
              let owner = name.package_name.to_canonical() +
                ":" +
                name.module_name.to_canonical() +
                "#"
              if !entry.exposed &&
                !context.has_prefix("value:" + owner) &&
                !context.has_prefix("type:" + owner) {
                raise Invalid(
                  "moonbit.inaccessible_type",
                  context,
                  name.to_canonical(),
                )
              }
              match entry.definition {
                TypeAliasDefinition(params, target) => {
                  if !params.is_empty() || trail.contains(name) {
                    raise Invalid(
                      "moonbit.unsupported_type", context, "Generic or cyclic alias",
                    )
                  }
                  lower_type(ctx, target, context, trail=trail + [name])
                }
                CustomTypeDefinition(params, _) => {
                  if !params.is_empty() {
                    raise Invalid(
                      "moonbit.unsupported_type", context, "Generic custom type",
                    )
                  }
                  Nominal(name)
                }
                _ =>
                  raise Invalid(
                    "moonbit.incomplete_type",
                    context,
                    name.to_canonical(),
                  )
              }
            }
            None => {
              if name.to_canonical() == "morphir/moonbit-source:float32#float32" &&
                !ctx.source_extensions.contains("float32") {
                raise Invalid(
                  "moonbit.missing_source_extension",
                  context,
                  name.to_canonical(),
                )
              }
              Atom(scalar_type(tpe, context))
            }
          }
        }
      }
    }
  }
}

///|
fn lower_key(tpe : Lowered) -> String {
  match tpe {
    Atom(s) =>
      match s {
        SignedInt32 => "sdk-int32"
        BoundedInteger(name) => "sdk-" + name
        Integer => "int"
        Float => "float"
        Float32 => "float32"
        Boolean => "bool"
        Text => "text"
        Character => "char"
        Decimal => "decimal"
        Unit => "unit"
      }
    Product(xs) => "tuple(" + xs.map(lower_key).join(",") + ")"
    Shape(n, _) => n
    Arrow(a, b) => "fn(" + lower_key(a) + "," + lower_key(b) + ")"
    Sequence(a) => "list(" + lower_key(a) + ")"
    Optional(a) => "maybe(" + lower_key(a) + ")"
    Outcome(a, e) => "result(" + lower_key(a) + "," + lower_key(e) + ")"
    Nominal(n) => "type(" + n.to_canonical() + ")"
  }
}

///|
fn type_source(ctx : Lowering, tpe : Lowered) -> String {
  match tpe {
    Atom(s) => moon_type(s, ctx.imports)
    Product(xs) => "(" + xs.map(t => type_source(ctx, t)).join(", ") + ")"
    Shape(n, _) => n
    Arrow(a, b) =>
      "((" +
      type_source(ctx, a) +
      ") -> " +
      type_source(ctx, b) +
      " raise @sdk.SdkError)"
    Sequence(a) => {
      ctx.imports["list"] = true
      "@list.List[" + type_source(ctx, a) + "]"
    }
    Optional(a) => "Option[" + type_source(ctx, a) + "]"
    Outcome(a, e) =>
      "Result[" + type_source(ctx, a) + ", " + type_source(ctx, e) + "]"
    Nominal(n) => ctx.names.names["type:" + n.to_canonical()]
  }
}

///|
fn curry_type(inputs : Array[Lowered], output : Lowered) -> Lowered {
  let mut result = output
  for i = inputs.length() - 1; i >= 0; i = i - 1 {
    result = Arrow(inputs[i], result)
  }
  result
}

///|
fn local_name(name : @ir.Name) -> String raise {
  validate_name(name)
  "x_" + hex(name.to_canonical())
}

///|
fn field_name(ctx : Lowering, shape : String, name : @ir.Name) -> String {
  ctx.names.fields[shape][name]
}

///|
fn curry_source(
  ctx : Lowering,
  inputs : Array[(String, Lowered)],
  output : Lowered,
  body : String,
) -> String {
  let mut source = body
  let mut result = output
  for i = inputs.length() - 1; i >= 0; i = i - 1 {
    source = "fn(" +
      inputs[i].0 +
      " : " +
      type_source(ctx, inputs[i].1) +
      ") -> " +
      type_source(ctx, result) +
      " raise @sdk.SdkError { " +
      source +
      " }"
    result = Arrow(inputs[i].1, result)
  }
  source
}

///|
/// Marks what a `pub` declaration exposes: record shapes become `pub(all)`, and a type that is not `public` is
/// emitted abstract. MoonBit refuses a `pub` signature that names a `priv` type, but an abstract type is visible to
/// other packages without its constructors.
fn export_type(ctx : Lowering, tpe : Lowered) -> Unit {
  match tpe {
    Nominal(name) =>
      if !ctx.types[name].public {
        ctx.abstract_types[name] = true
      }
    Arrow(a, b) | Outcome(a, b) => {
      export_type(ctx, a)
      export_type(ctx, b)
    }
    Product(xs) =>
      for t in xs {
        export_type(ctx, t)
      }
    Shape(name, fields) => {
      ctx.exported_shapes[name] = true
      for field in fields {
        export_type(ctx, field.1)
      }
    }
    Optional(t) | Sequence(t) => export_type(ctx, t)
    Atom(_) => ()
  }
}

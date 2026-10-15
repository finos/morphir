///|
fn value_attrs(value : @ir.Value) -> @ir.ValueAttributes {
  match value {
    Literal(a, _)
    | Constructor(a, _)
    | Tuple(a, _)
    | List(a, _)
    | Record(a, _)
    | Variable(a, _)
    | Reference(a, _)
    | Field(a, _, _)
    | FieldFunction(a, _)
    | Apply(a, _, _)
    | Lambda(a, _, _)
    | LetDefinition(a, _, _, _)
    | LetRecursion(a, _, _)
    | Destructure(a, _, _, _)
    | IfThenElse(a, _, _, _)
    | PatternMatch(a, _, _)
    | UpdateRecord(a, _, _)
    | Unit(a)
    | Hole(a, _, _) => a
  }
}

///|
fn inferred(
  ctx : Lowering,
  value : @ir.Value,
  env : Map[@ir.Name, Lowered],
  context : String,
) -> Lowered raise {
  if value_attrs(value).inferred_type is Some(tpe) {
    return lower_type(ctx, tpe, context)
  }
  match value {
    Variable(_, n) =>
      match env.get(n) {
        Some(t) => t
        None =>
          raise Invalid("moonbit.unbound_variable", context, n.to_canonical())
      }
    Reference(_, n) =>
      match ctx.values.get(n) {
        Some(d) => curry_type(d.inputs.map(p => p.1), d.output)
        None =>
          raise Invalid(
            "moonbit.ambiguous_type", context, "SDK references require a concrete inferred signature",
          )
      }
    Constructor(_, n) =>
      match ctx.constructors.get(n) {
        Some(c) => curry_type(c.inputs, c.output)
        None =>
          raise Invalid(
            "moonbit.unresolved_constructor",
            context,
            n.to_canonical(),
          )
      }
    Literal(_, lit) =>
      Atom(
        match lit {
          IntegerLiteral(_) => Integer
          DecimalLiteral(_) => Decimal
          FloatLiteral(_) => Float
          StringLiteral(_) => Text
          CharLiteral(_) => Character
          BoolLiteral(_) => Boolean
          DocumentLiteral(_) =>
            raise Invalid(
              "moonbit.unsupported_literal", context, "Document literal",
            )
        },
      )
    Unit(_) => Atom(Scalar::Unit)
    Apply(_, f, _) =>
      match inferred(ctx, f, env, context) {
        Arrow(_, b) => b
        _ =>
          raise Invalid(
            "moonbit.type_mismatch", context, "Applied expression is not a function",
          )
      }
    Field(_, r, n) =>
      match inferred(ctx, r, env, context) {
        Shape(_, fs) =>
          match fs.iter().find_first(p => p.0 == n) {
            Some(p) => p.1
            None =>
              raise Invalid("moonbit.unknown_field", context, n.to_canonical())
          }
        _ =>
          raise Invalid(
            "moonbit.type_mismatch", context, "Field requires a closed record",
          )
      }
    IfThenElse(_, _, a, _) => inferred(ctx, a, env, context)
    _ =>
      raise Invalid(
        "moonbit.ambiguous_type", context, "Expression requires a concrete inferred type",
      )
  }
}

///|
fn expression(
  ctx : Lowering,
  value : @ir.Value,
  expected : Lowered,
  env : Map[@ir.Name, Lowered],
  owner : @ir.FQName,
  context : String,
) -> String raise {
  if value_attrs(value).inferred_type is Some(tpe) {
    if lower_type(ctx, tpe, context) != expected {
      raise Invalid(
        "moonbit.type_mismatch", context, "Inferred and contextual types disagree",
      )
    }
  }
  fn emit(v : @ir.Value, t : Lowered, suffix : String) -> String raise {
    expression(ctx, v, t, env, owner, context + suffix)
  }
  match value {
    Literal(_, _) | Unit(_) =>
      match expected {
        Atom(s) => scalar_literal(value, s, ctx.imports, context)
        _ =>
          raise Invalid(
            "moonbit.type_mismatch", context, "Scalar body has a compound type",
          )
      }
    Variable(_, n) => {
      if env.get(n) != Some(expected) {
        raise Invalid(
          "moonbit.type_mismatch",
          context,
          "Unbound variable or conflicting type: " + n.to_canonical(),
        )
      }
      ctx.locals.unwrap().names[n]
    }
    Reference(_, n) =>
      match ctx.values.get(n) {
        Some(d) => {
          if !d.exposed && d.module_name != owner.module_name {
            raise Invalid(
              "moonbit.inaccessible_reference",
              context,
              n.to_canonical(),
            )
          }
          if curry_type(d.inputs.map(p => p.1), d.output) != expected {
            raise Invalid(
              "moonbit.type_mismatch",
              context,
              "Reference signature differs: " +
              lower_key(curry_type(d.inputs.map(p => p.1), d.output)) +
              " vs " +
              lower_key(expected),
            )
          }
          ctx.names.names[value_node(n)] + "()"
        }
        None if n.package_name.to_canonical() == "morphir/SDK" =>
          sdk_reference(ctx, n, expected, context)
        None =>
          raise Invalid(
            "moonbit.unresolved_reference",
            context,
            n.to_canonical(),
          )
      }
    Apply(_, Apply(_, Reference(_, n), left), right) if n.to_canonical() ==
      "morphir/SDK:basics#and" ||
      n.to_canonical() == "morphir/SDK:basics#or" => {
      if expected != Atom(Scalar::Boolean) {
        raise Invalid("moonbit.type_mismatch", context, "Boolean operation")
      }
      "(" +
      emit(left, Atom(Scalar::Boolean), "/left") +
      (if n.local_name.to_canonical() == "and" { " && " } else { " || " }) +
      emit(right, Atom(Scalar::Boolean), "/right") +
      ")"
    }
    Apply(_, f, argument) => {
      let ft = inferred(ctx, f, env, context + "/function")
      guard ft is Arrow(a, b) else {
        raise Invalid(
          "moonbit.type_mismatch", context, "Application requires function",
        )
      }
      if b != expected {
        raise Invalid(
          "moonbit.type_mismatch", context, "Application result differs",
        )
      }
      // Explicit temporaries freeze function-before-argument evaluation and curried steps.
      let function_name = ctx.locals.unwrap().fresh("function")
      let argument_name = ctx.locals.unwrap().fresh("argument")
      "{ let " +
      function_name +
      " = " +
      emit(f, ft, "/function") +
      "; let " +
      argument_name +
      " = " +
      emit(argument, a, "/argument") +
      "; " +
      function_name +
      "(" +
      argument_name +
      ") }"
    }
    Lambda(_, pattern, body) => {
      guard expected is Arrow(a, b) else {
        raise Invalid(
          "moonbit.type_mismatch", context, "Lambda requires function type",
        )
      }
      let nested = env.copy()
      let pat = pattern_source(ctx, pattern, a, nested, owner, context)
      let argument_name = ctx.locals.unwrap().fresh("argument")
      "fn(" +
      argument_name +
      " : " +
      type_source(ctx, a) +
      ") -> " +
      type_source(ctx, b) +
      " raise @sdk.SdkError { let " +
      pat +
      " = " +
      argument_name +
      "; " +
      expression(ctx, body, b, nested, owner, context + "/lambda") +
      " }"
    }
    IfThenElse(_, condition, yes, no) =>
      "if (" +
      emit(condition, Atom(Scalar::Boolean), "/condition") +
      ") { " +
      emit(yes, expected, "/then") +
      " } else { " +
      emit(no, expected, "/else") +
      " }"
    LetDefinition(_, n, definition, body) => {
      let (inputs, output, implementation) = local_definition(
        ctx, definition, context,
      )
      let nested = env.copy()
      nested[n] = curry_type(inputs.map(p => p.1), output)
      let args = env.copy()
      for p in inputs {
        args[p.0] = p.1
      }
      let source = curry_source(
        ctx,
        inputs.map(p => (ctx.locals.unwrap().names[p.0], p.1)),
        output,
        expression(
          ctx,
          implementation,
          output,
          args,
          owner,
          context + "/definition",
        ),
      )
      "{ let " +
      ctx.locals.unwrap().names[n] +
      " : " +
      type_source(ctx, nested[n]) +
      " = " +
      source +
      "; " +
      expression(ctx, body, expected, nested, owner, context + "/in") +
      " }"
    }
    Tuple(_, xs) => {
      guard expected is Product(ts) else {
        raise Invalid("moonbit.type_mismatch", context, "Tuple type")
      }
      if xs.length() != ts.length() {
        raise Invalid("moonbit.type_mismatch", context, "Tuple arity")
      }
      "(" +
      Array::makei(xs.length(), i => {
        emit(xs[i], ts[i], "/tuple/" + i.to_string())
      }).join(", ") +
      ")"
    }
    List(_, xs) => {
      guard expected is Sequence(t) else {
        raise Invalid("moonbit.type_mismatch", context, "List type")
      }
      ctx.imports["list"] = true
      "@list.from_array([" +
      xs.map(x => emit(x, t, "/element")).join(", ") +
      "])"
    }
    Record(_, fields) => {
      guard expected is Shape(n, fs) else {
        raise Invalid("moonbit.type_mismatch", context, "Record type")
      }
      if fields.length() != fs.length() {
        raise Invalid("moonbit.type_mismatch", context, "Record fields differ")
      }
      n +
      "::{ " +
      fs
      .map(p => {
        let v = match fields.get(p.0) {
          Some(v) => v
          None =>
            raise Invalid("moonbit.unknown_field", context, p.0.to_canonical())
        }
        field_name(ctx, n, p.0) +
        ": " +
        emit(v, p.1, "/field/" + p.0.to_canonical())
      })
      .join(", ") +
      " }"
    }
    Field(_, record, n) => {
      let rt = inferred(ctx, record, env, context + "/record")
      guard rt is Shape(shape, fs) else {
        raise Invalid("moonbit.type_mismatch", context, "Field requires record")
      }
      if !fs.any(p => p.0 == n && p.1 == expected) {
        raise Invalid("moonbit.unknown_field", context, n.to_canonical())
      }
      "(" + emit(record, rt, "/record") + ")." + field_name(ctx, shape, n)
    }
    FieldFunction(_, n) => {
      guard expected is Arrow(Shape(shape, fs) as a, b) else {
        raise Invalid(
          "moonbit.type_mismatch", context, "Field function requires closed record input",
        )
      }
      if !fs.any(p => p.0 == n && p.1 == b) {
        raise Invalid("moonbit.unknown_field", context, n.to_canonical())
      }
      let record_name = ctx.locals.unwrap().fresh("record")
      curry_source(
        ctx,
        [(record_name, a)],
        b,
        record_name + "." + field_name(ctx, shape, n),
      )
    }
    UpdateRecord(_, record, updates) => {
      guard expected is Shape(n, fs) else {
        raise Invalid(
          "moonbit.type_mismatch", context, "Update requires record",
        )
      }
      for key, _ in updates {
        if !fs.any(p => p.0 == key) {
          raise Invalid("moonbit.unknown_field", context, key.to_canonical())
        }
      }
      let record_name = ctx.locals.unwrap().fresh("record")
      "{ let " +
      record_name +
      " = " +
      emit(record, expected, "/record") +
      "; " +
      n +
      "::{ " +
      fs
      .map(p => {
        field_name(ctx, n, p.0) +
        ": " +
        (match updates.get(p.0) {
          Some(v) => emit(v, p.1, "/update/" + p.0.to_canonical())
          None => record_name + "." + field_name(ctx, n, p.0)
        })
      })
      .join(", ") +
      " } }"
    }
    Constructor(_, n) =>
      match ctx.constructors.get(n) {
        Some(c) => {
          if !c.exposed && c.module_name != owner.module_name {
            raise Invalid(
              "moonbit.inaccessible_reference",
              context,
              n.to_canonical(),
            )
          }
          if curry_type(c.inputs, c.output) != expected {
            raise Invalid(
              "moonbit.type_mismatch", context, "Constructor signature",
            )
          }
          let args = Array::makei(c.inputs.length(), i => {
            (ctx.locals.unwrap().fresh("argument"), c.inputs[i])
          })
          curry_source(
            ctx,
            args,
            c.output,
            type_source(ctx, c.output) +
            "::" +
            ctx.names.names["constructor:" + n.to_canonical()] +
            (if args.is_empty() {
              ""
            } else {
              "(" + args.map(p => p.0).join(", ") + ")"
            }),
          )
        }
        None => sdk_constructor(ctx, n, expected, context)
      }
    Destructure(_, pattern, value, body) => {
      let t = inferred(ctx, value, env, context)
      let nested = env.copy()
      let pat = pattern_source(ctx, pattern, t, nested, owner, context)
      "{ let " +
      pat +
      " = " +
      emit(value, t, "/destructure") +
      "; " +
      expression(ctx, body, expected, nested, owner, context + "/body") +
      " }"
    }
    PatternMatch(_, scrutinee, cases) => {
      let t = inferred(ctx, scrutinee, env, context)
      "match " +
      emit(scrutinee, t, "/scrutinee") +
      " { " +
      cases
      .map(p => {
        let nested = env.copy()
        let pat = pattern_source(ctx, p.0, t, nested, owner, context)
        pat +
        " => " +
        expression(ctx, p.1, expected, nested, owner, context + "/case")
      })
      .join("; ") +
      " }"
    }
    Hole(_, _, _) =>
      raise Invalid("moonbit.incomplete_body", context, "Hole expression")
    _ =>
      raise Invalid(
        "moonbit.unsupported_expression", context, "Recursive binding definitions require a separate lowering",
      )
  }
}

///|
fn local_definition(
  ctx : Lowering,
  d : @ir.ValueDefinition,
  context : String,
) -> (Array[(@ir.Name, Lowered)], Lowered, @ir.Value) raise {
  match d {
    ExpressionBody(inputs, output, body) =>
      (
        inputs.map(p => (p.0, lower_type(ctx, p.1, context))),
        lower_type(ctx, output, context),
        body,
      )
    _ =>
      raise Invalid(
        "moonbit.unresolved_implementation", context, "Local definition requires expression implementation",
      )
  }
}

///|
fn pattern_source(
  ctx : Lowering,
  pattern : @ir.Pattern,
  tpe : Lowered,
  env : Map[@ir.Name, Lowered],
  owner : @ir.FQName,
  context : String,
) -> String raise {
  match pattern {
    WildcardPattern(_) => "_"
    AsPattern(_, inner, n) => {
      env[n] = tpe
      "(" +
      pattern_source(ctx, inner, tpe, env, owner, context) +
      " as " +
      ctx.locals.unwrap().names[n] +
      ")"
    }
    UnitPattern(_) if tpe == Atom(Scalar::Unit) => "()"
    TuplePattern(_, ps) => {
      guard tpe is Product(ts) else {
        raise Invalid("moonbit.type_mismatch", context, "Tuple pattern")
      }
      if ps.length() != ts.length() {
        raise Invalid("moonbit.type_mismatch", context, "Pattern arity")
      }
      "(" +
      Array::makei(ps.length(), i => {
        pattern_source(ctx, ps[i], ts[i], env, owner, context)
      }).join(", ") +
      ")"
    }
    ConstructorPattern(_, n, ps) => {
      let c = match ctx.constructors.get(n) {
        Some(c) => c
        None =>
          raise Invalid(
            "moonbit.unsupported_pattern", context, "Only binding custom constructor patterns are implemented",
          )
      }
      if !c.exposed && c.module_name != owner.module_name {
        raise Invalid(
          "moonbit.inaccessible_reference",
          context,
          n.to_canonical(),
        )
      }
      if c.output != tpe || c.inputs.length() != ps.length() {
        raise Invalid(
          "moonbit.type_mismatch", context, "Constructor pattern signature",
        )
      }
      ctx.names.names["constructor:" + n.to_canonical()] +
      (if ps.is_empty() {
        ""
      } else {
        "(" +
        Array::makei(ps.length(), i => {
          pattern_source(ctx, ps[i], c.inputs[i], env, owner, context)
        }).join(", ") +
        ")"
      })
    }
    _ =>
      raise Invalid(
        "moonbit.unsupported_pattern", context, "Pattern requires a registered lowering",
      )
  }
}

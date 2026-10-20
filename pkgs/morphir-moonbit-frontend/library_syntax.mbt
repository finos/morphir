///|
/// Parser-owned nodes remain inside this adapter until declarations are admitted.
priv struct ParsedLibrary {
  nodes : Array[@ast.Impl]
  source_chars : Array[Char]
}

///|
fn library_parse(input : Input, cancelled : () -> Bool) -> ParsedLibrary raise {
  check_lexing(input)
  let (nodes, reports) = @parser.parse_string(input.source, name=input.unit_id)
  library_poll(cancelled)
  if !reports.is_empty() {
    reject("syntax", reports[0].msg, reports[0].loc)
  }
  { nodes: nodes.to_array(), source_chars: input.source.to_array(), }
}

///|
priv struct LibraryAdapter {
  source_chars : Array[Char]
  channel : SourceChannel
  signatures : Map[String, Array[LibraryTypeUse]]
  limits : LibraryLimits
  cancelled : () -> Bool
  mut expressions : Int32
  mut calls : Int32
  mut lets : Int32
}

///|
fn LibraryAdapter::visit(
  self : LibraryAdapter,
  loc : @location.Location,
  depth : Int32,
) -> Unit raise {
  library_poll(self.cancelled)
  if depth > self.limits.max_depth ||
    self.expressions >= self.limits.max_expressions {
    reject("expression_limit", "Expression traversal budget exceeded", loc)
  }
  self.expressions += 1
}

///|
fn LibraryAdapter::number(
  self : LibraryAdapter,
  raw : String,
  scalar : LibraryScalar,
  loc : @location.Location,
) -> LibraryExpr raise {
  let start = loc.start.cnum
  let end = loc.end.cnum
  if start < 0 || end < start || end > self.source_chars.length() {
    reject("source_coordinate", "Invalid numeric literal coordinate", loc)
  }
  let authored = String::from_array(self.source_chars[start:end].to_owned())
  Number(library_integer_literal(raw, scalar, loc), authored, scalar, span(loc))
}

///|
fn LibraryAdapter::floating(
  self : LibraryAdapter,
  raw : String,
  scalar : LibraryScalar,
  loc : @location.Location,
) -> LibraryExpr raise {
  let start = loc.start.cnum
  let end = loc.end.cnum
  if start < 0 || end < start || end > self.source_chars.length() {
    reject("source_coordinate", "Invalid floating literal coordinate", loc)
  }
  let authored = String::from_array(self.source_chars[start:end].to_owned())
  let spelling = if raw.has_suffix("F") || raw.has_suffix("f") {
    raw[:raw.length() - 1].to_owned()
  } else {
    raw
  }
  let parsed = @parse.parse_double(spelling.view()) catch {
    _ => {
      reject("invalid_literal", "Invalid floating literal", loc)
      0.0
    }
  }
  if parsed.is_nan() || parsed.is_inf() {
    reject(
      "invalid_literal", "Nonfinite floating literals are unsupported", loc,
    )
  }
  let value = if scalar == Floating32 {
    Float::from_double(parsed).to_double()
  } else {
    parsed
  }
  if value.is_inf() {
    reject("invalid_literal", "Floating literal exceeds source range", loc)
  }
  Floating(value, authored, scalar, span(loc))
}

///|
/// Unsuffixed integer literals follow the expected source width in the small
/// expression forms whose type is fixed by their surrounding annotation.
fn LibraryAdapter::expression_as(
  self : LibraryAdapter,
  expr : @ast.Expr,
  depth : Int32,
  scalar : LibraryScalar,
) -> LibraryExpr raise {
  if !scalar.is_integer() || scalar == SignedInt32 {
    return self.expression(expr, depth)
  }
  let loc = expr.loc()
  match expr {
    @ast.Constant(c=@ast.Int(raw), ..) => {
      self.visit(loc, depth)
      self.number(raw, scalar, loc)
    }
    @ast.Group(expr=inner, ..) => {
      self.visit(loc, depth)
      self.expression_as(inner, depth + 1, scalar)
    }
    @ast.Unary(op~, expr=inner, ..) if identifier(op) == "-" &&
      scalar.is_signed() => {
      self.visit(loc, depth)
      match inner {
        @ast.Constant(c=@ast.Int(raw), ..) => {
          self.visit(inner.loc(), depth + 1)
          self.number("-" + raw, scalar, loc)
        }
        _ =>
          NumericNegation(
            self.expression_as(inner, depth + 1, scalar),
            span(loc),
          )
      }
    }
    @ast.Infix(op~, lhs~, rhs~, ..) if ["+", "-", "*"].contains(identifier(op)) => {
      self.visit(loc, depth)
      Binary(
        identifier(op),
        self.expression_as(lhs, depth + 1, scalar),
        self.expression_as(rhs, depth + 1, scalar),
        span(loc),
      )
    }
    @ast.If(cond~, ifso~, ifnot=Some(other), ..) => {
      self.visit(loc, depth)
      Conditional(
        self.expression(cond, depth + 1),
        self.expression_as(ifso, depth + 1, scalar),
        self.expression_as(other, depth + 1, scalar),
        span(loc),
      )
    }
    _ => self.expression(expr, depth)
  }
}

///|
fn LibraryAdapter::expression(
  self : LibraryAdapter,
  expr : @ast.Expr,
  depth : Int32,
) -> LibraryExpr raise {
  let loc = expr.loc()
  let source = span(loc)
  self.visit(loc, depth)
  match expr {
    @ast.Constant(c=@ast.Bool(value), ..) => Boolean(value, source)
    @ast.Constant(c=@ast.Int(raw), ..) => self.number(raw, SignedInt32, loc)
    @ast.Constant(c=@ast.Int64(raw), ..) => self.number(raw, SignedInt64, loc)
    @ast.Constant(c=@ast.UInt(raw), ..) => self.number(raw, UnsignedInt32, loc)
    @ast.Constant(c=@ast.UInt64(raw), ..) =>
      self.number(raw, UnsignedInt64, loc)
    @ast.Constant(c=@ast.BigInt(raw), ..) =>
      self.number(raw, UnboundedInteger, loc)
    @ast.Constant(c=@ast.Float(raw), ..) => self.floating(raw, Floating32, loc)
    @ast.Constant(c=@ast.Double(raw), ..) => self.floating(raw, Floating64, loc)
    @ast.Constant(c=@ast.String(repr), ..) => {
      // The pinned lexer counts Unicode scalar positions, not UTF-8 bytes or UTF-16 units.
      let start = loc.start.cnum
      let end = loc.end.cnum
      if start < 0 || end < start || end > self.source_chars.length() {
        reject("source_coordinate", "Invalid literal coordinate", loc)
      }
      let authored = String::from_array(self.source_chars[start:end].to_owned())
      if authored != "\"" + repr + "\"" {
        reject(
          "source_coordinate", "Literal token does not match pinned lexer coordinates",
          loc,
        )
      }
      Text(library_cook_string(repr, loc), authored, source)
    }
    @ast.Ident(id~, ..) => Identifier(identifier(id), source)
    @ast.Group(expr~, ..) => self.expression(expr, depth + 1)
    @ast.Constraint(expr~, ty~, ..) => {
      let target = library_type(Some(ty), ty.loc(), self.channel)
      Constraint(
        self.expression_as(expr, depth + 1, target.scalar),
        target,
        source,
      )
    }
    @ast.Unary(op~, expr~, ..) => {
      let operator = identifier(op)
      if operator == "-" {
        return NumericNegation(self.expression(expr, depth + 1), source)
      }
      if operator != "!" {
        reject(
          "unsupported_operator", "Only Boolean negation is supported", loc,
        )
      }
      Negation(self.expression(expr, depth + 1), source)
    }
    @ast.Infix(op~, lhs~, rhs~, ..) => {
      let op = identifier(op)
      if !["&&", "||", "==", "!=", "+", "-", "*", "/", "<", "<=", ">", ">="].contains(
          op,
        ) {
        reject(
          "unsupported_operator", "Operator is outside the supported library subset",
          loc,
        )
      }
      Binary(
        op,
        self.expression(lhs, depth + 1),
        self.expression(rhs, depth + 1),
        source,
      )
    }
    @ast.If(cond~, ifso~, ifnot=Some(other), ..) =>
      Conditional(
        self.expression(cond, depth + 1),
        self.expression(ifso, depth + 1),
        self.expression(other, depth + 1),
        source,
      )
    @ast.Let(pattern~, expr~, body~, ..) => {
      self.lets += 1
      if self.lets > self.limits.max_lets {
        reject("let_limit", "Function binding budget exceeded", loc)
      }
      let mut annotation = None
      let binder = match pattern {
        @ast.Var(binder) => binder
        @ast.Constraint(pat=@ast.Var(binder), ty~, ..) => {
          annotation = Some(library_type(Some(ty), ty.loc(), self.channel))
          binder
        }
        _ => {
          reject(
            "unsupported_binding", "Only a single immutable named Boolean binding is supported",
            loc,
          )
          abort("unreachable")
        }
      }
      Binding(
        binder.name,
        span(binder.loc),
        match annotation {
          Some(ty) =>
            Constraint(
              self.expression_as(expr, depth + 1, ty.scalar),
              ty,
              source,
            )
          None => self.expression(expr, depth + 1)
        },
        self.expression(body, depth + 1),
        source,
      )
    }
    @ast.DotApply(self=receiver, method_name~, args~, return_self=false, ..) if args.is_empty() =>
      match (method_name.name, receiver) {
        ("length", value) =>
          StringLength(self.expression(value, depth + 1), source)
        (
          "to_owned",
          @ast.ArrayGetSlice(
            array~,
            start_index=Some(start),
            end_index=Some(end),
            ..
          ),
        ) =>
          StringSlice(
            self.expression(array, depth + 1),
            self.expression(start, depth + 1),
            self.expression(end, depth + 1),
            source,
          )
        _ => {
          reject(
            "unsupported_expression", "Only String.length() and String[start:end].to_owned() are supported",
            loc,
          )
          abort("unreachable")
        }
      }
    @ast.Apply(func~, args~, ..) => {
      guard func is @ast.Ident(id~, ..) else {
        reject(
          "unsupported_expression", "Only direct same-file or audited SDK calls are supported",
          loc,
        )
        abort("unreachable")
      }
      self.visit(func.loc(), depth + 1)
      self.calls += 1
      if self.calls > self.limits.max_calls {
        reject("call_limit", "Unit call-site budget exceeded", loc)
      }
      let (name, qualified) = match id.name {
        @ast.Ident(name~) => (name, None)
        @ast.Dot(pkg~, id~) => ("@" + pkg + "." + id, Some((pkg, id)))
      }
      let arguments = []
      let mut i = 0
      for arg in args {
        if !(arg.kind is @ast.Positional) {
          reject(
            "unsupported_arguments", "Only positional call arguments are supported",
            loc,
          )
        }
        arguments.push(
          match self.signatures.get(name) {
            Some(inputs) if i < inputs.length() =>
              self.expression_as(arg.value, depth + 1, inputs[i].scalar)
            _ => self.expression(arg.value, depth + 1)
          },
        )
        i += 1
      }
      match qualified {
        Some((package_alias, source_name)) =>
          QualifiedCall(package_alias, source_name, arguments, source)
        None => Call(name, arguments, source)
      }
    }
    _ => {
      reject(
        "unsupported_expression", "Expected a pure Boolean library expression", loc,
      )
      abort("unreachable")
    }
  }
}

///|
/// Complete signatures precede body adaptation, enabling forward references.
fn library_adapt(
  parsed : ParsedLibrary,
  limits : LibraryLimits,
  cancelled : () -> Bool,
  channel : SourceChannel,
) -> Array[LibraryFunction] raise {
  let nodes = parsed.nodes
  if nodes.is_empty() || nodes.length() > limits.max_functions {
    library_error(
      "declaration_count",
      "Expected one or more functions within the declaration budget",
      None,
    )
  }
  let signatures = []
  let names : Map[String, Bool] = Map([])
  for node in nodes {
    library_poll(cancelled)
    guard node
      is @ast.TopFuncDef(fun_decl=decl, decl_body=body, where_clause=None, ..) else {
      reject(
        "unsupported_declaration",
        "Only top-level functions are supported",
        node.loc(),
      )
      abort("unreachable")
    }
    if decl.type_name is Some(_) ||
      decl.is_async is Some(_) ||
      decl.nocancel_ is Some(_) ||
      !decl.quantifiers.is_empty() ||
      !decl.attrs.is_empty() {
      reject(
        "unsupported_function",
        "Methods, generics, attributes and effects are unsupported",
        decl.loc,
      )
    }
    let effect = match decl.error_type {
      @ast.NoErrorType => LibraryEffect::Pure
      @ast.ErrorType(
        ty=@ast.Name(
          constr_id={ id: @ast.Dot(pkg="sdk", id="SdkError"), .. },
          tys~,
          ..
        )
      ) if tys.is_empty() => SdkError
      @ast.ErrorType(
        ty=@ast.Name(
          constr_id={ id: @ast.Dot(pkg="decimal", id="DecimalError"), .. },
          tys~,
          ..
        )
      ) if tys.is_empty() => DecimalError
      _ => {
        reject(
          "unsupported_function",
          "Only the pinned raise @sdk.SdkError declaration is supported in the numeric SDK profile",
          decl.loc,
        )
        abort("unreachable")
      }
    }
    if channel == Stable && effect != Pure {
      library_error(
        "experimental_capability",
        "SDK error declarations require " + EXPERIMENTAL_PROFILE,
        Some(span(decl.loc)),
      )
    }
    let public = match decl.vis {
      @ast.Pub(attr=None, ..) => true
      @ast.Default => false
      _ => {
        reject(
          "unsupported_visibility",
          "Only default or plain pub function visibility is supported",
          decl.loc,
        )
        abort("unreachable")
      }
    }
    if names.contains(decl.name.name) {
      reject(
        "duplicate_function",
        "Duplicate function: " + decl.name.name,
        decl.loc,
      )
    }
    names[decl.name.name] = true
    let output_type = library_type(
      decl.return_type,
      decl.return_type.map(t => t.loc()).unwrap_or(decl.loc),
      channel,
    )
    guard decl.decl_params is Some(parameters) else {
      reject(
        "unsupported_parameters",
        "An explicit positional parameter list is required",
        decl.loc,
      )
      abort("unreachable")
    }
    if parameters.length() > limits.max_parameters {
      reject("parameter_limit", "Parameter budget exceeded", decl.params_loc)
    }
    let parameter_names : Map[String, Bool] = Map([])
    let inputs = []
    let input_types = []
    for parameter in parameters {
      guard parameter is @ast.Positional(binder~, ty~) else {
        reject(
          "unsupported_parameters",
          "Only named positional parameters are supported",
          parameter.loc(),
        )
        abort("unreachable")
      }
      input_types.push(
        library_type(ty, ty.map(t => t.loc()).unwrap_or(binder.loc), channel),
      )
      if parameter_names.contains(binder.name) {
        reject(
          "duplicate_parameter",
          "Duplicate parameter: " + binder.name,
          binder.loc,
        )
      }
      parameter_names[binder.name] = true
      inputs.push((binder.name, span(binder.loc)))
    }
    guard body is @ast.DeclBody(expr~) else {
      reject(
        "missing_body",
        "An ordinary expression body is required",
        decl.loc,
      )
      abort("unreachable")
    }
    signatures.push(
      (
        decl.name.name,
        public,
        inputs,
        input_types,
        output_type,
        expr,
        span(decl.name.loc),
        source_documentation(decl.doc),
        effect,
      ),
    )
  }
  let signature_types : Map[String, Array[LibraryTypeUse]] = Map([])
  for (name, _, _, input_types, _, _, _, _, _) in signatures {
    signature_types[name] = input_types
  }
  let adapter = LibraryAdapter::{
    source_chars: parsed.source_chars,
    channel,
    signatures: signature_types,
    limits,
    cancelled,
    expressions: 0,
    calls: 0,
    lets: 0,
  }
  let functions = []
  for
    (
      name,
      public,
      parameters,
      input_types,
      output_type,
      body,
      source,
      doc,
      effect,
    ) in signatures {
    adapter.lets = 0
    functions.push({
      name,
      doc,
      public,
      parameters,
      input_types,
      output_type,
      effect,
      body: adapter.expression_as(body, 0, output_type.scalar),
      body_source: span(body.loc()),
      source,
    })
  }
  functions
}

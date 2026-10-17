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
  mode : LibraryMode
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
    @ast.Constant(c=@ast.String(repr), ..) if self.mode.supports_strings() => {
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
    @ast.Constraint(expr~, ty~, ..) =>
      Constraint(
        self.expression(expr, depth + 1),
        library_type(Some(ty), ty.loc(), self.mode),
        source,
      )
    @ast.Unary(op~, expr~, ..) => {
      if identifier(op) != "!" {
        reject(
          "unsupported_operator", "Only Boolean negation is supported", loc,
        )
      }
      Negation(self.expression(expr, depth + 1), source)
    }
    @ast.Infix(op~, lhs~, rhs~, ..) => {
      let op = identifier(op)
      if !["&&", "||", "==", "!="].contains(op) &&
        !(self.mode.supports_strings() && op == "+") &&
        !(self.mode.supports_string_order() &&
        ["<", "<=", ">", ">="].contains(op)) {
        reject(
          "unsupported_operator", "Only Boolean operators are supported", loc,
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
          annotation = Some(library_type(Some(ty), ty.loc(), self.mode))
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
          Some(ty) => Constraint(self.expression(expr, depth + 1), ty, source)
          None => self.expression(expr, depth + 1)
        },
        self.expression(body, depth + 1),
        source,
      )
    }
    @ast.Apply(func~, args~, ..) => {
      guard func is @ast.Ident(id~, ..) else {
        reject(
          "unsupported_expression", "Only direct unqualified function calls are supported",
          loc,
        )
        abort("unreachable")
      }
      self.visit(func.loc(), depth + 1)
      self.calls += 1
      if self.calls > self.limits.max_calls {
        reject("call_limit", "Unit call-site budget exceeded", loc)
      }
      let name = identifier(id)
      let arguments = []
      for arg in args {
        if !(arg.kind is @ast.Positional) {
          reject(
            "unsupported_arguments", "Only positional call arguments are supported",
            loc,
          )
        }
        arguments.push(self.expression(arg.value, depth + 1))
      }
      Call(name, arguments, source)
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
  mode : LibraryMode,
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
      !decl.attrs.is_empty() ||
      !(decl.error_type is @ast.NoErrorType) {
      reject(
        "unsupported_function",
        "Methods, generics, attributes and effects are unsupported",
        decl.loc,
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
      mode,
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
        library_type(ty, ty.map(t => t.loc()).unwrap_or(binder.loc), mode),
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
      ),
    )
  }
  let adapter = LibraryAdapter::{
    source_chars: parsed.source_chars,
    mode,
    limits,
    cancelled,
    expressions: 0,
    calls: 0,
    lets: 0,
  }
  let functions = []
  for
    (name, public, parameters, input_types, output_type, body, source, doc) in signatures {
    adapter.lets = 0
    functions.push({
      name,
      doc,
      public,
      parameters,
      input_types,
      output_type,
      body: adapter.expression(body, 0),
      body_source: span(body.loc()),
      source,
    })
  }
  functions
}

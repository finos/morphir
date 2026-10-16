///|
/// Parser-owned nodes remain inside this adapter until declarations are admitted.
priv struct ParsedLibrary {
  nodes : Array[@ast.Impl]
}

///|
fn library_parse(input : Input, cancelled : () -> Bool) -> ParsedLibrary raise {
  check_lexing(input)
  let (nodes, reports) = @parser.parse_string(input.source, name=input.unit_id)
  library_poll(cancelled)
  if !reports.is_empty() {
    reject("syntax", reports[0].msg, reports[0].loc)
  }
  { nodes: nodes.to_array(), }
}

///|
priv struct LibraryAdapter {
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
    @ast.Ident(id~, ..) => Identifier(identifier(id), source)
    @ast.Group(expr~, ..) => self.expression(expr, depth + 1)
    @ast.Constraint(expr~, ty~, ..) => {
      require_bool(Some(ty), loc)
      self.expression(expr, depth + 1)
    }
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
      if !["&&", "||", "==", "!="].contains(op) {
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
      let binder = match pattern {
        @ast.Var(binder) => binder
        @ast.Constraint(pat=@ast.Var(binder), ty~, ..) => {
          require_bool(Some(ty), loc)
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
        self.expression(expr, depth + 1),
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
    require_bool(decl.return_type, decl.loc)
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
    for parameter in parameters {
      guard parameter is @ast.Positional(binder~, ty~) else {
        reject(
          "unsupported_parameters",
          "Only named positional parameters are supported",
          parameter.loc(),
        )
        abort("unreachable")
      }
      require_bool(ty, binder.loc)
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
    signatures.push((decl.name.name, public, inputs, expr, span(decl.name.loc)))
  }
  let adapter = LibraryAdapter::{
    limits,
    cancelled,
    expressions: 0,
    calls: 0,
    lets: 0,
  }
  let functions = []
  for (name, public, parameters, body, source) in signatures {
    adapter.lets = 0
    functions.push({
      name,
      public,
      parameters,
      body: adapter.expression(body, 0),
      body_source: span(body.loc()),
      source,
    })
  }
  functions
}

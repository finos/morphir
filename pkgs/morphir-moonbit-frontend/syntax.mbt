///|
fn span(loc : @location.Location) -> @ir.SourceLocation {
  {
    start_line: loc.start.lnum,
    start_column: loc.start.cnum - loc.start.bol,
    end_line: loc.end.lnum,
    end_column: loc.end.cnum - loc.end.bol,
  }
}

///|
/// Parser attachment owns comment/declaration association. Remove only the doc
/// marker's conventional space and empty separator edges, retaining Markdown.
fn source_documentation(doc : @ast.DocString) -> String? {
  let lines = doc.content
    .to_array()
    .map(line => line.strip_prefix(" ").unwrap_or(line[:]).to_owned())
  let mut first = 0
  let mut last = lines.length()
  while first < last && lines[first] == "" {
    first += 1
  }
  while last > first && lines[last - 1] == "" {
    last -= 1
  }
  if first == last {
    None
  } else {
    Some(lines[first:last].to_owned().join("\n"))
  }
}

///|
fn reject(
  code : String,
  detail : String,
  loc : @location.Location,
) -> Unit raise FrontendError {
  raise Invalid({
    code: "moonbit_frontend." + code,
    detail,
    source: Some(span(loc)),
  })
}

///|
fn boolean_type() -> @ir.Type raise {
  @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#bool"),
    [],
  )
}

///|
fn require_bool(
  ty : @ast.Type?,
  loc : @location.Location,
) -> Unit raise FrontendError {
  match ty {
    Some(@ast.Name(constr_id~, tys~, ..)) =>
      if !(constr_id.id is @ast.Ident(name="Bool")) || !tys.is_empty() {
        reject(
          "unsupported_type", "Only explicitly declared Bool is supported", loc,
        )
      }
    _ =>
      reject("unsupported_type", "An explicit Bool annotation is required", loc)
  }
}

///|
fn identifier(var_ : @ast.Var) -> String raise FrontendError {
  match var_.name {
    @ast.Ident(name~) => name
    _ => {
      reject(
        "qualified_reference",
        "Imports and qualified references are unsupported",
        var_.loc,
      )
      abort("unreachable")
    }
  }
}

///|
priv struct Lowerer {
  scope : Map[String, @ir.Name]
  boolean : @ir.Type
  limits : Limits
  cancelled : () -> Bool
  mut expressions : Int32
  names : BinderNames
  origins : Array[@ion.IonValue]
}

///|
fn Lowerer::attrs(
  self : Lowerer,
  loc : @location.Location,
) -> @ir.ValueAttributes {
  {
    source: Some(span(loc)),
    inferred_type: Some(self.boolean),
    extensions: Map([]),
  }
}

///|
fn Lowerer::literal(
  self : Lowerer,
  value : Bool,
  loc : @location.Location,
) -> @ir.Value {
  @ir.Value::Literal(self.attrs(loc), @ir.Literal::BoolLiteral(value))
}

///|
fn Lowerer::negate(
  self : Lowerer,
  value : @ir.Value,
  loc : @location.Location,
) -> @ir.Value {
  @ir.Value::IfThenElse(
    self.attrs(loc),
    value,
    self.literal(false, loc),
    self.literal(true, loc),
  )
}

///|
fn Lowerer::fresh(
  self : Lowerer,
  value : @ir.Value,
  role : String,
  loc : @location.Location,
) -> @ir.Name raise {
  let base = match value {
    Variable(_, name) => name.to_canonical()
    _ => "boolean"
  }
  let name = self.names.fresh(base, role)
  self.origins.push(
    ion_record([
      ("temporary", origin(role, loc)),
      ("identity", @ion.IonValue::string(name.to_canonical())),
      ("origin", @ion.IonValue::string(base)),
    ]),
  )
  name
}

///|
/// Equality binds both operands once, in source order, without duplicating trees.
fn Lowerer::equality(
  self : Lowerer,
  lhs : @ir.Value,
  rhs : @ir.Value,
  different : Bool,
  loc : @location.Location,
) -> @ir.Value raise {
  let left = self.fresh(lhs, "equality-left", loc)
  let right = self.fresh(rhs, "equality-right", loc)
  let l = @ir.Value::Variable(self.attrs(loc), left)
  let r = @ir.Value::Variable(self.attrs(loc), right)
  let comparison = if different {
    @ir.Value::IfThenElse(self.attrs(loc), l, self.negate(r, loc), r)
  } else {
    @ir.Value::IfThenElse(self.attrs(loc), l, r, self.negate(r, loc))
  }
  @ir.Value::LetDefinition(
    self.attrs(loc),
    left,
    @ir.ValueDefinition::ExpressionBody([], self.boolean, lhs),
    @ir.Value::LetDefinition(
      self.attrs(loc),
      right,
      @ir.ValueDefinition::ExpressionBody([], self.boolean, rhs),
      comparison,
    ),
  )
}

///|
fn Lowerer::lower(
  self : Lowerer,
  expr : @ast.Expr,
  depth : Int32,
) -> @ir.Value raise {
  let loc = expr.loc()
  if (self.cancelled)() {
    reject("cancelled", "Frontend cancelled", loc)
  }
  if depth > self.limits.max_depth ||
    self.expressions >= self.limits.max_expressions {
    reject("expression_limit", "Expression traversal budget exceeded", loc)
  }
  self.expressions += 1
  match expr {
    @ast.Constant(c=@ast.Bool(value), ..) => self.literal(value, loc)
    @ast.Ident(id~, ..) => {
      let text = identifier(id)
      match self.scope.get(text) {
        Some(name) => @ir.Value::Variable(self.attrs(loc), name)
        None => {
          reject(
            "unknown_reference",
            "Expected a Boolean parameter: " + text,
            loc,
          )
          abort("unreachable")
        }
      }
    }
    @ast.Group(expr~, ..) => self.lower(expr, depth + 1)
    @ast.Constraint(expr~, ty~, ..) => {
      require_bool(Some(ty), loc)
      self.lower(expr, depth + 1)
    }
    @ast.If(cond~, ifso~, ifnot=Some(other), ..) =>
      @ir.Value::IfThenElse(
        self.attrs(loc),
        self.lower(cond, depth + 1),
        self.lower(ifso, depth + 1),
        self.lower(other, depth + 1),
      )
    @ast.Unary(op~, expr~, ..) => {
      if identifier(op) != "!" {
        reject(
          "unsupported_operator", "Only Boolean negation is supported", loc,
        )
      }
      self.negate(self.lower(expr, depth + 1), loc)
    }
    @ast.Infix(op~, lhs~, rhs~, ..) => {
      let operator = identifier(op)
      if !["&&", "||", "==", "!="].contains(operator) {
        reject(
          "unsupported_operator", "Only Boolean operators are supported", loc,
        )
      }
      let left = self.lower(lhs, depth + 1)
      let right = self.lower(rhs, depth + 1)
      match operator {
        "&&" =>
          @ir.Value::IfThenElse(
            self.attrs(loc),
            left,
            right,
            self.literal(false, loc),
          )
        "||" =>
          @ir.Value::IfThenElse(
            self.attrs(loc),
            left,
            self.literal(true, loc),
            right,
          )
        _ => self.equality(left, right, operator == "!=", loc)
      }
    }
    _ => {
      reject(
        "unsupported_expression",
        "Expected a pure Boolean expression in " + LEGACY_BOOL_PROFILE,
        loc,
      )
      abort("unreachable")
    }
  }
}

///|
/// parse_string discards lexer errors. Reject them before admitting its recovered AST.
fn check_lexing(input : Input) -> Unit raise FrontendError {
  let lexed = @lexer.tokens_from_string(
    input.source[:],
    name=input.unit_id,
    comment=true,
  )
  if !lexed.errors.is_empty() {
    let (start, end, error) = lexed.errors[0]
    reject(
      "syntax",
      "Lexing error: " +
      Show::to_string(error) +
      ". Correct the token or use a supported identifier spelling.",
      { start, end, },
    )
  }
}

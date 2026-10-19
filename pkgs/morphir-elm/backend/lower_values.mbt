///|
fn Ctx::reserve_top_level(self : Ctx, elm_name : String) -> Unit {
  self.used[elm_name] = true
}

///|
/// Elm rejects a name that shadows any name in scope, so a name that is used or pending gets a numeric suffix.
fn Ctx::bind(self : Ctx, name : @ir.Name) -> String {
  let base = value_name(name)
  let mut elm_name = base
  while self.used.contains(elm_name) ||
        self.pending.get(elm_name).unwrap_or(0) > 0 {
    self.fresh += 1
    elm_name = base + "_" + self.fresh.to_string()
  }
  self.used[elm_name] = true
  self.scope[name.to_canonical()] = elm_name
  elm_name
}

///|
/// Marks the names of a let block as pending until the block binds them (`release`).
fn Ctx::reserve(self : Ctx, names : Array[String]) -> Unit {
  for name in names {
    self.pending[name] = self.pending.get(name).unwrap_or(0) + 1
  }
}

///|
/// A let block binds `name` now, so it is no longer pending.
fn Ctx::release(self : Ctx, name : String) -> Unit {
  match self.pending.get(name) {
    Some(count) if count > 1 => self.pending[name] = count - 1
    _ => self.pending.remove(name)
  }
}

///|
/// Lowers `body` in a new scope. The locals that it binds go out of scope at the end, so a sibling scope can take
/// the same names.
fn[T] Ctx::with_scope(
  self : Ctx,
  body : () -> T raise ElmGenerationError,
) -> T raise ElmGenerationError {
  let saved_scope = self.scope.copy()
  let saved_used = self.used.copy()
  let saved_pending = self.pending.copy()
  defer {
    self.scope = saved_scope
    self.used = saved_used
    self.pending = saved_pending
  }
  body()
}

///|
/// The Elm names that a let chain binds, as `lower_let` puts them in one Elm let block: the let definition names
/// and the names of each destructuring pattern.
fn chain_binders(v : @ir.Value) -> Array[String] {
  let out = []
  let mut rest = v
  while true {
    match rest {
      LetDefinition(_, name, _, next) => {
        out.push(value_name(name))
        rest = next
      }
      LetRecursion(_, definitions, next) => {
        for name, _ in definitions {
          out.push(value_name(name))
        }
        rest = next
      }
      Destructure(_, pattern, _, next) => {
        out.append(pattern_names(pattern))
        rest = next
      }
      _ => break
    }
  }
  out
}

///|
/// The Elm names that a pattern binds.
fn pattern_names(pattern : @ir.Pattern) -> Array[String] {
  let found : Map[String, Bool] = Map([])
  pattern_binders(pattern, found)
  found.keys().collect()
}

///|
fn Ctx::fresh_name(self : Ctx, base : String) -> String {
  self.fresh += 1
  let name = base + "_" + self.fresh.to_string()
  self.used[name] = true
  name
}

///|
fn placeholder(
  ctx : Ctx,
  reason : String,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  match ctx.options.placeholders {
    Refuse => refuse("placeholder", at, reason)
    DebugTodo =>
      Application(
        [
          node(@ast.Expression::FunctionOrValue(["Debug"][:], "todo")),
          node(@ast.Expression::Literal(reason)),
        ][:],
      )
  }
}

///|
fn hole_reason(reason : @ir.HoleReason) -> String {
  match reason {
    UnresolvedReference(name) =>
      "hole: unresolved reference " + name.to_canonical()
    DeletedDuringRefactor(detail) => "hole: deleted during refactor: " + detail
    TypeMismatch(expected, found) =>
      "hole: type mismatch, expected " + expected + ", found " + found
  }
}

///|
fn int_expression(
  text : String,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  let value = @parse.parse_int64(text) catch {
    _ => refuse("int_literal", at, text + " is outside the Int64 range")
  }
  if value < 0L {
    if value == -9223372036854775808L {
      refuse("int_literal", at, text + " has no positive Int64 form")
    }
    Negation(node(Integer(-value)))
  } else {
    Integer(value)
  }
}

///|
fn lower_literal(
  lit : @ir.Literal,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  match lit {
    BoolLiteral(b) => FunctionOrValue([][:], if b { "True" } else { "False" })
    CharLiteral(c) => CharLiteral(c)
    StringLiteral(s) => Literal(s)
    IntegerLiteral(text) => int_expression(text, at)
    FloatLiteral(d) =>
      if d < 0.0 || (d == 0.0 && 1.0 / d < 0.0) {
        Negation(node(Floatable(-d)))
      } else {
        Floatable(d)
      }
    DecimalLiteral(text) =>
      refuse(
        "decimal_literal",
        at,
        "no Elm construction is mapped for decimal " + text,
      )
    DocumentLiteral(_) =>
      refuse("document_literal", at, "Elm has no document literal")
  }
}

///|
fn reference(ctx : Ctx, name : @ir.FQName, kind : Kind) -> @ast.Expression {
  match ctx.resolve(name, kind) {
    Qualified(qualifier, name_text) => FunctionOrValue(qualifier[:], name_text)
    Op(op) => PrefixOperator(op)
  }
}

///|
fn operator_direction(op : String) -> @ast.InfixDirection {
  match op {
    "^" | "++" | "::" | "&&" | "||" | ">>" => Right
    "==" | "/=" | "<" | ">" | "<=" | ">=" => Non
    _ => Left
  }
}

///|
fn lower_apply(
  ctx : Ctx,
  v : @ir.Value,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  let args = []
  let mut head = v
  while head is Apply(_, f, a) {
    args.push(a)
    head = f
  }
  args.rev_in_place()
  let lowered = args.map(a => node(lower_value(ctx, a, at)))
  let op = match head {
    Reference(_, name) =>
      match ctx.resolve(name, Value) {
        Op(op) => Some(op)
        Qualified(_, _) => None
      }
    _ => None
  }
  match op {
    Some(op) if lowered.length() >= 2 => {
      let infix = node(
        @ast.Expression::OperatorApplication(
          op,
          operator_direction(op),
          lowered[0],
          lowered[1],
        ),
      )
      if lowered.length() == 2 {
        infix.value
      } else {
        Application(
          ([node(@ast.Expression::ParenthesizedExpression(infix))] +
          lowered[2:].to_owned())[:],
        )
      }
    }
    Some(op) =>
      Application(([node(@ast.Expression::PrefixOperator(op))] + lowered)[:])
    None => Application(([node(lower_value(ctx, head, at))] + lowered)[:])
  }
}

///|
/// `as` binds loosest in Elm, so an as-pattern inside a cons or a constructor argument needs parentheses.
fn lower_inner_pattern(
  ctx : Ctx,
  p : @ir.Pattern,
  at : String,
) -> @ast.Node[@ast.Pattern] raise ElmGenerationError {
  match lower_pattern(ctx, p, at) {
    AsPattern(_, _) as lowered => node(ParenthesizedPattern(node(lowered)))
    lowered => node(lowered)
  }
}

///|
fn lower_pattern(
  ctx : Ctx,
  p : @ir.Pattern,
  at : String,
) -> @ast.Pattern raise ElmGenerationError {
  match p {
    WildcardPattern(_) => AllPattern
    AsPattern(_, WildcardPattern(_), name) => VarPattern(ctx.bind(name))
    AsPattern(_, inner, name) => {
      let lowered = lower_pattern(ctx, inner, at)
      AsPattern(node(lowered), node(ctx.bind(name)))
    }
    TuplePattern(_, items) => {
      check_tuple_arity(items.length(), at)
      TuplePattern(items.map(i => node(lower_pattern(ctx, i, at)))[:])
    }
    ConstructorPattern(_, name, args) => {
      let (qualifier, name_text) = match ctx.resolve(name, Constructor) {
        Qualified(q, l) => (q, l)
        Op(op) =>
          refuse("invalid_mapping", at, "constructor maps to operator " + op)
      }
      NamedPattern(
        { module_name: qualifier[:], name: name_text, },
        args.map(a => lower_inner_pattern(ctx, a, at))[:],
      )
    }
    EmptyListPattern(_) => ListPattern([][:])
    HeadTailPattern(_, head, tail) =>
      UnConsPattern(
        lower_inner_pattern(ctx, head, at),
        lower_inner_pattern(ctx, tail, at),
      )
    LiteralPattern(_, literal) =>
      match literal {
        BoolLiteral(b) =>
          NamedPattern(
            { module_name: [][:], name: if b { "True" } else { "False" }, },
            [][:],
          )
        CharLiteral(c) => CharPattern(c)
        StringLiteral(s) => StringPattern(s)
        IntegerLiteral(text) =>
          match int_expression(text, at) {
            Integer(v) => IntPattern(v)
            _ =>
              refuse(
                "literal_pattern",
                at,
                "Elm has no negative literal pattern: " + text,
              )
          }
        FloatLiteral(_) | DecimalLiteral(_) =>
          refuse("literal_pattern", at, "Elm has no float or decimal pattern")
      }
    UnitPattern(_) => UnitPattern
  }
}

///|
fn setters(
  ctx : Ctx,
  fields : Map[@ir.Name, @ir.Value],
  at : String,
) -> ArrayView[@ast.Node[@ast.RecordSetter]] raise ElmGenerationError {
  check_field_collisions(fields.keys(), at)
  let result = []
  for name, value in fields {
    result.push(
      node(@ast.RecordSetter::{
        field: node(value_name(name)),
        expression: node(lower_value(ctx, value, at)),
      }),
    )
  }
  result[:]
}

///|
/// A let function. It has a signature when its type has no type variable (`closed_type`): Elm reads a variable in
/// a let signature as a new rigid variable, so a signature with one could make valid code fail.
fn let_function(
  ctx : Ctx,
  elm_name : String,
  definition : @ir.ValueDefinition,
  at : String,
) -> @ast.LetDeclaration raise ElmGenerationError {
  let (arguments, expression) = match definition {
    ExpressionBody(inputs, _, body) => let_function_body(ctx, inputs, body, at)
    _ =>
      (
        [][:],
        node(
          placeholder(ctx, "a let definition without an expression body", at),
        ),
      )
  }
  let signature = match definition {
    ExpressionBody(inputs, output, _) if closed_type(output) &&
      inputs.iter().all(input => closed_type(input.1)) =>
      Some(signature(ctx, elm_name, inputs, output, at))
    _ => None
  }
  LetFunction({
    documentation: None,
    signature,
    declaration: node({ name: node(elm_name), arguments, expression, }),
  })
}

///|
/// The arguments and the body of a let function: the inputs, then the patterns of the leading lambdas of the body.
/// Elm refuses a let value that refers to itself (`loop = \\n -> loop n`), but accepts a let function that does
/// (`loop n = loop n`).
fn let_function_body(
  ctx : Ctx,
  inputs : Array[(@ir.Name, @ir.Type)],
  body : @ir.Value,
  at : String,
) -> (ArrayView[@ast.Node[@ast.Pattern]], @ast.Node[@ast.Expression]) raise ElmGenerationError {
  ctx.with_scope(fn() raise ElmGenerationError {
    let arguments = inputs.map(input => {
      node(@ast.Pattern::VarPattern(ctx.bind(input.0)))
    })
    let mut rest = body
    while rest is Lambda(_, pattern, next) {
      arguments.push(node(lower_pattern(ctx, pattern, at)))
      rest = next
    }
    (arguments[:], node(lower_value(ctx, rest, at)))
  })
}

///|
/// Whether a type has no type variable, also no row variable.
fn closed_type(t : @ir.Type) -> Bool {
  match t {
    Variable(_, _) | ExtensibleRecord(_, _, _) => false
    Reference(_, _, args) => args.iter().all(closed_type)
    Tuple(_, items) => items.iter().all(closed_type)
    Union(_, items) => items.iter().all(closed_type)
    Record(_, fields) => fields.values().all(closed_type)
    Function(_, input, output) => closed_type(input) && closed_type(output)
    Unit(_) => true
  }
}

///|
fn function_body(
  ctx : Ctx,
  inputs : Array[(@ir.Name, @ir.Type)],
  body : @ir.Value,
  at : String,
) -> (ArrayView[@ast.Node[@ast.Pattern]], @ast.Node[@ast.Expression]) raise ElmGenerationError {
  ctx.with_scope(fn() raise ElmGenerationError {
    let arguments = inputs.map(input => {
      node(@ast.Pattern::VarPattern(ctx.bind(input.0)))
    })
    (arguments[:], node(lower_value(ctx, body, at)))
  })
}

///|
fn lower_let(
  ctx : Ctx,
  v : @ir.Value,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  ctx.with_scope(fn() raise ElmGenerationError {
    // Elm sees every name of the block in each definition, so the binders inside a definition avoid them.
    ctx.reserve(chain_binders(v))
    let declarations = []
    let mut rest = v
    while true {
      match rest {
        LetDefinition(_, name, definition, next) => {
          // The definition sees the outer binding of its own name, so bind after lowering.
          let body = let_function(ctx, "", definition, at)
          ctx.release(value_name(name))
          let elm_name = ctx.bind(name)
          declarations.push(node(rename_let(body, elm_name)))
          rest = next
        }
        LetRecursion(_, definitions, next) => {
          for name, _ in definitions {
            ctx.release(value_name(name))
          }
          let names = definitions
            .keys()
            .map(name => (name, ctx.bind(name)))
            .collect()
          for pair in names {
            declarations.push(
              node(
                let_function(ctx, pair.1, definitions.get(pair.0).unwrap(), at),
              ),
            )
          }
          rest = next
        }
        Destructure(_, pattern, value, next) => {
          let lowered_value = node(lower_value(ctx, value, at))
          pattern_names(pattern).each(name => ctx.release(name))
          let lowered_pattern = node(lower_pattern(ctx, pattern, at))
          declarations.push(
            node(
              @ast.LetDeclaration::LetDestructuring(
                lowered_pattern, lowered_value,
              ),
            ),
          )
          rest = next
        }
        _ => break
      }
    }
    LetExpression({
      declarations: declarations[:],
      expression: node(lower_value(ctx, rest, at)),
    })
  })
}

///|
fn rename_let(
  declaration : @ast.LetDeclaration,
  elm_name : String,
) -> @ast.LetDeclaration {
  match declaration {
    LetFunction(f) =>
      LetFunction({
        ..f,
        signature: f.signature.map(s => {
          node({ ..s.value, name: node(elm_name), })
        }),
        declaration: node({ ..f.declaration.value, name: node(elm_name), }),
      })
    other => other
  }
}

///|
fn lower_value(
  ctx : Ctx,
  v : @ir.Value,
  at : String,
) -> @ast.Expression raise ElmGenerationError {
  match v {
    Literal(_, literal) => lower_literal(literal, at)
    Constructor(_, name) => reference(ctx, name, Constructor)
    Tuple(_, items) => {
      check_tuple_arity(items.length(), at)
      TupledExpression(items.map(i => node(lower_value(ctx, i, at)))[:])
    }
    List(_, items) => ListExpr(items.map(i => node(lower_value(ctx, i, at)))[:])
    Record(_, fields) => RecordExpr(setters(ctx, fields, at))
    Variable(_, name) =>
      match ctx.scope.get(name.to_canonical()) {
        Some(elm_name) => FunctionOrValue([][:], elm_name)
        None => FunctionOrValue([][:], value_name(name))
      }
    Reference(_, name) => reference(ctx, name, Value)
    Field(_, target, name) =>
      RecordAccess(node(lower_value(ctx, target, at)), node(value_name(name)))
    FieldFunction(_, name) => RecordAccessFunction("." + value_name(name))
    Apply(_, _, _) => lower_apply(ctx, v, at)
    Lambda(_, _, _) =>
      ctx.with_scope(fn() raise ElmGenerationError {
        let args = []
        let mut body = v
        while body is Lambda(_, pattern, next) {
          args.push(node(lower_pattern(ctx, pattern, at)))
          body = next
        }
        LambdaExpression({
          args: args[:],
          expression: node(lower_value(ctx, body, at)),
        })
      })
    LetDefinition(_, _, _, _)
    | LetRecursion(_, _, _)
    | Destructure(_, _, _, _) => lower_let(ctx, v, at)
    IfThenElse(_, condition, then_branch, else_branch) =>
      IfBlock(
        node(lower_value(ctx, condition, at)),
        node(lower_value(ctx, then_branch, at)),
        node(lower_value(ctx, else_branch, at)),
      )
    PatternMatch(_, subject, cases) => {
      let lowered_subject = node(lower_value(ctx, subject, at))
      let lowered_cases = cases.map(c => {
        ctx.with_scope(fn() raise ElmGenerationError {
          let pattern = node(lower_pattern(ctx, c.0, at))
          @ast.Case::{ pattern, expression: node(lower_value(ctx, c.1, at)), }
        })
      })
      CaseExpression({ expression: lowered_subject, cases: lowered_cases[:], })
    }
    UpdateRecord(_, target, fields) =>
      // Elm updates only a bare name: a local, or a value that prints unqualified. Any other target is bound in
      // a `let` first.
      match lower_value(ctx, target, at) {
        FunctionOrValue(qualifier, name) if qualifier.is_empty() &&
          name.get_char(0) is Some(c) &&
          c >= 'a' &&
          c <= 'z' =>
          RecordUpdateExpression(node(name), setters(ctx, fields, at))
        record => {
          let fresh = ctx.fresh_name("record")
          let bound = node(
            @ast.LetDeclaration::LetFunction({
              documentation: None,
              signature: None,
              declaration: node({
                name: node(fresh),
                arguments: [][:],
                expression: node(record),
              }),
            }),
          )
          LetExpression({
            declarations: [bound][:],
            expression: node(
              RecordUpdateExpression(node(fresh), setters(ctx, fields, at)),
            ),
          })
        }
      }
    Unit(_) => UnitExpr
    Hole(_, reason, _) => placeholder(ctx, hole_reason(reason), at)
  }
}

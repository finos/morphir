///|
/// A let block, by morphir-elm's `mapLetExpression`. One frame holds every name
/// that the block binds before any right-hand side is lowered. The chain is in
/// dependency order (`let_groups`), not in source order. A let function or
/// value is a `LetDefinition` whose definition is never lifted; a destructuring
/// is a `Destructure`; a cycle is a `LetRecursion`, and a destructuring in a
/// cycle is not supported. The let nodes have the attributes of `range`, the
/// range of the let expression.
fn Lowering::let_block(
  self : Lowering,
  range : @ast.Range,
  block : @ast.LetBlock,
) -> @ir.Value raise LowerError {
  let declarations = block.declarations
  // As `declarationIndexForName` (`Dict.fromList`: a later name wins).
  let index_of : Map[String, Int] = Map([])
  for i, declaration in declarations {
    for name in names_bound_by_declaration(declaration.value) {
      index_of[name] = i
    }
  }
  let frame : Map[String, Bool] = Map([])
  for name, _ in index_of {
    frame[name] = true
  }
  let edges = declarations
    .iter()
    .map(declaration => {
      names_referred_by_declaration(declaration.value).filter_map(name => {
        index_of.get(name)
      })
    })
  self.locals.push(frame)
  // Lower the chain outermost first, then the `in` expression.
  let steps : Array[LetStep] = []
  for group in let_groups(edges.collect()) {
    match group {
      Single(i) => steps.push(self.let_step(declarations[i]))
      Recursive(ids) => {
        let definitions : Map[@ir.Name, @ir.ValueDefinition] = Map([])
        for i in ids {
          let declaration = declarations[i]
          guard declaration.value is LetFunction(f) else {
            raise LowerError(
              "elm.unsupported",
              "a recursive destructuring is not supported",
              Some(declaration.range),
            )
          }
          let (name, definition) = self.let_function(declaration.range, f)
          definitions[name] = definition
        }
        steps.push(Recursion(definitions))
      }
    }
  }
  let mut value = self.expression(block.expression)
  ignore(self.locals.pop())
  let a = value_attributes(range)
  for k = steps.length() - 1; k >= 0; k = k - 1 {
    value = match steps[k] {
      Definition(name, definition) => LetDefinition(a, name, definition, value)
      Destructuring(pattern, bound) => Destructure(a, pattern, bound, value)
      Recursion(definitions) => LetRecursion(a, definitions, value)
    }
  }
  value
}

///|
/// One lowered link of a let chain, before its `in` value is known.
priv enum LetStep {
  Definition(@ir.Name, @ir.ValueDefinition)
  Destructuring(@ir.Pattern, @ir.Value)
  Recursion(Map[@ir.Name, @ir.ValueDefinition])
}

///|
fn Lowering::let_step(
  self : Lowering,
  declaration : @ast.Node[@ast.LetDeclaration],
) -> LetStep raise LowerError {
  match declaration.value {
    LetFunction(f) => {
      let (name, definition) = self.let_function(declaration.range, f)
      Definition(name, definition)
    }
    LetDestructuring(pattern, expression) => {
      // The names are in the let frame already.
      let p = self.pattern(pattern, Map([]))
      Destructuring(p, self.expression(expression))
    }
  }
}

///|
/// A let function or value, by morphir-elm's `mapFunction`: no inputs, the let
/// annotation or a fresh placeholder as the output, and the body as a lambda of
/// the arguments over the expression, at the range of the declaration.
fn Lowering::let_function(
  self : Lowering,
  range : @ast.Range,
  f : @ast.Function,
) -> (@ir.Name, @ir.ValueDefinition) raise LowerError {
  let output = match f.signature {
    Some(signature) =>
      lower_type(self.scope, signature.value.type_annotation, None)
    None => self.placeholder()
  }
  let implementation = f.declaration.value
  let lambda : @ast.Node[@ast.Expression] = {
    range,
    value: LambdaExpression({
      args: implementation.arguments,
      expression: implementation.expression,
    }),
  }
  let body = self.expression(lambda)
  (
    @mapping.elm_name(implementation.name.value),
    ExpressionBody([], output, body),
  )
}

///|
/// The names that a let declaration binds: a let function's name, or the names
/// of a destructuring pattern.
fn names_bound_by_declaration(
  declaration : @ast.LetDeclaration,
) -> Array[String] {
  match declaration {
    LetFunction(f) => [f.declaration.value.name.value]
    LetDestructuring(pattern, _) => {
      let names = []
      names_bound_by_pattern(pattern.value, names)
      names
    }
  }
}

///|
/// morphir-elm's `namesBoundByPattern`.
fn names_bound_by_pattern(
  pattern : @ast.Pattern,
  names : Array[String],
) -> Unit {
  match pattern {
    TuplePattern(items) | ListPattern(items) | NamedPattern(_, items) =>
      for item in items {
        names_bound_by_pattern(item.value, names)
      }
    RecordPattern(fields) =>
      for field in fields {
        names.push(field.value)
      }
    UnConsPattern(head, tail) => {
      names_bound_by_pattern(head.value, names)
      names_bound_by_pattern(tail.value, names)
    }
    VarPattern(name) => names.push(name)
    AsPattern(inner, name) => {
      names.push(name.value)
      names_bound_by_pattern(inner.value, names)
    }
    ParenthesizedPattern(inner) => names_bound_by_pattern(inner.value, names)
    _ => ()
  }
}

///|
/// The names that a let declaration mentions. For a let function only its
/// expression is scanned, as in morphir-elm.
fn names_referred_by_declaration(
  declaration : @ast.LetDeclaration,
) -> Array[String] {
  let names = []
  match declaration {
    LetFunction(f) =>
      names_referred_by_expression(f.declaration.value.expression.value, names)
    LetDestructuring(_, expression) =>
      names_referred_by_expression(expression.value, names)
  }
  names
}

///|
/// morphir-elm's `namesReferredByExpression`: the unqualified names that an
/// expression mentions, by syntax only (shadowing is not seen).
fn names_referred_by_expression(
  expression : @ast.Expression,
  names : Array[String],
) -> Unit {
  let walk = (node : @ast.Node[@ast.Expression]) => {
    names_referred_by_expression(node.value, names)
  }
  match expression {
    Application(items) | TupledExpression(items) | ListExpr(items) =>
      for item in items {
        walk(item)
      }
    OperatorApplication(_, _, left, right) => {
      walk(left)
      walk(right)
    }
    FunctionOrValue([], name) => names.push(name)
    IfBlock(c, t, e) => {
      walk(c)
      walk(t)
      walk(e)
    }
    Negation(inner) | ParenthesizedExpression(inner) | RecordAccess(inner, _) =>
      walk(inner)
    LetExpression(inner) => {
      walk(inner.expression)
      for declaration in inner.declarations {
        match declaration.value {
          LetFunction(f) => walk(f.declaration.value.expression)
          LetDestructuring(_, e) => walk(e)
        }
      }
    }
    CaseExpression(block) => {
      walk(block.expression)
      for c in block.cases {
        walk(c.expression)
      }
    }
    LambdaExpression(lambda) => walk(lambda.expression)
    RecordExpr(setters) =>
      for setter in setters {
        walk(setter.value.expression)
      }
    RecordUpdateExpression(target, setters) => {
      names.push(target.value)
      for setter in setters {
        walk(setter.value.expression)
      }
    }
    _ => ()
  }
}

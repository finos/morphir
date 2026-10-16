///|
/// The default value attributes with the source location of `range`.
pub fn value_attributes(range : @ast.Range) -> @ir.ValueAttributes {
  {
    ..@ir.ValueAttributes::default(),
    source: Some({
      start_line: range.start.row,
      start_column: range.start.column,
      end_line: range.end.row,
      end_column: range.end.column,
    }),
  }
}

///|
/// The state of lowering one top-level declaration: the scope, the local names
/// (one frame per binding form) and the next placeholder number, shared by the
/// declaration and its lets.
priv struct Lowering {
  scope : @resolve.Scope
  locals : Array[Map[String, Bool]]
  placeholders : Ref[Int32]
}

///|
fn Lowering::is_local(self : Lowering, name : String) -> Bool {
  self.locals.iter().any(frame => frame.contains(name))
}

///|
/// A fresh placeholder type: `t-0`, `t-1`, … in the order of the declaration.
fn Lowering::placeholder(self : Lowering) -> @ir.Type {
  let n = self.placeholders.val
  self.placeholders.val = n + 1
  placeholder(n)
}

///|
fn starts_upper(name : String) -> Bool {
  match name.get_char(0) {
    Some(c) => c >= 'A' && c <= 'Z'
    None => false
  }
}

///|
/// One top-level value as morphir-elm's `make` writes it: the Elm name and an
/// `ExpressionBody`. The declaration arguments and the arguments of the leading
/// lambdas of the body form one list. Inputs are lifted from the front while the
/// lowered pattern is a variable (also `(x)` or `_ as x`) and the rest of the
/// annotation is a function type (an unannotated value lifts every leading
/// variable, each with a fresh placeholder type). The other arguments stay in
/// the body as `Lambda` nodes.
pub fn lower_value_definition(
  scope : @resolve.Scope,
  f : @ast.Function,
) -> (String, @ir.ValueDefinition) raise LowerError {
  let lowering : Lowering = { scope, locals: [], placeholders: Ref(0), }
  let declaration = f.declaration.value
  let (arguments, body) = arguments_and_body(declaration)
  let frame : Map[String, Bool] = Map([])
  let patterns = lowering.patterns(arguments[:], frame)
  let inputs : Array[(@ir.Name, @ir.Type)] = []
  let mut rest = f.signature.map(s => s.value.type_annotation)
  let mut lifted = 0
  while lifted < arguments.length() {
    // As morphir-elm's `liftLambdaArguments`, test the lowered pattern: `x`,
    // `(x)` and `_ as x` are all `AsPattern(WildcardPattern, x)`.
    guard patterns[lifted] is AsPattern(_, WildcardPattern(_), name) else {
      break
    }
    match rest {
      None => inputs.push((name, lowering.placeholder()))
      Some(annotation) => {
        guard function_parts(annotation) is Some((argument, result)) else {
          break
        }
        inputs.push((name, lower_type(scope, argument, None)))
        rest = Some(result)
      }
    }
    lifted += 1
  }
  let output = match rest {
    None => lowering.placeholder()
    Some(annotation) => lower_type(scope, annotation, None)
  }
  lowering.locals.push(frame)
  let mut value = lowering.expression(body)
  ignore(lowering.locals.pop())
  for i = arguments.length() - 1; i >= lifted; i = i - 1 {
    value = Lambda(value_attributes(arguments[i].range), patterns[i], value)
  }
  (declaration.name.value, ExpressionBody(inputs, output, value))
}

///|
/// The declaration arguments, then the arguments of each leading lambda of the
/// body (also inside any number of parentheses), and the body after the last of
/// them.
fn arguments_and_body(
  declaration : @ast.FunctionImplementation,
) -> (Array[@ast.Node[@ast.Pattern]], @ast.Node[@ast.Expression]) {
  let arguments = declaration.arguments.to_owned()
  let mut body = declaration.expression
  while true {
    let mut inner = body
    while inner.value is ParenthesizedExpression(e) {
      inner = e
    }
    guard inner.value is LambdaExpression(lambda) else { break }
    arguments.append(lambda.args.to_owned())
    body = lambda.expression
  }
  (arguments, body)
}

///|
/// One expression, by morphir-elm's `mapExpression`.
fn Lowering::expression(
  self : Lowering,
  node : @ast.Node[@ast.Expression],
) -> @ir.Value raise LowerError {
  let a = value_attributes(node.range)
  match node.value {
    UnitExpr => Unit(a)
    FunctionOrValue(qualifier, name) => {
      let resolved = self.scope.resolve_value(qualifier.to_owned(), name, n => {
        self.is_local(n)
      }) catch {
        @resolve.ResolveError(code, message) =>
          raise LowerError(code, message, Some(node.range))
      }
      match resolved {
        Local(n) => Variable(a, @mapping.elm_name(n))
        BoolLiteral(b) => Literal(a, BoolLiteral(b))
        Global(fq) if starts_upper(name) => Constructor(a, fq)
        Global(fq) => Reference(a, fq)
      }
    }
    ParenthesizedExpression(inner) => self.expression(inner)
    LambdaExpression(lambda) => {
      let frame : Map[String, Bool] = Map([])
      let patterns = self.patterns(lambda.args, frame)
      self.locals.push(frame)
      let mut value = self.expression(lambda.expression)
      ignore(self.locals.pop())
      for i = patterns.length() - 1; i >= 0; i = i - 1 {
        value = Lambda(a, patterns[i], value)
      }
      value
    }
    Application(items) => {
      // `f a b` is `Apply(Apply(f, a), b)`.
      guard items is [first, .. rest] else {
        raise LowerError(
          "elm.unsupported",
          "an empty application is not supported",
          Some(node.range),
        )
      }
      let mut value = self.expression(first)
      for item in rest {
        value = Apply(a, value, self.expression(item))
      }
      value
    }
    // `|>` and `<|` are only syntax: both are an application of the function.
    OperatorApplication("|>", _, left, right) => {
      let f = self.expression(right)
      Apply(a, f, self.expression(left))
    }
    OperatorApplication("<|", _, left, right) => {
      let f = self.expression(left)
      Apply(a, f, self.expression(right))
    }
    OperatorApplication(symbol, _, left, right) => {
      let op = self.operator(symbol, node.range)
      let l = self.expression(left)
      Apply(a, Apply(a, op, l), self.expression(right))
    }
    IfBlock(c, t, e) => {
      let condition = self.expression(c)
      let then_branch = self.expression(t)
      IfThenElse(a, condition, then_branch, self.expression(e))
    }
    PrefixOperator(symbol) | Operator(symbol) =>
      self.operator(symbol, node.range)
    Integer(n) | Hex(n) => Literal(a, IntegerLiteral(n.to_string()))
    Floatable(d) => Literal(a, FloatLiteral(d))
    // A negated number literal folds into the literal; `-(1)` and `-x` do not.
    Negation({ value: Integer(n), .. }) =>
      Literal(a, IntegerLiteral((-n).to_string()))
    Negation({ value: Floatable(d), .. }) => Literal(a, FloatLiteral(-d))
    Negation(inner) =>
      Apply(a, Reference(a, negate_name), self.expression(inner))
    Literal(s) => Literal(a, StringLiteral(s))
    CharLiteral(c) => Literal(a, CharLiteral(c))
    TupledExpression([item]) => self.expression(item)
    TupledExpression(items) => Tuple(a, self.expressions(items))
    ListExpr(items) => List(a, self.expressions(items))
    LetExpression(block) => self.let_block(node.range, block)
    CaseExpression(block) => {
      let subject = self.expression(block.expression)
      let cases : Array[(@ir.Pattern, @ir.Value)] = []
      for c in block.cases {
        // Each case binds its own names.
        let frame : Map[String, Bool] = Map([])
        let pattern = self.pattern(c.pattern, frame)
        self.locals.push(frame)
        let body = self.expression(c.expression)
        ignore(self.locals.pop())
        cases.push((pattern, body))
      }
      PatternMatch(a, subject, cases)
    }
    RecordExpr(setters) => Record(a, self.fields(setters))
    RecordAccess(target, field) =>
      Field(a, self.expression(target), @mapping.elm_name(field.value))
    RecordAccessFunction(name) => {
      let field = if name.has_prefix(".") {
        name.view(start_offset=1).to_owned()
      } else {
        name
      }
      FieldFunction(a, @mapping.elm_name(field))
    }
    RecordUpdateExpression(name, setters) => {
      let resolved = self.scope.resolve_value([], name.value, n => {
        self.is_local(n)
      }) catch {
        @resolve.ResolveError(code, message) =>
          raise LowerError(code, message, Some(name.range))
      }
      let target_attributes = value_attributes(name.range)
      let target : @ir.Value = match resolved {
        Local(n) => Variable(target_attributes, @mapping.elm_name(n))
        Global(fq) => Reference(target_attributes, fq)
        BoolLiteral(b) => Literal(target_attributes, BoolLiteral(b))
      }
      UpdateRecord(a, target, self.fields(setters))
    }
    GLSLExpression(_) =>
      raise LowerError(
        "elm.unsupported",
        "GLSL is not supported",
        Some(node.range),
      )
  }
}

///|
fn Lowering::expressions(
  self : Lowering,
  nodes : ArrayView[@ast.Node[@ast.Expression]],
) -> Array[@ir.Value] raise LowerError {
  let result = []
  for node in nodes {
    result.push(self.expression(node))
  }
  result
}

///|
/// The fields of a record or a record update. A later setter of the same field
/// wins, as in morphir-elm's `Dict.fromList`.
fn Lowering::fields(
  self : Lowering,
  setters : ArrayView[@ast.Node[@ast.RecordSetter]],
) -> Map[@ir.Name, @ir.Value] raise LowerError {
  let fields : Map[@ir.Name, @ir.Value] = Map([])
  for setter in setters {
    let value = self.expression(setter.value.expression)
    fields[@mapping.elm_name(setter.value.field.value)] = value
  }
  fields
}

///|
/// An operator as a function: the `Reference` of its Morphir SDK function. An
/// operator without one is `elm.unsupported_value` at `range`.
fn Lowering::operator(
  self : Lowering,
  symbol : String,
  range : @ast.Range,
) -> @ir.Value raise LowerError {
  let fq = self.scope.resolve_operator(symbol) catch {
    @resolve.ResolveError(code, message) =>
      raise LowerError(code, message, Some(range))
  }
  Reference(value_attributes(range), fq)
}

///|
/// `Basics.negate`, which morphir-elm applies to a negated expression that is
/// not a number literal.
let negate_name : @ir.FQName = @ir.FQName::parse("morphir/SDK:basics#negate") catch {
  _ => abort("morphir/SDK:basics#negate")
}

///|
/// The frontend produces structural IR. It does not claim Hindley-Milner inference.
pub fn unknown_type() -> @ir.Type {
  @ir.Type::Variable(
    @ir.TypeAttributes::default(),
    @ir.Name::from_words(["scheme", "value"]),
  )
}

///|
fn attrs() -> @ir.ValueAttributes {
  @ir.ValueAttributes::default()
}

///|
fn type_ref(name : String) -> @ir.Type raise {
  @ir.Type::Reference(@ir.TypeAttributes::default(), @ir.FQName::parse(name), [])
}

///|
pub fn result_type(value : @ir.Value) -> @ir.Type raise {
  match value {
    Literal(_, BoolLiteral(_)) => type_ref("morphir/SDK:basics#bool")
    Literal(_, IntegerLiteral(_)) => type_ref("morphir/SDK:basics#int")
    Literal(_, FloatLiteral(_)) => type_ref("morphir/SDK:basics#float")
    Literal(_, StringLiteral(_)) => type_ref("morphir/SDK:string#string")
    Literal(_, CharLiteral(_)) => type_ref("morphir/SDK:char#char")
    Unit(_) => @ir.Type::Unit(@ir.TypeAttributes::default())
    Lambda(_, _, body) =>
      @ir.Type::Function(
        @ir.TypeAttributes::default(),
        unknown_type(),
        result_type(body),
      )
    _ => unknown_type()
  }
}

///|
pub fn primitive(name : String) -> String? {
  match name {
    "+" => Some("morphir/SDK:basics#add")
    "-" => Some("morphir/SDK:basics#subtract")
    "*" => Some("morphir/SDK:basics#multiply")
    "/" => Some("morphir/SDK:basics#divide")
    "=" => Some("morphir/SDK:basics#equal")
    "<" => Some("morphir/SDK:basics#less-than")
    ">" => Some("morphir/SDK:basics#greater-than")
    "<=" => Some("morphir/SDK:basics#less-than-or-equal")
    ">=" => Some("morphir/SDK:basics#greater-than-or-equal")
    "not" => Some("morphir/SDK:basics#not")
    "length" => Some("morphir/SDK:list#length")
    "string-append" => Some("morphir/SDK:string#append")
    _ => None
  }
}

///|
priv struct Compiler {
  mut next : Int32
  mut depth : Int32
  reserved : Map[String, Bool]
}

///|
fn Compiler::fresh(self : Compiler) -> @ir.Name {
  for ;; {
    let text = "scheme-temporary-" + self.next.to_string()
    self.next += 1
    if !self.reserved.contains(text) {
      self.reserved[text] = true
      return @ir.Name::from_words([
        "scheme",
        "temporary",
        (self.next - 1).to_string(),
      ])
    }
  }
}

///|
fn reserve(datum : @scheme.Datum, names : Map[String, Bool]) -> Unit {
  match datum {
    Symbol(name) => names[name] = true
    Sequence(items, tail) => {
      for item in items {
        reserve(item, names)
      }
      if tail is Some(tail) {
        reserve(tail, names)
      }
    }
    Vector(items) =>
      for item in items {
        reserve(item, names)
      }
    _ => ()
  }
}

///|
fn compiler(forms : Array[@scheme.Datum]) -> Compiler {
  let reserved = Map([])
  for form in forms {
    reserve(form, reserved)
  }
  { next: 0, depth: 0, reserved, }
}

///|
fn pattern(name : @ir.Name) -> @ir.Pattern {
  @ir.Pattern::AsPattern(attrs(), @ir.Pattern::WildcardPattern(attrs()), name)
}

///|
fn bind_name(name : String) -> @ir.Name raise {
  @ir.Name::parse(name)
}

///|
fn apply(function : @ir.Value, argument : @ir.Value) -> @ir.Value {
  @ir.Value::Apply(attrs(), function, argument)
}

///|
fn literal(datum : @scheme.Datum) -> @ir.Value raise {
  let value = match datum {
    Number(Integer(n)) =>
      return @ir.Value::Literal(
        int_fact(),
        @ir.Literal::IntegerLiteral(n.to_string()),
      )
    Number(Real(n)) => @ir.Literal::FloatLiteral(n)
    Number(Rational(_, _)) =>
      raise @scheme.Unsupported(
        "Exact rational literals have no direct Morphir literal",
      )
    Boolean(b) => @ir.Literal::BoolLiteral(b)
    Text(s) => @ir.Literal::StringLiteral(s)
    Character(c) => @ir.Literal::CharLiteral(c)
    Sequence(items, None) => return @ir.Value::List(attrs(), items.map(literal))
    _ =>
      raise @scheme.Unsupported(
        "Quoted symbols, vectors and improper lists cannot be lowered to Morphir literals",
      )
  }
  @ir.Value::Literal(attrs(), value)
}

///|
fn Compiler::body(
  self : Compiler,
  forms : Array[@scheme.Datum],
  scope : Map[String, Bool],
) -> @ir.Value raise {
  if forms.is_empty() {
    return @ir.Value::Unit(attrs())
  }
  self.depth += 1
  defer {
    self.depth -= 1
  }
  if self.depth > 256 {
    raise @scheme.Limit("Frontend depth")
  }
  let first = self.lower(forms[0], scope)
  if forms.length() == 1 {
    return first
  }
  @ir.Value::LetDefinition(
    attrs(),
    self.fresh(),
    @ir.ValueDefinition::ExpressionBody([], result_type(first), first),
    self.body(forms[1:].to_owned(), scope),
  )
}

///|
fn Compiler::lower(
  self : Compiler,
  datum : @scheme.Datum,
  scope : Map[String, Bool],
) -> @ir.Value raise {
  self.depth += 1
  defer {
    self.depth -= 1
  }
  if self.depth > 256 {
    raise @scheme.Limit("Frontend depth")
  }
  let forms = match datum {
    Symbol(name) => {
      if !scope.contains(name) && primitive(name) is Some(reference) {
        return @ir.Value::Reference(attrs(), @ir.FQName::parse(reference))
      }
      if !scope.contains(name) && name.contains("#") {
        return @ir.Value::Reference(attrs(), @ir.FQName::parse(name))
      }
      return @ir.Value::Variable(attrs(), bind_name(name))
    }
    Sequence(items, None) => items
    Sequence(_, Some(_)) => raise @scheme.Unsupported("Improper application")
    _ => return literal(datum)
  }
  if forms.is_empty() {
    raise @scheme.Invalid("Empty application")
  }
  let head = match forms[0] {
    Symbol(name) => name
    _ => ""
  }
  match head {
    "quote" => {
      if forms.length() != 2 {
        raise @scheme.Invalid("quote expects one argument")
      }
      literal(forms[1])
    }
    "if" => {
      if forms.length() != 4 {
        raise @scheme.Invalid("if expects three arguments")
      }
      let condition = self.lower(forms[1], scope)
      if condition is @ir.Value::Literal(_, value) &&
        !(value is @ir.Literal::BoolLiteral(_)) {
        raise @scheme.Unsupported("Morphir conditions must be boolean")
      }
      @ir.Value::IfThenElse(
        attrs(),
        condition,
        self.lower(forms[2], scope),
        self.lower(forms[3], scope),
      )
    }
    "begin" => self.body(forms[1:].to_owned(), scope)
    "lambda" => {
      if forms.length() < 3 {
        raise @scheme.Invalid("lambda needs a body")
      }
      let params = @scheme.proper(forms[1]).map(@scheme.symbol)
      if params.is_empty() {
        raise @scheme.Unsupported(
          "Morphir lambdas require a parameter; use unit explicitly",
        )
      }
      let inner_scope = Map::from_array(scope.iter().collect())
      let seen : Map[String, Bool] = Map([])
      for param in params {
        if seen.contains(param) {
          raise @scheme.Invalid("Duplicate parameter")
        }
        seen[param] = true
        inner_scope[param] = true
      }
      let mut body = self.body(forms[2:].to_owned(), inner_scope)
      for i = params.length() - 1; i >= 0; i = i - 1 {
        body = @ir.Value::Lambda(attrs(), pattern(bind_name(params[i])), body)
      }
      body
    }
    "let" | "let*" | "letrec" => {
      if forms.length() < 3 {
        raise @scheme.Invalid("let needs a body")
      }
      let bindings = @scheme.bindings(forms[1], sequential=head == "let*")
      let inner_scope = Map::from_array(scope.iter().collect())
      if head == "letrec" {
        for (name, _) in bindings {
          inner_scope[name] = true
        }
      }
      let lowered : Array[(@ir.Name, @ir.Value)] = []
      for (name, expression) in bindings {
        let value = self.lower(
          expression,
          if head == "let" {
            scope
          } else {
            inner_scope
          },
        )
        lowered.push((bind_name(name), value))
        if head == "let*" {
          inner_scope[name] = true
        }
      }
      for (name, _) in bindings {
        inner_scope[name] = true
      }
      let mut body = self.body(forms[2:].to_owned(), inner_scope)
      if head == "letrec" {
        let defs : Map[@ir.Name, @ir.ValueDefinition] = Map([])
        for (name, value) in lowered {
          defs[name] = definition(value)
        }
        return @ir.Value::LetRecursion(attrs(), defs, body)
      }
      // Simultaneous let evaluates initializers outside all new bindings.
      if head == "let" {
        let temps = lowered.map(_ => self.fresh())
        for i = lowered.length() - 1; i >= 0; i = i - 1 {
          body = @ir.Value::LetDefinition(
            attrs(),
            lowered[i].0,
            @ir.ValueDefinition::ExpressionBody(
              [],
              result_type(lowered[i].1),
              @ir.Value::Variable(attrs(), temps[i]),
            ),
            body,
          )
        }
        for i = lowered.length() - 1; i >= 0; i = i - 1 {
          body = @ir.Value::LetDefinition(
            attrs(),
            temps[i],
            definition(lowered[i].1),
            body,
          )
        }
      } else {
        for i = lowered.length() - 1; i >= 0; i = i - 1 {
          body = @ir.Value::LetDefinition(
            attrs(),
            lowered[i].0,
            definition(lowered[i].1),
            body,
          )
        }
      }
      body
    }
    "set!" | "define" | "define-syntax" | "quasiquote" =>
      raise @scheme.Unsupported(
        "Cannot lower " + head + " to functional Morphir IR",
      )
    _ => {
      if !scope.contains(head) && head == "list" {
        return @ir.Value::List(
          attrs(),
          forms[1:].to_owned().map(form => self.lower(form, scope)),
        )
      }
      if !scope.contains(head) &&
        ["+", "-", "*", "/", "string-append"].contains(head) {
        let args = forms[1:].to_owned().map(form => self.lower(form, scope))
        if args.is_empty() {
          return match head {
            "+" => @ir.Value::Literal(attrs(), @ir.Literal::IntegerLiteral("0"))
            "*" => @ir.Value::Literal(attrs(), @ir.Literal::IntegerLiteral("1"))
            "string-append" => literal(@scheme.Datum::Text(""))
            _ => raise @scheme.Invalid("Arithmetic needs an operand")
          }
        }
        let reference = self.lower(forms[0], scope)
        let mut result = args[0]
        if args.length() == 1 && (head == "-" || head == "/") {
          let initial = @ir.Value::Literal(
            attrs(),
            @ir.Literal::IntegerLiteral(if head == "-" { "0" } else { "1" }),
          )
          return apply(apply(reference, initial), result)
        }
        for i = 1; i < args.length(); i = i + 1 {
          result = apply(apply(reference, result), args[i])
        }
        return result
      }
      if forms.length() == 1 {
        raise @scheme.Unsupported(
          "Zero-argument calls require explicit unit in Morphir",
        )
      }
      if !scope.contains(head) &&
        ["=", "<", ">", "<=", ">="].contains(head) &&
        forms.length() != 3 {
        raise @scheme.Unsupported("Morphir comparison calls need two operands")
      }
      let mut result = self.lower(forms[0], scope)
      for form in forms[1:] {
        result = apply(result, self.lower(form, scope))
      }
      result
    }
  }
}

///|
fn definition(value : @ir.Value) -> @ir.ValueDefinition raise {
  let inputs : Array[(@ir.Name, @ir.Type)] = []
  let mut body = value
  let seen : Map[@ir.Name, Bool] = Map([])
  while body
        is @ir.Value::Lambda(
          _,
          @ir.Pattern::AsPattern(_, @ir.Pattern::WildcardPattern(_), name),
          rest
        ) {
    if seen.contains(name) {
      break
    }
    seen[name] = true
    inputs.push((name, unknown_type()))
    body = rest
  }
  @ir.ValueDefinition::ExpressionBody(inputs, result_type(body), body)
}

///|
/// Scheme integers are exact, so an integer literal is an `Int`. The frontend states it as a fact for inference.
fn int_fact() -> @ir.ValueAttributes raise {
  {
    source: None,
    inferred_type: Some(type_ref("morphir/SDK:basics#int")),
    extensions: Map([]),
  }
}

///|
/// `t` with each `scheme-value` placeholder replaced by the next `t-<n>` with the unknown marker.
fn number_type(t : @ir.Type, next : Ref[Int32]) -> @ir.Type {
  if t == unknown_type() {
    let name = @ir.Name::from_words(["t", next.val.to_string()])
    next.val += 1
    return @ir.Type::Variable(
      @ir.TypeAttributes::default().with_unknown(),
      name,
    )
  }
  match t {
    Function(a, x, y) => {
      let x = number_type(x, next)
      @ir.Type::Function(a, x, number_type(y, next))
    }
    _ => t
  }
}

///|
/// The definition with its placeholders numbered: its inputs, then its output, then its body.
fn number_definition(
  def : @ir.ValueDefinition,
  next : Ref[Int32],
) -> @ir.ValueDefinition {
  match def {
    ExpressionBody(inputs, output, body) => {
      let inputs = inputs.map(i => (i.0, number_type(i.1, next)))
      let output = number_type(output, next)
      @ir.ValueDefinition::ExpressionBody(
        inputs,
        output,
        number_value(body, next),
      )
    }
    _ => def
  }
}

///|
/// The value with the placeholders of every let signature in it numbered, in pre-order.
fn number_value(v : @ir.Value, next : Ref[Int32]) -> @ir.Value {
  match v {
    LetDefinition(a, n, def, rest) => {
      let def = number_definition(def, next)
      @ir.Value::LetDefinition(a, n, def, number_value(rest, next))
    }
    LetRecursion(a, defs, rest) => {
      let out : Map[@ir.Name, @ir.ValueDefinition] = Map([])
      for n, def in defs {
        out[n] = number_definition(def, next)
      }
      @ir.Value::LetRecursion(a, out, number_value(rest, next))
    }
    Apply(a, f, x) => {
      let f = number_value(f, next)
      @ir.Value::Apply(a, f, number_value(x, next))
    }
    Lambda(a, p, body) => @ir.Value::Lambda(a, p, number_value(body, next))
    IfThenElse(a, c, t, e) => {
      let c = number_value(c, next)
      let t = number_value(t, next)
      @ir.Value::IfThenElse(a, c, t, number_value(e, next))
    }
    List(a, items) => @ir.Value::List(a, items.map(i => number_value(i, next)))
    _ => v
  }
}

///|
/// The definition with each `scheme-value` placeholder replaced by `t-<n>` with the unknown marker, numbered
/// from 0 in traversal order. One name is one variable for inference, so each position gets its own name.
fn number_placeholders(def : @ir.ValueDefinition) -> @ir.ValueDefinition {
  number_definition(def, Ref(0))
}

///|
pub fn compile_expression(source : String) -> @ir.Value raise {
  let forms = @scheme.parse_program(source)
  if forms.length() != 1 {
    raise @scheme.Invalid("Expected one expression")
  }
  compiler(forms).lower(forms[0], Map([]))
}

///|
/// Lower top-level definitions and an optional final expression into a library.
pub fn compile_file(
  source : String,
  package_name~ : String = "user",
  module_name~ : String = "main",
) -> @ir.IRFile raise {
  let forms = @scheme.parse_program(source)
  let compiler = compiler(forms)
  let scope : Map[String, Bool] = Map([])
  let definitions : Array[(String, @scheme.Datum)] = []
  let expressions : Array[@scheme.Datum] = []
  for form in forms {
    if form is @scheme.Datum::Sequence(items, None) &&
      items.length() > 0 &&
      items[0] == @scheme.Datum::Symbol("define") {
      if !expressions.is_empty() {
        raise @scheme.Unsupported("Definitions must precede expressions")
      }
      if items.length() < 3 {
        raise @scheme.Invalid("Incomplete definition")
      }
      let (name, expression) = match items[1] {
        Symbol(name) => {
          if items.length() != 3 {
            raise @scheme.Invalid("define needs one expression")
          }
          (name, items[2])
        }
        Sequence(signature, None) if signature.length() > 1 =>
          (
            @scheme.symbol(signature[0]),
            @scheme.Datum::Sequence(
              [
                @scheme.Datum::Symbol("lambda"),
                @scheme.Datum::Sequence(signature[1:].to_owned(), None),
                ..items[2:],
              ],
              None,
            ),
          )
        _ =>
          raise @scheme.Unsupported(
            "Top-level function requires at least one parameter",
          )
      }
      if scope.contains(name) {
        raise @scheme.Invalid("Duplicate definition: " + name)
      }
      scope[name] = true
      definitions.push((name, expression))
    } else {
      expressions.push(form)
    }
  }
  if !expressions.is_empty() && scope.contains("main") {
    raise @scheme.Invalid("Final expression conflicts with definition main")
  }
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([])
  for (name, expression) in definitions {
    values[bind_name(name)] = {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: number_placeholders(
          definition(compiler.lower(expression, scope)),
        ),
      },
    }
  }
  if !expressions.is_empty() {
    values[bind_name("main")] = {
      access: @ir.Access::Public,
      value: {
        doc: None,
        value: number_placeholders(
          definition(compiler.body(expressions, scope)),
        ),
      },
    }
  }
  let module_def : @ir.ModuleDefinition = { types: Map([]), values, doc: None, }
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse(package_name), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse(module_name),
          { access: @ir.Access::Public, value: module_def, },
        ),
      ]),
    }),
  )
}

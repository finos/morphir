///|
/// Walks the declarations of one module with a stack of local names. It records the project modules that the
/// names resolve to and a problem for each name that does not resolve.
priv struct Walker {
  project : Project
  scope : Scope
  module_name : Array[String]
  path : String
  locals : Array[Map[String, Bool]] // a stack of frames
  found : Array[Array[String]] // first use first, no duplicates, not this module
  values : Array[@ir.FQName] // first use first, no duplicates, any package
  problems : Array[ResolveProblem]
}

///|
/// The names that one module uses.
pub(all) struct ModuleReferences {
  /// The project modules that the module references by any name, each once in first-use order.
  modules : Array[Array[String]]
  /// The names in value bodies that morphir-elm lowers to a value `Reference`, from any package, each once in
  /// first-use order: values that are not locals, operators other than `<|` and `|>`, and `Basics.negate` for a
  /// negation of anything but a number literal. Constructors, patterns and type annotations are not in it.
  values : Array[@ir.FQName]
  /// The names that do not resolve.
  problems : Array[ResolveProblem]
} derive(Eq, Debug)

///|
pub extend ModuleReferences with Eq::{equal, not_equal}

///|
pub extend ModuleReferences with @debug.Debug::{to_repr}

///|
/// The project modules that the declarations of a module reference by name, each once in first-use order, and
/// the names that do not resolve. It looks at type annotations, type definitions, value bodies and patterns.
pub fn Project::collect_references(
  self : Project,
  module_name : Array[String],
) -> (Array[Array[String]], Array[ResolveProblem]) {
  let found = self.module_references(module_name)
  (found.modules, found.problems)
}

///|
/// The names that the declarations of a module use: the project modules, the value references of the bodies and
/// the names that do not resolve. A module that is not in the project has none.
pub fn Project::module_references(
  self : Project,
  module_name : Array[String],
) -> ModuleReferences {
  guard self.modules.get(dotted(module_name)) is Some(m) else {
    return { modules: [], values: [], problems: [], }
  }
  let walker : Walker = {
    project: self,
    scope: self.scope(module_name),
    module_name,
    path: m.path,
    locals: [],
    found: [],
    values: [],
    problems: [],
  }
  for d in m.file.declarations {
    walker.declaration(d.value)
  }
  { modules: walker.found, values: walker.values, problems: walker.problems, }
}

///|
/// As `collect_references`, but a name that does not resolve raises `ResolveFailed` with all the problems.
pub fn Project::references(
  self : Project,
  module_name : Array[String],
) -> Array[Array[String]] raise ResolveFailed {
  let (found, problems) = self.collect_references(module_name)
  if !problems.is_empty() {
    raise ResolveFailed(problems)
  }
  found
}

///|
fn Walker::is_local(self : Walker, name : String) -> Bool {
  self.locals.iter().any(frame => frame.contains(name))
}

///|
fn Walker::record(self : Walker, fq : @ir.FQName) -> Unit {
  guard self.project.module_of(fq) is Some(m) else { return }
  if m != self.module_name && !self.found.contains(m) {
    self.found.push(m)
  }
}

///|
/// A name that morphir-elm lowers to a value `Reference` in a body.
fn Walker::record_value(self : Walker, fq : @ir.FQName) -> Unit {
  if !self.values.contains(fq) {
    self.values.push(fq)
  }
}

///|
/// An operator in a body. morphir-elm lowers `<|` and `|>` to an application. Other operators are SDK
/// references; one without a binding is not reported here.
fn Walker::operator(self : Walker, symbol : String) -> Unit {
  if symbol is ("<|" | "|>") {
    return
  }
  if @mapping.morphir_operator(symbol) is Some(fq) {
    self.record_value(fq)
  }
}

///|
fn Walker::fail(
  self : Walker,
  error : ResolveError,
  range : @ast.Range,
) -> Unit {
  let ResolveError(code, message) = error
  self.problems.push(problem(code, message, self.path, range))
}

///|
fn Walker::value(
  self : Walker,
  qualifier : Array[String],
  name : String,
  range : @ast.Range,
) -> Unit {
  try self.scope.resolve_value(qualifier, name, n => self.is_local(n)) catch {
    e => self.fail(e, range)
  } noraise {
    Global(fq) => {
      self.record(fq)
      // morphir-elm lowers a name that starts with an upper-case letter to a constructor, not a reference.
      if !starts_upper(name) {
        self.record_value(fq)
      }
    }
    Local(_) | BoolLiteral(_) => ()
  }
}

///|
fn Walker::declaration(self : Walker, d : @ast.Declaration) -> Unit {
  match d {
    FunctionDeclaration(f) => self.function(f)
    AliasDeclaration(a) => self.type_annotation(a.type_annotation)
    CustomTypeDeclaration(t) =>
      for c in t.constructors {
        for arg in c.value.arguments {
          self.type_annotation(arg)
        }
      }
    // Project::new reports these as unsupported.
    PortDeclaration(_) | InfixDeclaration(_) | Destructuring(_, _) => ()
  }
}

///|
/// A function: its annotation, then its body with the arguments as locals.
fn Walker::function(self : Walker, f : @ast.Function) -> Unit {
  if f.signature is Some(signature) {
    self.type_annotation(signature.value.type_annotation)
  }
  let implementation = f.declaration.value
  self.with_patterns(implementation.arguments, implementation.expression)
}

///|
/// The expression with the names of the patterns as locals.
fn Walker::with_patterns(
  self : Walker,
  patterns : ArrayView[@ast.Node[@ast.Pattern]],
  body : @ast.Node[@ast.Expression],
) -> Unit {
  let frame : Map[String, Bool] = Map([])
  for p in patterns {
    self.pattern(p, frame)
  }
  self.locals.push(frame)
  self.expression(body)
  ignore(self.locals.pop())
}

///|
fn Walker::type_annotation(
  self : Walker,
  t : @ast.Node[@ast.TypeAnnotation],
) -> Unit {
  match t.value {
    GenericType(_) | Unit => ()
    Typed(name, args) => {
      let (qualifier, local_name) = name.value
      try self.scope.resolve_type(qualifier.to_owned(), local_name) catch {
        e => self.fail(e, name.range)
      } noraise {
        fq => self.record(fq)
      }
      for a in args {
        self.type_annotation(a)
      }
    }
    Tupled(items) =>
      for item in items {
        self.type_annotation(item)
      }
    Record(fields) =>
      for f in fields {
        self.type_annotation(f.value.type_annotation)
      }
    GenericRecord(_, fields) =>
      for f in fields.value {
        self.type_annotation(f.value.type_annotation)
      }
    FunctionTypeAnnotation(a, b) => {
      self.type_annotation(a)
      self.type_annotation(b)
    }
  }
}

///|
/// Resolves the constructors of a pattern and adds the names that it binds to `frame`.
fn Walker::pattern(
  self : Walker,
  p : @ast.Node[@ast.Pattern],
  frame : Map[String, Bool],
) -> Unit {
  match p.value {
    AllPattern
    | UnitPattern
    | CharPattern(_)
    | StringPattern(_)
    | IntPattern(_)
    | HexPattern(_)
    | FloatPattern(_) => ()
    TuplePattern(items) | ListPattern(items) =>
      for item in items {
        self.pattern(item, frame)
      }
    RecordPattern(fields) =>
      for f in fields {
        frame[f.value] = true
      }
    UnConsPattern(head, tail) => {
      self.pattern(head, frame)
      self.pattern(tail, frame)
    }
    VarPattern(n) => frame[n] = true
    NamedPattern(name_ref, args) => {
      // A constructor is never a local.
      let qualifier = name_ref.module_name.to_owned()
      try self.scope.resolve_value(qualifier, name_ref.name, _ => false) catch {
        e => self.fail(e, p.range)
      } noraise {
        Global(fq) => self.record(fq)
        Local(_) | BoolLiteral(_) => ()
      }
      for a in args {
        self.pattern(a, frame)
      }
    }
    AsPattern(inner, n) => {
      self.pattern(inner, frame)
      frame[n.value] = true
    }
    ParenthesizedPattern(inner) => self.pattern(inner, frame)
  }
}

///|
fn Walker::expression(self : Walker, e : @ast.Node[@ast.Expression]) -> Unit {
  match e.value {
    PrefixOperator(symbol) | Operator(symbol) => self.operator(symbol)
    UnitExpr
    | Integer(_)
    | Hex(_)
    | Floatable(_)
    | Literal(_)
    | CharLiteral(_)
    | RecordAccessFunction(_)
    | GLSLExpression(_) => ()
    FunctionOrValue(qualifier, name) =>
      self.value(qualifier.to_owned(), name, e.range)
    Application(items) | TupledExpression(items) | ListExpr(items) =>
      for item in items {
        self.expression(item)
      }
    // Operators are SDK names; only the operands can reference the project.
    OperatorApplication(symbol, _, left, right) => {
      self.operator(symbol)
      self.expression(left)
      self.expression(right)
    }
    IfBlock(c, t, f) => {
      self.expression(c)
      self.expression(t)
      self.expression(f)
    }
    Negation(inner) => {
      // morphir-elm lowers the negation of a number literal to a literal and any other negation to
      // `Basics.negate`.
      if !(inner.value is (Integer(_) | Floatable(_))) &&
        self.project.core.value_of("Basics", "negate") is Some(negate) {
        self.record_value(negate)
      }
      self.expression(inner)
    }
    ParenthesizedExpression(inner) | RecordAccess(inner, _) =>
      self.expression(inner)
    LetExpression(block) => self.let_block(block)
    CaseExpression(block) => {
      self.expression(block.expression)
      for c in block.cases {
        self.with_patterns([c.pattern], c.expression)
      }
    }
    LambdaExpression(lambda) =>
      self.with_patterns(lambda.args, lambda.expression)
    RecordExpr(setters) =>
      for s in setters {
        self.expression(s.value.expression)
      }
    RecordUpdateExpression(record, setters) => {
      self.value([], record.value, record.range)
      for s in setters {
        self.expression(s.value.expression)
      }
    }
  }
}

///|
/// The let function names and the destructured names are locals in the whole block.
fn Walker::let_block(self : Walker, block : @ast.LetBlock) -> Unit {
  let frame : Map[String, Bool] = Map([])
  self.locals.push(frame)
  for d in block.declarations {
    match d.value {
      LetFunction(f) => frame[f.declaration.value.name.value] = true
      LetDestructuring(p, _) => self.pattern(p, frame)
    }
  }
  for d in block.declarations {
    match d.value {
      LetFunction(f) => self.function(f)
      LetDestructuring(_, e) => self.expression(e)
    }
  }
  self.expression(block.expression)
  ignore(self.locals.pop())
}

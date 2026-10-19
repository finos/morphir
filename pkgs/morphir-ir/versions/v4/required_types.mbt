///|
/// Whether native Union occurs in this authored type. This does not expand references.
pub fn Type::has_union(self : Type) -> Bool {
  match self {
    Union(_, _) => true
    Reference(_, _, xs) | Tuple(_, xs) => xs.any(Type::has_union)
    Record(_, fs) | ExtensibleRecord(_, _, fs) =>
      fs.values().any(Type::has_union)
    Function(_, a, b) => a.has_union() || b.has_union()
    Variable(_, _) | Unit(_) => false
  }
}

///|
/// Named type dependencies, including references under every alternative.
pub fn Type::references(self : Type) -> Array[FQName] {
  let out = []
  fn visit(t : Type) -> Unit {
    match t {
      Reference(_, n, xs) => {
        out.push(n)
        xs.each(visit)
      }
      Tuple(_, xs) | Union(_, xs) => xs.each(visit)
      Record(_, fs) | ExtensibleRecord(_, _, fs) => fs.values().each(visit)
      Function(_, a, b) => {
        visit(a)
        visit(b)
      }
      Variable(_, _) | Unit(_) => ()
    }
  }
  visit(self)
  out
}

///|
fn add_attrs(a : ValueAttributes, out : Array[Type]) -> Unit {
  if a.inferred_type is Some(t) {
    out.push(t)
  }
}

///|
fn pattern_types(p : Pattern, out : Array[Type]) -> Unit {
  match p {
    WildcardPattern(a)
    | EmptyListPattern(a)
    | LiteralPattern(a, _)
    | UnitPattern(a) => add_attrs(a, out)
    AsPattern(a, p, _) => {
      add_attrs(a, out)
      pattern_types(p, out)
    }
    TuplePattern(a, ps) | ConstructorPattern(a, _, ps) => {
      add_attrs(a, out)
      ps.each(p => pattern_types(p, out))
    }
    HeadTailPattern(a, h, t) => {
      add_attrs(a, out)
      pattern_types(h, out)
      pattern_types(t, out)
    }
  }
}

///|
fn incompleteness_types(why : Incompleteness, out : Array[Type]) -> Unit {
  if why is Hole(_, Some(t)) {
    out.push(t)
  }
}

///|
fn definition_types(d : ValueDefinition, out : Array[Type]) -> Unit {
  match d {
    ExpressionBody(xs, t, v) => {
      xs.each(x => out.push(x.1))
      out.push(t)
      value_types(v, out)
    }
    NativeBody(xs, t, _) => {
      xs.each(x => out.push(x.1))
      out.push(t)
    }
    ExternalBody(xs, t, _, v) => {
      xs.each(x => out.push(x.1))
      out.push(t)
      if v is Some(v) {
        value_types(v, out)
      }
    }
    IncompleteBody(xs, t, why, v) => {
      xs.each(x => out.push(x.1))
      if t is Some(t) {
        out.push(t)
      }
      incompleteness_types(why, out)
      if v is Some(v) {
        value_types(v, out)
      }
    }
  }
}

///|
fn value_types(v : Value, out : Array[Type]) -> Unit {
  let visit = v => value_types(v, out)
  match v {
    Literal(a, _)
    | Constructor(a, _)
    | Variable(a, _)
    | Reference(a, _)
    | FieldFunction(a, _)
    | Unit(a) => add_attrs(a, out)
    Hole(a, _, t) => {
      add_attrs(a, out)
      if t is Some(t) {
        out.push(t)
      }
    }
    Tuple(a, xs) | List(a, xs) => {
      add_attrs(a, out)
      xs.each(visit)
    }
    Record(a, fs) => {
      add_attrs(a, out)
      fs.values().each(visit)
    }
    Field(a, v, _) => {
      add_attrs(a, out)
      visit(v)
    }
    Apply(a, f, x) => {
      add_attrs(a, out)
      visit(f)
      visit(x)
    }
    Lambda(a, p, v) => {
      add_attrs(a, out)
      pattern_types(p, out)
      visit(v)
    }
    LetDefinition(a, _, d, v) => {
      add_attrs(a, out)
      definition_types(d, out)
      visit(v)
    }
    LetRecursion(a, ds, v) => {
      add_attrs(a, out)
      ds.values().each(d => definition_types(d, out))
      visit(v)
    }
    Destructure(a, p, x, v) => {
      add_attrs(a, out)
      pattern_types(p, out)
      visit(x)
      visit(v)
    }
    IfThenElse(a, c, y, n) => {
      add_attrs(a, out)
      visit(c)
      visit(y)
      visit(n)
    }
    PatternMatch(a, s, cases) => {
      add_attrs(a, out)
      visit(s)
      for (p, v) in cases {
        pattern_types(p, out)
        visit(v)
      }
    }
    UpdateRecord(a, r, fs) => {
      add_attrs(a, out)
      visit(r)
      fs.values().each(visit)
    }
  }
}

///|
/// Types explicitly required by this expression, including nested definitions and pattern facts.
/// Data and arbitrary extension payloads are never interpreted as type syntax.
pub fn Value::required_types(self : Value) -> Array[Type] {
  let out = []
  value_types(self, out)
  out
}

///|
pub fn ValueDefinition::required_types(self : ValueDefinition) -> Array[Type] {
  let out = []
  definition_types(self, out)
  out
}

///|
pub fn TypeDefinition::required_types(self : TypeDefinition) -> Array[Type] {
  match self {
    TypeAliasDefinition(_, t) => [t]
    CustomTypeDefinition(_, cs) => {
      let out = []
      for _, xs in cs.value {
        xs.each(x => out.push(x.1))
      }
      out
    }
    IncompleteTypeDefinition(_, why, t) => {
      let out = []
      incompleteness_types(why, out)
      if t is Some(t) {
        out.push(t)
      }
      out
    }
  }
}

///|
fn annotation_types(annotations : Array[Annotation], out : Array[Type]) -> Unit {
  for annotation in annotations {
    if annotation is Structured(_, args) {
      for arg in args {
        match arg {
          Positional(v) | Named(_, v) => value_types(v, out)
        }
      }
    }
  }
}

///|
pub fn Annotation::required_types(self : Annotation) -> Array[Type] {
  let out = []
  annotation_types([self], out)
  out
}

///|
pub fn ValueSpecification::required_types(
  self : ValueSpecification,
) -> Array[Type] {
  let out = []
  annotation_types(self.annotations, out)
  self.inputs.each(x => out.push(x.1))
  out.push(self.output)
  out
}

///|
pub fn TypeSpecification::required_types(
  self : TypeSpecification,
) -> Array[Type] {
  let out = []
  annotation_types(self.annotations, out)
  match self.body {
    TypeAliasSpecification(_, t) => out.push(t)
    CustomTypeSpecification(_, cs) =>
      for _, xs in cs {
        xs.each(x => out.push(x.1))
      }
    DerivedTypeSpecification(_, d) => out.push(d.base_type)
    OpaqueTypeSpecification(_) => ()
  }
  out
}

///|
pub fn PackageDefinition::required_types(
  self : PackageDefinition,
) -> Array[Type] {
  let out = []
  for _, m in self.modules {
    for _, d in m.value.types {
      out.append(d.value.value.required_types())
    }
    for _, d in m.value.values {
      out.append(d.value.value.required_types())
    }
  }
  out
}

///|
pub fn PackageSpecification::required_types(
  self : PackageSpecification,
) -> Array[Type] {
  let out = []
  for _, m in self.modules {
    annotation_types(m.annotations, out)
    for _, d in m.types {
      out.append(d.value.required_types())
    }
    for _, d in m.values {
      out.append(d.value.required_types())
    }
  }
  out
}

///|
/// Whole-file requirements include dependencies. A selected consumer must validate its closure before pruning.
pub fn IRFile::required_types(self : IRFile) -> Array[Type] {
  let out = []
  match self.distribution {
    Library(_, deps, d) => {
      out.append(d.required_types())
      for _, s in deps {
        out.append(s.required_types())
      }
    }
    Application(_, deps, d, _) => {
      out.append(d.required_types())
      for _, d in deps {
        out.append(d.required_types())
      }
    }
    Specs(_, deps, s) => {
      out.append(s.required_types())
      for _, s in deps {
        out.append(s.required_types())
      }
    }
  }
  out
}

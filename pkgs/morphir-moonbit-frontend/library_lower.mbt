///|
fn library_origin(name : String, source : @ir.SourceLocation) -> @ion.IonValue {
  ion_record([
    ("name", @ion.IonValue::string(name)),
    ("coordinate_profile", @ion.IonValue::string("moonbit-parser-position-v1")),
    ("start_line", @ion.IonValue::int(source.start_line)),
    ("start_column", @ion.IonValue::int(source.start_column)),
    ("end_line", @ion.IonValue::int(source.end_line)),
    ("end_column", @ion.IonValue::int(source.end_column)),
  ])
}

///|
fn library_attributes(
  source : @ir.SourceLocation,
  ty : @ir.Type,
) -> @ir.ValueAttributes {
  { source: Some(source), inferred_type: Some(ty), extensions: Map([]), }
}

///|
fn library_arrow(boolean : @ir.Type, arity : Int32) -> @ir.Type {
  let mut result = boolean
  for i = 0; i < arity; i = i + 1 {
    result = @ir.Type::Function(@ir.TypeAttributes::default(), boolean, result)
  }
  result
}

///|
priv struct LibraryLowerer {
  functions : Array[ResolvedFunction]
  entries : Array[@ir.FQName]
  boolean : @ir.Type
  cancelled : () -> Bool
  origins : Array[@ion.IonValue]
  mut names : BinderNames
}

///|
fn LibraryLowerer::literal(
  self : LibraryLowerer,
  value : Bool,
  source : @ir.SourceLocation,
) -> @ir.Value {
  @ir.Value::Literal(
    library_attributes(source, self.boolean),
    @ir.Literal::BoolLiteral(value),
  )
}

///|
fn LibraryLowerer::negate(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
) -> @ir.Value {
  @ir.Value::IfThenElse(
    library_attributes(source, self.boolean),
    value,
    self.literal(false, source),
    self.literal(true, source),
  )
}

///|
fn LibraryLowerer::fresh(
  self : LibraryLowerer,
  value : @ir.Value,
  role : String,
  source : @ir.SourceLocation,
) -> @ir.Name raise {
  let base = match value {
    Variable(_, name) => name.to_canonical()
    _ => "boolean"
  }
  let name = self.names.fresh(base, role)
  self.origins.push(
    ion_record([
      ("temporary", library_origin(role, source)),
      ("identity", @ion.IonValue::string(name.to_canonical())),
      ("origin", @ion.IonValue::string(base)),
    ]),
  )
  name
}

///|
fn LibraryLowerer::expression(
  self : LibraryLowerer,
  expr : ResolvedExpr,
) -> @ir.Value raise {
  library_poll(self.cancelled)
  match expr {
    Boolean(value, source) => self.literal(value, source)
    Variable(name, source) =>
      @ir.Value::Variable(library_attributes(source, self.boolean), name)
    Negation(value, source) => self.negate(self.expression(value), source)
    Conditional(cond, yes, no, source) =>
      @ir.Value::IfThenElse(
        library_attributes(source, self.boolean),
        self.expression(cond),
        self.expression(yes),
        self.expression(no),
      )
    Binding(name, text, binder_source, value, body, source) => {
      self.origins.push(
        ion_record([
          ("binding", library_origin(text, binder_source)),
          (
            "allocation_reason",
            @ion.IonValue::string(
              if name == self.names.source.names[text] {
                self.names.source.reason(text)
              } else {
                "lexical-shadow"
              },
            ),
          ),
          ("identity", @ion.IonValue::string(name.to_canonical())),
        ]),
      )
      @ir.Value::LetDefinition(
        library_attributes(source, self.boolean),
        name,
        @ir.ValueDefinition::ExpressionBody(
          [],
          self.boolean,
          self.expression(value),
        ),
        self.expression(body),
      )
    }
    Call(index, arguments, source) => {
      self.origins.push(
        ion_record([
          (
            "call",
            library_origin(self.functions[index].declaration.name, source),
          ),
        ]),
      )
      let mut value = @ir.Value::Reference(
        library_attributes(
          source,
          library_arrow(self.boolean, arguments.length()),
        ),
        self.entries[index],
      )
      for i = 0; i < arguments.length(); i = i + 1 {
        value = @ir.Value::Apply(
          library_attributes(
            source,
            library_arrow(self.boolean, arguments.length() - i - 1),
          ),
          value,
          self.expression(arguments[i]),
        )
      }
      value
    }
    Binary(op, lhs, rhs, source) => {
      let attrs = library_attributes(source, self.boolean)
      let left = self.expression(lhs)
      let right = self.expression(rhs)
      match op {
        "&&" =>
          @ir.Value::IfThenElse(attrs, left, right, self.literal(false, source))
        "||" =>
          @ir.Value::IfThenElse(attrs, left, self.literal(true, source), right)
        _ => {
          // Strict operand bindings preserve order and avoid duplicating call trees.
          let l = self.fresh(left, "equality-left", source)
          let r = self.fresh(right, "equality-right", source)
          let lv = @ir.Value::Variable(attrs, l)
          let rv = @ir.Value::Variable(attrs, r)
          let comparison = if op == "!=" {
            @ir.Value::IfThenElse(attrs, lv, self.negate(rv, source), rv)
          } else {
            @ir.Value::IfThenElse(attrs, lv, rv, self.negate(rv, source))
          }
          @ir.Value::LetDefinition(
            attrs,
            l,
            @ir.ValueDefinition::ExpressionBody([], self.boolean, left),
            @ir.Value::LetDefinition(
              attrs,
              r,
              @ir.ValueDefinition::ExpressionBody([], self.boolean, right),
              comparison,
            ),
          )
        }
      }
    }
  }
}

///|
fn library_lower(
  input : Input,
  package_name : @ir.Path,
  module_name : @ir.Path,
  checked : CheckedLibrary,
  cancelled : () -> Bool,
) -> LibraryOutput raise {
  let boolean = boolean_type()
  let allocated = allocate_source_names(
    checked.functions.map(f => (f.declaration.name, f.declaration.source)),
    package_name.to_canonical() + ":" + module_name.to_canonical(),
  )
  let warnings = allocated.warnings.copy()
  for function in checked.functions {
    warnings.append(function.names.source.warnings)
  }
  let entries = checked.functions.map(f => {
    @ir.FQName::parse(
      package_name.to_canonical() +
      ":" +
      module_name.to_canonical() +
      "#" +
      allocated.names[f.declaration.name].to_canonical(),
    )
  })
  let lowerer = LibraryLowerer::{
    functions: checked.functions,
    entries,
    boolean,
    cancelled,
    origins: [],
    names: BinderNames::new([], ""),
  }
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([])
  let metadata = []
  let public_entries = []
  for i = 0; i < checked.functions.length(); i = i + 1 {
    library_poll(cancelled)
    let function = checked.functions[i]
    let declaration = function.declaration
    lowerer.origins.clear()
    lowerer.names = function.names
    let body = lowerer.expression(function.body)
    values[allocated.names[declaration.name]] = {
      access: if declaration.public {
        @ir.Access::Public
      } else {
        @ir.Access::Private
      },
      value: {
        doc: None,
        value: @ir.ValueDefinition::ExpressionBody(
          function.parameters.map(name => (name, boolean)),
          boolean,
          body,
        ),
      },
    }
    if declaration.public {
      public_entries.push(entries[i])
    }
    let id = "value:" + entries[i].to_canonical()
    metadata.push({
      node_id: id,
      data: ion_record([
        ("declaration", library_origin(declaration.name, declaration.source)),
        (
          "naming",
          ion_record([
            ("policy", @ion.IonValue::string(NAMING_POLICY)),
            ("original", @ion.IonValue::string(declaration.name)),
            (
              "allocation_reason",
              @ion.IonValue::string(allocated.reason(declaration.name)),
            ),
            (
              "identity",
              @ion.IonValue::string(
                allocated.names[declaration.name].to_canonical(),
              ),
            ),
          ]),
        ),
        (
          "parameters",
          @ion.IonValue::list(
            declaration.parameters.mapi((i, p) => {
              allocated_origin(
                library_origin(p.0, p.1),
                function.parameters[i],
                function.names.source.reason(p.0),
              )
            }),
          ),
        ),
      ]),
    })
    metadata.push({
      node_id: id + "/body",
      data: ion_record([
        ("body", library_origin(declaration.name, declaration.body_source)),
        ("nodes", @ion.IonValue::list(lowerer.origins.copy())),
      ]),
    })
  }
  public_entries.sort_by(fn(a, b) { a.to_canonical().compare(b.to_canonical()) })
  let module_def : @ir.ModuleDefinition = { types: Map([]), doc: None, values, }
  let ir = @ir.IRFile::new(
    @ir.Distribution::Library(package_name, Map([]), {
      modules: Map::from_array([
        (module_name, { access: @ir.Access::Public, value: module_def, }),
      ]),
    }),
  )
  {
    unit_id: input.unit_id,
    ir,
    entries: public_entries,
    metadata,
    annotations: [@ion.SymbolToken::new("morphir_pipeline")],
    warnings,
    provenance: [
      ion_record([
        ("language", @ion.IonValue::string("moonbit")),
        ("profile", @ion.IonValue::string(LIBRARY_PROFILE)),
        ("parser_version", @ion.IonValue::string(PARSER_VERSION)),
        ("naming_policy", @ion.IonValue::string(NAMING_POLICY)),
        ("unit_id", @ion.IonValue::string(input.unit_id)),
      ]).with_annotation(@ion.SymbolToken::new("morphir_moonbit_frontend")),
    ] +
    warnings.map(w => w.to_ion()),
  }
}

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
fn library_arrow(
  signature : LibrarySignature,
  remaining : Int32,
  metadata : Bool,
) -> @ir.Type raise {
  let mut result = signature.output_type.to_ir(metadata)
  for i = signature.input_types.length() - 1
      i >= signature.input_types.length() - remaining
      i = i - 1 {
    result = @ir.Type::Function(
      @ir.TypeAttributes::default(),
      signature.input_types[i].to_ir(metadata),
      result,
    )
  }
  result
}

///|
priv struct LibraryLowerer {
  functions : Array[ResolvedFunction]
  bindings : PinnedSourceBindings
  entries : Array[@ir.FQName]
  boolean : @ir.Type
  types : Map[@ir.Name, LibraryTypeUse]
  metadata : Bool
  profile : String
  string_limit : Int32
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
    Floating(value, authored, scalar, source) => {
      let float64 = @ir.Type::Reference(
        @ir.TypeAttributes::default(),
        @ir.FQName::parse("morphir/SDK:basics#float"),
        [],
      )
      let attrs = library_attributes(source, float64)
      attrs.extensions["moonbit-source-number-v1"] = @ir.Data::Object(
        Map::from_array([
          ("kind", @ir.Data::Text("literal")),
          ("authored_token", @ir.Data::Text(authored)),
          ("resolved_type", @ir.Data::Text(scalar.source_name())),
          (
            "float64_bits",
            @ir.Data::Text(value.reinterpret_as_uint64().to_string()),
          ),
          (
            "float32_bits",
            @ir.Data::Text(
              if scalar == Floating32 {
                Float::from_double(value).reinterpret_as_uint().to_string()
              } else {
                ""
              },
            ),
          ),
          (
            "precision",
            @ir.Data::Number(if scalar == Floating32 { "24" } else { "53" }),
          ),
        ]),
      )
      let literal = @ir.Value::Literal(attrs, @ir.Literal::FloatLiteral(value))
      if scalar == Floating32 {
        let float32 = self.expr_type(expr)
        let converted = self.invoke(
          "morphir/moonbit-source:float32#from-float64",
          [(literal, float64)],
          float32,
          source,
          "float32-literal-round",
          metadata_key="moonbit-source-number-v1",
          runtime_extension="morphir-moonbit-source-float-v1",
        )
        match converted {
          @ir.Value::Apply(conversion_attrs, _, _) =>
            conversion_attrs.extensions["moonbit-source-number-v1"] = @ir.Data::Object(
              Map::from_array([
                ("kind", @ir.Data::Text("conversion")),
                ("policy", @ir.Data::Text("rounded-to-binary32")),
                ("input_representation", @ir.Data::Text("IEEE-binary64")),
                ("output_representation", @ir.Data::Text("IEEE-binary32")),
                (
                  "binding",
                  @ir.Data::Text("morphir/moonbit-source:float32#from-float64"),
                ),
                (
                  "float32_bits",
                  @ir.Data::Text(
                    Float::from_double(value).reinterpret_as_uint().to_string(),
                  ),
                ),
                (
                  "source_start_line",
                  @ir.Data::Number(source.start_line.to_string()),
                ),
                (
                  "source_start_column",
                  @ir.Data::Number(source.start_column.to_string()),
                ),
              ]),
            )
          _ => abort("floating literal conversion must apply a binding")
        }
        converted
      } else {
        literal
      }
    }
    Number(value, authored, scalar, source) => {
      let exact = library_integer_type()
      let attrs = library_attributes(source, exact)
      let facts = Map::from_array([
        ("kind", @ir.Data::Text("literal")),
        ("authored_token", @ir.Data::Text(authored)),
        ("canonical_value", @ir.Data::Text(value)),
        ("resolved_type", @ir.Data::Text(scalar.source_name())),
        (
          "signedness",
          @ir.Data::Text(if scalar.is_signed() { "signed" } else { "unsigned" }),
        ),
        ("compiler", @ir.Data::Text("0.10.18+6c83a7f62")),
      ])
      if scalar.bits() == 0 {
        facts["precision"] = @ir.Data::Text("arbitrary")
      } else {
        facts["width"] = @ir.Data::Number(scalar.bits().to_string())
      }
      attrs.extensions["moonbit-source-number-v1"] = @ir.Data::Object(facts)
      if scalar == UnboundedInteger {
        return @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral(value))
      }
      let result = LibraryTypeUse::{
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
      self.invoke(
        "morphir/moonbit-source:" + scalar.source_module() + "#normalize",
        [(@ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral(value)), exact)],
        result,
        source,
        "literal-normalization",
        metadata_key="moonbit-source-number-v1",
        runtime_extension=if scalar == SignedInt32 {
          "morphir-moonbit-source-int32-v1"
        } else {
          "morphir-moonbit-source-integer-v1"
        },
      )
    }
    Text(value, authored, source) => {
      let attrs = library_attributes(source, self.expr_type(expr))
      attrs.extensions["moonbit-source-string-v1"] = @ir.Data::Object(
        Map::from_array([
          ("kind", @ir.Data::Text("literal")),
          ("authored_token", @ir.Data::Text(authored)),
          ("cooked", @ir.Data::Text(value)),
          ("utf16_code_units", @ir.Data::Number(value.length().to_string())),
        ]),
      )
      self.require_string(
        @ir.Value::Literal(attrs, @ir.Literal::StringLiteral(value)),
        source,
        "literal-boundary",
      )
    }
    Constraint(value, ty, source) => {
      let value = self.expression(value)
      if !self.metadata {
        return value
      }
      self.origins.push(
        ion_record([("constraint", library_origin(ty.spelling, ty.source))]),
      )
      // Retain this authored type use even when the constrained expression is a
      // reference whose own type metadata belongs to a different declaration.
      let name = self.fresh(value, "constraint-value", source)
      let ty = ty.to_ir(true)
      let attrs = library_attributes(source, ty)
      @ir.Value::LetDefinition(
        attrs,
        name,
        @ir.ValueDefinition::ExpressionBody([], ty, value),
        @ir.Value::Variable(attrs, name),
      )
    }
    Variable(name, source) =>
      @ir.Value::Variable(
        library_attributes(source, self.types[name].to_ir(self.metadata)),
        name,
      )
    Negation(value, source) => self.negate(self.expression(value), source)
    NumericNegation(value, source) => {
      if self.expr_type(value) is @ir.Type::Reference(_, name, []) &&
        (
          name.to_canonical() == "morphir/moonbit-source:float32#float32" ||
          name.to_canonical() == "morphir/SDK:basics#float"
        ) {
        let ty = self.expr_type(value)
        return self.invoke(
          if name.to_canonical() == "morphir/SDK:basics#float" {
            "morphir/SDK:basics#negate"
          } else {
            "morphir/moonbit-source:float32#negate"
          },
          [(self.expression(value), ty)],
          ty,
          source,
          "float-negate",
          runtime_extension=if name.to_canonical() == "morphir/SDK:basics#float" {
            ""
          } else {
            "morphir-moonbit-source-float-v1"
          },
        )
      }
      let scalar = self.integer_scalar(value).unwrap()
      if scalar == SignedInt32 {
        self.int32_negate(self.expression(value), source)
      } else {
        self.integer_negate(self.expression(value), scalar, source)
      }
    }
    StringLength(value, source) =>
      self.string_length(self.expression(value), source)
    StringSlice(value, start, end, source) =>
      self.string_slice(
        self.expression(value),
        self.expression(start),
        self.expression(end),
        source,
      )
    Conditional(cond, yes, no, source) =>
      @ir.Value::IfThenElse(
        library_attributes(source, self.expr_type(yes)),
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
        library_attributes(source, self.expr_type(body)),
        name,
        @ir.ValueDefinition::ExpressionBody(
          [],
          self.types[name].to_ir(self.metadata),
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
      let arguments = arguments.map(arg => self.expression(arg))
      let temporaries = if self.metadata {
        arguments.map(arg => self.fresh(arg, "call-argument", source))
      } else {
        []
      }
      let mut value = @ir.Value::Reference(
        library_attributes(
          source,
          library_arrow(
            self.functions[index].declaration,
            arguments.length(),
            self.metadata,
          ),
        ),
        self.entries[index],
      )
      for i = 0; i < arguments.length(); i = i + 1 {
        value = @ir.Value::Apply(
          library_attributes(
            source,
            library_arrow(
              self.functions[index].declaration,
              arguments.length() - i - 1,
              self.metadata,
            ),
          ),
          value,
          if self.metadata {
            @ir.Value::Variable(
              library_attributes(
                source,
                self.functions[index].declaration.input_types[i].to_ir(
                  self.metadata,
                ),
              ),
              temporaries[i],
            )
          } else {
            arguments[i]
          },
        )
      }
      for i = temporaries.length() - 1; i >= 0; i = i - 1 {
        value = @ir.Value::LetDefinition(
          library_attributes(
            source,
            self.functions[index].declaration.output_type.to_ir(self.metadata),
          ),
          temporaries[i],
          @ir.ValueDefinition::ExpressionBody(
            [],
            self.functions[index].declaration.input_types[i].to_ir(
              self.metadata,
            ),
            arguments[i],
          ),
          value,
        )
      }
      value
    }
    SdkCall(index, arguments, source) => self.sdk_call(index, arguments, source)
    Binary(op, lhs, rhs, source) => {
      let attrs = library_attributes(source, self.boolean)
      let left = self.expression(lhs)
      let right = self.expression(rhs)
      if self.expr_type(lhs) is @ir.Type::Reference(_, name, _) &&
        name.to_canonical() == "morphir/SDK:string#string" {
        let text = self.expr_type(lhs)
        return if op == "+" {
          self.invoke(
            "morphir/moonbit-source:string#append-bounded",
            [
              (left, text),
              (right, text),
              (self.bound(source), library_integer_type()),
            ],
            text,
            source,
            "bounded-concatenation",
          )
        } else if ["<", "<=", ">", ">="].contains(op) {
          self.string_order(op, left, right, text, source)
        } else {
          self.invoke(
            if op == "==" {
              "morphir/SDK:basics#equal"
            } else {
              "morphir/SDK:basics#not-equal"
            },
            [(left, text), (right, text)],
            self.boolean,
            source,
            "string-equality",
          )
        }
      }
      if self.integer_scalar(lhs) is Some(scalar) {
        return if scalar == SignedInt32 {
          self.int32_binary(op, left, right, source)
        } else {
          self.integer_binary(op, left, right, scalar, source)
        }
      }
      if self.expr_type(lhs) is @ir.Type::Reference(_, float_name, []) &&
        (
          float_name.to_canonical() == "morphir/moonbit-source:float32#float32" ||
          float_name.to_canonical() == "morphir/SDK:basics#float"
        ) {
        let ty = self.expr_type(lhs)
        let operation = match op {
          "+" => "add"
          "-" => "subtract"
          "*" => "multiply"
          "/" => "divide"
          "==" => "equal"
          "!=" => "not-equal"
          "<" => "less-than"
          "<=" => "less-than-or-equal"
          ">" => "greater-than"
          _ => "greater-than-or-equal"
        }
        let float32 = float_name.to_canonical() ==
          "morphir/moonbit-source:float32#float32"
        let result = self.invoke(
          (if float32 {
            "morphir/moonbit-source:float32#"
          } else {
            "morphir/SDK:basics#"
          }) +
          operation,
          [(left, ty), (right, ty)],
          if ["+", "-", "*", "/"].contains(op) {
            ty
          } else {
            self.boolean
          },
          source,
          "float-" + operation,
          metadata_key="moonbit-source-number-v1",
          runtime_extension=if float32 {
            "morphir-moonbit-source-float-v1"
          } else {
            ""
          },
        )
        if float32 && ["+", "-", "*", "/"].contains(op) {
          match result {
            @ir.Value::Apply(operation_attrs, _, _) =>
              operation_attrs.extensions["moonbit-source-number-v1"] = @ir.Data::Object(
                Map::from_array([
                  ("kind", @ir.Data::Text("operation")),
                  ("policy", @ir.Data::Text("binary32-operation-rounding")),
                  (
                    "binding",
                    @ir.Data::Text(
                      "morphir/moonbit-source:float32#" + operation,
                    ),
                  ),
                  (
                    "source_start_line",
                    @ir.Data::Number(source.start_line.to_string()),
                  ),
                  (
                    "source_start_column",
                    @ir.Data::Number(source.start_column.to_string()),
                  ),
                ]),
              )
            _ => abort("floating operation must apply a binding")
          }
        }
        return result
      }
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
  string_limit : Int32,
  bindings : PinnedSourceBindings,
  channel : SourceChannel,
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
    bindings,
    entries,
    boolean,
    types: Map([]),
    metadata: true,
    profile: channel.profile(),
    string_limit,
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
    lowerer.types.clear()
    for name, ty in function.types {
      lowerer.types[name] = ty
    }
    let mut body = lowerer.expression(function.body)
    if declaration.public {
      if declaration.output_type.scalar == Floating32 {
        body = lowerer.round_float32(
          body,
          declaration.body_source,
          "public-result",
        )
      }
      for j = function.parameters.length() - 1; j >= 0; j = j - 1 {
        if declaration.input_types[j].scalar == Floating32 {
          let ty = declaration.input_types[j].to_ir(true)
          let name = function.parameters[j]
          let source = declaration.parameters[j].1
          let rounded = lowerer.round_float32(
            @ir.Value::Variable(library_attributes(source, ty), name),
            source,
            "public-argument",
          )
          body = @ir.Value::LetDefinition(
            library_attributes(
              declaration.body_source,
              declaration.output_type.to_ir(true),
            ),
            name,
            @ir.ValueDefinition::ExpressionBody([], ty, rounded),
            body,
          )
        }
      }
    }
    if declaration.public {
      if declaration.output_type.scalar.has_integer_boundary() {
        body = lowerer.require_integer_boundary(
          body,
          declaration.output_type.scalar,
          declaration.body_source,
          "public-result",
        )
      }
      for j = function.parameters.length() - 1; j >= 0; j = j - 1 {
        if declaration.input_types[j].scalar.has_integer_boundary() {
          let ty = declaration.input_types[j].to_ir(true)
          let name = function.parameters[j]
          let source = declaration.parameters[j].1
          let value = lowerer.require_integer_boundary(
            @ir.Value::Variable(library_attributes(source, ty), name),
            declaration.input_types[j].scalar,
            source,
            "public-argument",
          )
          body = @ir.Value::LetDefinition(
            library_attributes(
              declaration.body_source,
              declaration.output_type.to_ir(true),
            ),
            name,
            @ir.ValueDefinition::ExpressionBody([], ty, value),
            body,
          )
        }
      }
    }
    if declaration.public {
      if declaration.output_type.scalar == Text {
        body = lowerer.require_string(
          body,
          declaration.body_source,
          "public-result",
        )
      }
      for j = function.parameters.length() - 1; j >= 0; j = j - 1 {
        if declaration.input_types[j].scalar == Text {
          let ty = declaration.input_types[j].to_ir(true)
          let name = function.parameters[j]
          let source = declaration.parameters[j].1
          let value = lowerer.require_string(
            @ir.Value::Variable(library_attributes(source, ty), name),
            source,
            "public-argument",
          )
          body = @ir.Value::LetDefinition(
            library_attributes(
              declaration.body_source,
              declaration.output_type.to_ir(true),
            ),
            name,
            @ir.ValueDefinition::ExpressionBody([], ty, value),
            body,
          )
        }
      }
    }
    values[allocated.names[declaration.name]] = {
      access: if declaration.public {
        @ir.Access::Public
      } else {
        @ir.Access::Private
      },
      value: {
        doc: declaration.doc,
        value: @ir.ValueDefinition::ExpressionBody(
          function.parameters.mapi((j, name) => {
            (name, declaration.input_types[j].to_ir(true))
          }),
          declaration.output_type.to_ir(true),
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
          "source_error_contract",
          @ion.IonValue::string(declaration.effect.identifier()),
        ),
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
  let source_modules : Map[@ir.ModuleName, @ir.ModuleSpecification] = Map([])
  source_modules[@ir.Path::parse("string")] = @sdk_spec.source_string_specification().modules[@ir.Path::parse(
      "string",
    )]

  source_modules[@ir.Path::parse("int32")] = @sdk_spec.source_int32_module_specification()

  for (name, module_spec) in @sdk_spec.source_integer_specification().modules {
    source_modules[name] = module_spec
  }

  for (name, module_spec) in @sdk_spec.source_float_specification().modules {
    source_modules[name] = module_spec
  }

  let ir = @ir.IRFile::new(
    @ir.Distribution::Library(
      package_name,
      if !source_modules.is_empty() {
        Map::from_array([
          (
            @sdk_spec.source_string_package_name(),
            @ir.PackageSpecification::{ modules: source_modules, },
          ),
        ])
      } else {
        Map([])
      },
      {
        modules: Map::from_array([
          (module_name, { access: @ir.Access::Public, value: module_def, }),
        ]),
      },
    ),
  )
  {
    unit_id: input.unit_id,
    ir,
    entries: public_entries,
    metadata,
    annotations: [@ion.symbol("morphir_pipeline")],
    warnings,
    provenance: [
      ion_record([
        ("language", @ion.IonValue::string("moonbit")),
        ("profile", @ion.IonValue::string(channel.profile())),
        ("parser_version", @ion.IonValue::string(PARSER_VERSION)),
        ("naming_policy", @ion.IonValue::string(NAMING_POLICY)),
        ("unit_id", @ion.IonValue::string(input.unit_id)),
      ]).with_annotation(@ion.symbol("morphir_moonbit_frontend")),
    ] +
    warnings.map(w => w.to_ion()),
  }
}

///|
fn LibraryLowerer::expr_type(
  self : LibraryLowerer,
  expr : ResolvedExpr,
) -> @ir.Type raise {
  match expr {
    Boolean(_, _) | Negation(_, _) => self.boolean
    NumericNegation(value, _) => self.expr_type(value)
    StringLength(_, source) =>
      LibraryTypeUse::{
        scalar: SignedInt32,
        spelling: "Int32",
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
    StringSlice(_, _, _, source) =>
      LibraryTypeUse::{
        scalar: Text,
        spelling: "String",
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
    Number(_, _, scalar, source) =>
      LibraryTypeUse::{
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
    Floating(_, _, scalar, source) =>
      LibraryTypeUse::{
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
    Text(_, _, source) =>
      LibraryTypeUse::{ scalar: Text, spelling: "String", source, profile: "", }.to_ir(
        self.metadata,
      )
    Binary(op, lhs, _, _) =>
      if ["+", "-", "*", "/"].contains(op) {
        self.expr_type(lhs)
      } else {
        self.boolean
      }
    Variable(name, _) => self.types[name].to_ir(self.metadata)
    Constraint(_, ty, _) => ty.to_ir(self.metadata)
    Conditional(_, yes, _, _) => self.expr_type(yes)
    Binding(_, _, _, _, body, _) => self.expr_type(body)
    Call(index, _, _) =>
      self.functions[index].declaration.output_type.to_ir(self.metadata)
    SdkCall(index, _, source) => {
      let scalar = self.bindings.entries[index].output
      LibraryTypeUse::{
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: self.profile,
      }.to_ir(self.metadata)
    }
  }
}

///|
fn library_integer_type() -> @ir.Type raise {
  @ir.Type::Reference(
    @ir.TypeAttributes::default(),
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
}

///|
fn LibraryLowerer::round_float32(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
  role : String,
) -> @ir.Value raise {
  let float32 = LibraryTypeUse::{
    scalar: Floating32,
    spelling: "Float",
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  self.invoke(
    "morphir/moonbit-source:float32#round-boundary",
    [(value, float32)],
    float32,
    source,
    role,
    metadata_key="moonbit-source-number-v1",
    runtime_extension="morphir-moonbit-source-float-v1",
  )
}

///|
/// MoonBit compares String lengths before UTF-16 lexical ties. Bind source
/// operands in order, then lengths, so each source expression executes once.
fn LibraryLowerer::string_order(
  self : LibraryLowerer,
  op : String,
  left : @ir.Value,
  right : @ir.Value,
  text : @ir.Type,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let int = library_integer_type()
  let attrs = library_attributes(source, self.boolean)
  let l = self.fresh(left, "string-order-left", source)
  let r = self.fresh(right, "string-order-right", source)
  let lv = @ir.Value::Variable(library_attributes(source, text), l)
  let rv = @ir.Value::Variable(library_attributes(source, text), r)
  let ll = self.invoke(
    "morphir/SDK:string#length",
    [(lv, text)],
    int,
    source,
    "order-length",
  )
  let rl = self.invoke(
    "morphir/SDK:string#length",
    [(rv, text)],
    int,
    source,
    "order-length",
  )
  let ln = self.fresh(ll, "string-order-left-length", source)
  let rn = self.fresh(rl, "string-order-right-length", source)
  let lengths = [
    (@ir.Value::Variable(library_attributes(source, int), ln), int),
    (@ir.Value::Variable(library_attributes(source, int), rn), int),
  ]
  let operation_name = match op {
    "<" => "less-than"
    "<=" => "less-than-or-equal"
    ">" => "greater-than"
    _ => "greater-than-or-equal"
  }
  let operation = "morphir/SDK:basics#" + operation_name
  let mut result = @ir.Value::IfThenElse(
    attrs,
    self.invoke(
      "morphir/SDK:basics#equal",
      lengths,
      self.boolean,
      source,
      "order-equal-lengths",
    ),
    self.invoke(
      operation,
      [(lv, text), (rv, text)],
      self.boolean,
      source,
      "order-lexical-tie",
    ),
    self.invoke(operation, lengths, self.boolean, source, "order-length-first"),
  )
  let bindings = [
    (l, text, left),
    (r, text, right),
    (ln, int, ll),
    (rn, int, rl),
  ]
  for i = bindings.length() - 1; i >= 0; i = i - 1 {
    let (name, ty, value) = bindings[i]
    let owner = library_attributes(source, self.boolean)
    if i == 0 {
      owner.extensions["moonbit-source-string-order-v1"] = @ir.Data::Object(
        Map::from_array([
          ("operator", @ir.Data::Text(op)),
          ("ordering", @ir.Data::Text("utf16-shortlex")),
          ("lowering", @ir.Data::Text("length-first-lexical-tie")),
        ]),
      )
    }
    result = @ir.Value::LetDefinition(
      owner,
      name,
      @ir.ValueDefinition::ExpressionBody([], ty, value),
      result,
    )
  }
  result
}

///|
fn LibraryLowerer::bound(
  self : LibraryLowerer,
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  @ir.Value::Literal(
    library_attributes(source, library_integer_type()),
    @ir.Literal::IntegerLiteral(self.string_limit.to_string()),
  )
}

///|
fn LibraryLowerer::invoke(
  _self : LibraryLowerer,
  name : String,
  arguments : Array[(@ir.Value, @ir.Type)],
  result : @ir.Type,
  source : @ir.SourceLocation,
  role : String,
  metadata_key~ : String = "moonbit-source-string-v1",
  runtime_extension~ : String = "morphir-moonbit-source-string-v1",
) -> @ir.Value raise {
  let attrs = library_attributes(source, result)
  let facts = Map::from_array([
    ("kind", @ir.Data::Text("synthetic")),
    ("role", @ir.Data::Text(role)),
  ])
  if runtime_extension != "" {
    facts["runtime_extension"] = @ir.Data::Text(runtime_extension)
  }
  attrs.extensions[metadata_key] = @ir.Data::Object(facts)
  let mut signature = result
  for i = arguments.length() - 1; i >= 0; i = i - 1 {
    signature = @ir.Type::Function(
      @ir.TypeAttributes::default(),
      arguments[i].1,
      signature,
    )
  }
  let mut value = @ir.Value::Reference(
    { ..attrs, inferred_type: Some(signature), },
    @ir.FQName::parse(name),
  )
  for arg in arguments {
    guard signature is @ir.Type::Function(_, _, remaining) else {
      abort("invalid internal signature")
    }
    signature = remaining
    value = @ir.Value::Apply(
      { ..attrs, inferred_type: Some(signature), },
      value,
      arg.0,
    )
  }
  value
}

///|
/// Lower only an adapter-resolved source binding. The call owns its source
/// binding facts; the canonical SDK declaration remains the executable IR.
fn LibraryLowerer::sdk_call(
  self : LibraryLowerer,
  index : Int32,
  arguments : Array[ResolvedExpr],
  source : @ir.SourceLocation,
) -> @ir.Value raise {
  let binding = self.bindings.entries[index]
  let authored = binding.authored()
  self.origins.push(
    ion_record([
      ("sdk_call", library_origin(authored, source)),
      ("canonical", @ion.IonValue::string(binding.canonical)),
      ("source_package", @ion.IonValue::string(binding.source_package)),
      ("source_tree", @ion.IonValue::string(binding.source_tree)),
      ("source_signature", @ion.IonValue::string(binding.source_signature)),
    ]),
  )
  let facts = @ir.Data::Object(
    Map::from_array([
      ("kind", @ir.Data::Text("source-call")),
      ("source_alias", @ir.Data::Text(binding.source_alias)),
      ("source_name", @ir.Data::Text(binding.source_name)),
      ("source_package", @ir.Data::Text(binding.source_package)),
      ("source_version", @ir.Data::Text(binding.source_version)),
      ("source_tree", @ir.Data::Text(binding.source_tree)),
      ("source_signature", @ir.Data::Text(binding.source_signature)),
      ("canonical", @ir.Data::Text(binding.canonical)),
      ("conversion_policy", @ir.Data::Text(binding.contract.identifier())),
      ("sdk_classification", @ir.Data::Text(binding.origin.identifier())),
    ]),
  )
  if binding.form is StringMethod(_) && facts is @ir.Data::Object(fields) {
    fields["source_form"] = @ir.Data::Text("string-method")
    fields["receiver_type"] = @ir.Data::Text("String")
    fields["argument_coercion"] = @ir.Data::Text(
      "pinned-implicit-string-to-stringview",
    )
    fields["canonical_argument_order"] = @ir.Data::Text(
      binding.canonical_order().map(i => i.to_string()).join(","),
    )
  }
  if self.profile == EXPERIMENTAL_PROFILE && facts is @ir.Data::Object(fields) {
    fields["source_error_contract"] = @ir.Data::Text(
      binding.effect.identifier(),
    )
  }
  if binding.contract is DecimalExactConstruction &&
    facts is @ir.Data::Object(fields) {
    if arguments[0] is Text(text, lexeme, _) {
      fields["original_literal"] = @ir.Data::Text(text)
      fields["original_source_spelling"] = @ir.Data::Text(lexeme)
      let mantissa = text.split("e").to_array()[0]
      let fraction = mantissa.split(".").to_array()
      fields["literal_scale"] = @ir.Data::Number(
        (if fraction.length() == 2 { fraction[1].length() } else { 0 }).to_string(),
      )
    }
  }
  let output_type = LibraryTypeUse::{
    scalar: binding.output,
    spelling: binding.output.source_name(),
    source,
    profile: self.profile,
  }.to_ir(self.metadata)
  let input_types = binding.inputs.map(scalar => {
    LibraryTypeUse::{
      scalar,
      spelling: scalar.source_name(),
      source,
      profile: self.profile,
    }.to_ir(self.metadata)
  })
  let values = arguments.map(argument => self.expression(argument))
  // A reordered method call always binds temporaries, so the SDK argument order
  // cannot change source evaluation order.
  let temporaries = if self.metadata || binding.form is StringMethod(_) {
    values.map(value => self.fresh(value, "sdk-call-argument", source))
  } else {
    []
  }
  let order = binding.canonical_order()
  let mut signature = output_type
  for k = order.length() - 1; k >= 0; k = k - 1 {
    signature = @ir.Type::Function(
      @ir.TypeAttributes::default(),
      input_types[order[k]],
      signature,
    )
  }
  let reference_attrs = library_attributes(source, signature)
  reference_attrs.extensions["moonbit-source-binding-v1"] = facts
  let mut value = @ir.Value::Reference(
    reference_attrs,
    @ir.FQName::parse(binding.canonical),
  )
  // Temporaries keep source evaluation order; application uses SDK order.
  for i in order {
    guard signature is @ir.Type::Function(_, _, remaining) else {
      abort("invalid pinned SDK signature")
    }
    signature = remaining
    let apply_attrs = library_attributes(source, signature)
    apply_attrs.extensions["moonbit-source-binding-v1"] = facts
    value = @ir.Value::Apply(
      apply_attrs,
      value,
      if temporaries.is_empty() {
        values[i]
      } else {
        @ir.Value::Variable(
          library_attributes(source, input_types[i]),
          temporaries[i],
        )
      },
    )
  }
  for i = temporaries.length() - 1; i >= 0; i = i - 1 {
    value = @ir.Value::LetDefinition(
      library_attributes(source, output_type),
      temporaries[i],
      @ir.ValueDefinition::ExpressionBody([], input_types[i], values[i]),
      value,
    )
  }
  value
}

///|
fn LibraryLowerer::require_string(
  self : LibraryLowerer,
  value : @ir.Value,
  source : @ir.SourceLocation,
  role : String,
) -> @ir.Value raise {
  let text = LibraryTypeUse::{
    scalar: Text,
    spelling: "String",
    source,
    profile: "",
  }.to_ir(self.metadata)
  self.invoke(
    "morphir/moonbit-source:string#require-valid",
    [(value, text), (self.bound(source), library_integer_type())],
    text,
    source,
    role,
  )
}

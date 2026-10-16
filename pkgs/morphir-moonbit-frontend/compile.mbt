///|
fn ion_record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::new(
    @ion.Struct(fields.map(pair => @ion.Field::new(pair.0, pair.1))),
  )
}

///|
fn origin(name : String, loc : @location.Location) -> @ion.IonValue {
  ion_record([
    ("name", @ion.IonValue::string(name)),
    ("coordinate_profile", @ion.IonValue::string("moonbit-parser-position-v1")),
    ("start_line", @ion.IonValue::int(loc.start.lnum)),
    ("start_column", @ion.IonValue::int(loc.start.cnum - loc.start.bol)),
    ("end_line", @ion.IonValue::int(loc.end.lnum)),
    ("end_column", @ion.IonValue::int(loc.end.cnum - loc.end.bol)),
  ])
}

///|
fn logical_path(text : String) -> @ir.Path raise FrontendError {
  try {
    let path = @ir.Path::parse(text)
    if text == "" || text.length() > 256 || path.to_canonical() != text {
      raise Invalid({
        code: "moonbit_frontend.invalid_identity",
        detail: "Package and module paths must be bounded and canonical",
        source: None,
      })
    }
    path
  } catch {
    Invalid(_) as error => raise error
    _ =>
      raise Invalid({
        code: "moonbit_frontend.invalid_identity",
        detail: "Invalid package or module path",
        source: None,
      })
  }
}

///|
/// Compile one pure, explicitly annotated Boolean function. No host access.
pub fn compile(
  input : Input,
  limits~ : Limits = Limits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> Output raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = compile_scoped(input, limits, cancelled, scope)
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
fn frontend_cancelled(error : Error) -> Bool {
  error is Invalid(diagnostic) &&
  diagnostic.code == "moonbit_frontend.cancelled"
}

///|
fn compile_scoped(
  input : Input,
  limits : Limits,
  cancelled : () -> Bool,
  scope : @observe.Scope,
) -> Output raise {
  fn input_error(code : String, detail : String) -> Unit raise FrontendError {
    raise Invalid({ code: "moonbit_frontend." + code, detail, source: None, })
  }
  limits.validate()
  if input.unit_id == "" ||
    input.unit_id.length() > 256 ||
    input.unit_id.to_array().any(c => c.to_int() < 32 || c.to_int() == 127) {
    input_error(
      "invalid_identity", "A bounded logical source identity is required",
    )
  }
  if cancelled() {
    input_error("cancelled", "Frontend cancelled")
  }
  if @utf8.encode(input.source).length() > limits.max_bytes {
    input_error("byte_limit", "Source exceeds the byte budget")
  }
  let package_name = logical_path(input.package_name)
  let module_name = logical_path(input.module_name)
  let nodes = scope.observe(
    @observe.Parse,
    fn(_) raise {
      check_lexing(input)
      let (nodes, reports) = @parser.parse_string(
        input.source,
        name=input.unit_id,
      )
      if cancelled() {
        input_error("cancelled", "Frontend cancelled")
      }
      if !reports.is_empty() {
        reject("syntax", reports[0].msg, reports[0].loc)
      }
      nodes
    },
    is_cancelled=frontend_cancelled,
  )
  let (decl, expr, lowerer, inputs, origins, public) = scope.observe(
    @observe.ProfileCheck,
    fn(_) raise {
      if nodes.length() != 1 {
        input_error(
          "declaration_count", "The first profile requires exactly one function",
        )
      }
      let node = nodes.head().unwrap()
      guard node
        is @ast.TopFuncDef(fun_decl=decl, decl_body=body, where_clause=None, ..) else {
        reject(
          "unsupported_declaration",
          "Only a top-level function is supported",
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
      let parameter_names = parameters.map(p => {
        match p {
          @ast.Positional(binder~, ..) => (binder.name, span(binder.loc))
          _ => {
            reject(
              "unsupported_parameters",
              "Only named positional parameters are supported",
              p.loc(),
            )
            abort("unreachable")
          }
        }
      })
      let names = BinderNames::new(
        parameter_names.iter().collect(),
        "binding:" + decl.name.name,
      )
      let boolean = boolean_type()
      let lowerer = Lowerer::{
        scope: Map([]),
        boolean,
        limits,
        cancelled,
        expressions: 0,
        names,
        origins: [],
      }
      let inputs = []
      let origins = []
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
        if lowerer.scope.contains(binder.name) {
          reject(
            "duplicate_parameter",
            "Duplicate parameter: " + binder.name,
            binder.loc,
          )
        }
        let name = lowerer.names.bind(binder.name)
        lowerer.scope[binder.name] = name
        inputs.push((name, boolean))
        origins.push(
          allocated_origin(
            origin(binder.name, binder.loc),
            name,
            lowerer.names.source.reason(binder.name),
          ),
        )
      }
      guard body is @ast.DeclBody(expr~) else {
        reject(
          "missing_body",
          "An ordinary expression body is required",
          decl.loc,
        )
        abort("unreachable")
      }
      (decl, expr, lowerer, inputs, origins, public)
    },
    is_cancelled=frontend_cancelled,
  )
  scope.observe(
    @observe.Lower,
    fn(_) raise {
      let boolean = lowerer.boolean
      let lowered = lowerer.lower(expr, 0)
      let allocated = allocate_source_names(
        [(decl.name.name, span(decl.name.loc))],
        package_name.to_canonical() + ":" + module_name.to_canonical(),
      )
      let name = allocated.names[decl.name.name]
      let warnings = allocated.warnings + lowerer.names.source.warnings
      let entry = @ir.FQName::parse(
        package_name.to_canonical() +
        ":" +
        module_name.to_canonical() +
        "#" +
        name.to_canonical(),
      )
      let module_def : @ir.ModuleDefinition = {
        types: Map([]),
        doc: None,
        values: Map::from_array([
          (
            name,
            {
              access: if public {
                @ir.Access::Public
              } else {
                @ir.Access::Private
              },
              value: {
                doc: None,
                value: @ir.ValueDefinition::ExpressionBody(
                  inputs, boolean, lowered,
                ),
              },
            },
          ),
        ]),
      }
      let ir = @ir.IRFile::new(
        @ir.Distribution::Library(package_name, Map([]), {
          modules: Map::from_array([
            (module_name, { access: @ir.Access::Public, value: module_def, }),
          ]),
        }),
      )
      let id = "value:" + entry.to_canonical()
      {
        unit_id: input.unit_id,
        ir,
        entry,
        public,
        metadata: [
          {
            node_id: id,
            data: ion_record([
              ("declaration", origin(decl.name.name, decl.name.loc)),
              (
                "naming",
                ion_record([
                  ("policy", @ion.IonValue::string(NAMING_POLICY)),
                  ("original", @ion.IonValue::string(decl.name.name)),
                  (
                    "allocation_reason",
                    @ion.IonValue::string(allocated.reason(decl.name.name)),
                  ),
                  ("identity", @ion.IonValue::string(name.to_canonical())),
                ]),
              ),
              ("parameters", @ion.IonValue::list(origins)),
            ]),
          },
          {
            node_id: id + "/body",
            data: ion_record([
              ("body", origin(decl.name.name, expr.loc())),
              ("nodes", @ion.IonValue::list(lowerer.origins.copy())),
            ]),
          },
        ],
        annotations: [@ion.SymbolToken::new("morphir_pipeline")],
        warnings,
        provenance: [
          ion_record([
            ("frontend", @ion.IonValue::string(PROFILE)),
            ("parser_version", @ion.IonValue::string(PARSER_VERSION)),
            ("naming_policy", @ion.IonValue::string(NAMING_POLICY)),
            ("unit_id", @ion.IonValue::string(input.unit_id)),
          ]).with_annotation(@ion.SymbolToken::new("morphir_moonbit_frontend")),
        ] +
        warnings.map(w => w.to_ion()),
      }
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Check budgets without parsing a source document.
pub fn Limits::validate(self : Limits) -> Unit raise FrontendError {
  if self.max_bytes <= 0 ||
    self.max_bytes > 65536 ||
    self.max_parameters < 0 ||
    self.max_parameters > 16 ||
    self.max_depth < 0 ||
    self.max_depth > 64 ||
    self.max_expressions <= 0 ||
    self.max_expressions > 4096 {
    raise Invalid({
      code: "moonbit_frontend.invalid_limits",
      detail: "Limits must stay within the supported profile budgets",
      source: None,
    })
  }
}

///|
/// Extend origin receipts without moving the fields consumed by source-label readers.
fn allocated_origin(
  original : @ion.IonValue,
  name : @ir.Name,
  reason : String,
) -> @ion.IonValue {
  guard original.kind() is Struct(fields) else {
    abort("Expected origin record")
  }
  @ion.IonValue::new(
    Struct(
      fields +
      [
        @ion.Field::new("identity", @ion.IonValue::string(name.to_canonical())),
        @ion.Field::new("allocation_reason", @ion.IonValue::string(reason)),
      ],
    ),
  ).with_annotations(original.annotations())
}

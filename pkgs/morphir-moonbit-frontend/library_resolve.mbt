///|
priv struct LibraryResolver {
  functions : Map[String, Int32]
  bindings : PinnedSourceBindings
  cancelled : () -> Bool
  names : BinderNames
}

///|
fn LibraryResolver::expression(
  self : LibraryResolver,
  expr : LibraryExpr,
  scope : Map[String, @ir.Name],
) -> ResolvedExpr raise {
  library_poll(self.cancelled)
  match expr {
    Boolean(value, source) => Boolean(value, source)
    Number(value, authored, scalar, source) =>
      Number(value, authored, scalar, source)
    Floating(value, authored, scalar, source) =>
      Floating(value, authored, scalar, source)
    Text(value, authored, source) => Text(value, authored, source)
    Constraint(value, ty, source) =>
      Constraint(self.expression(value, scope), ty, source)
    Identifier(text, source) =>
      match scope.get(text) {
        Some(name) => Variable(name, source)
        None => {
          library_error(
            if self.functions.contains(text) {
              "function_value"
            } else {
              "unknown_reference"
            },
            "Expected a bound value: " + text,
            Some(source),
          )
          abort("unreachable")
        }
      }
    Negation(value, source) => Negation(self.expression(value, scope), source)
    NumericNegation(value, source) =>
      NumericNegation(self.expression(value, scope), source)
    StringLength(value, source) =>
      StringLength(self.expression(value, scope), source)
    StringSlice(value, start, end, source) =>
      StringSlice(
        self.expression(value, scope),
        self.expression(start, scope),
        self.expression(end, scope),
        source,
      )
    Binary(op, lhs, rhs, source) =>
      Binary(
        op,
        self.expression(lhs, scope),
        self.expression(rhs, scope),
        source,
      )
    Conditional(cond, yes, no, source) =>
      Conditional(
        self.expression(cond, scope),
        self.expression(yes, scope),
        self.expression(no, scope),
        source,
      )
    Binding(text, binder_source, value, body, source) => {
      // The initializer sees the preceding scope, including an older shadowed name.
      let value = self.expression(value, scope)
      let name = self.names.bind(text)
      let nested = scope.copy()
      nested[text] = name
      Binding(
        name,
        text,
        binder_source,
        value,
        self.expression(body, nested),
        source,
      )
    }
    Call(text, arguments, source) => {
      if scope.contains(text) {
        library_error(
          "not_callable",
          "A value binding shadows the call target: " + text,
          Some(source),
        )
      }
      guard self.functions.get(text) is Some(index) else {
        library_error(
          "unknown_function",
          "Unknown library function: " + text,
          Some(source),
        )
        abort("unreachable")
      }
      Call(index, arguments.map(arg => self.expression(arg, scope)), source)
    }
    QualifiedCall(package_alias, source_name, arguments, source) => {
      if scope.contains(package_alias) {
        library_error(
          "shadowed_binding",
          "A local value shadows the source package alias: " + package_alias,
          Some(source),
        )
      }
      guard self.bindings.find(package_alias, source_name) is Some(index) else {
        library_error(
          "unknown_binding",
          "Unknown pinned source binding: @" + package_alias + "." + source_name,
          Some(source),
        )
        abort("unreachable")
      }
      SdkCall(index, arguments.map(arg => self.expression(arg, scope)), source)
    }
  }
}

///|
fn library_resolve(
  functions : Array[LibraryFunction],
  cancelled : () -> Bool,
  bindings : PinnedSourceBindings,
) -> Array[ResolvedFunction] raise {
  let indices : Map[String, Int32] = Map([])
  for i = 0; i < functions.length(); i = i + 1 {
    indices[functions[i].name] = i
  }
  let resolved = []
  for declaration in functions {
    library_poll(cancelled)
    let scope : Map[String, @ir.Name] = Map([])
    let bound_names = declaration.parameters.copy()
    collect_bindings(declaration.body, bound_names)
    let names = BinderNames::new(bound_names, "binding:" + declaration.name)
    let resolver = LibraryResolver::{
      functions: indices,
      bindings,
      cancelled,
      names,
    }
    let parameters = declaration.parameters.map(p => names.bind(p.0))
    for i = 0; i < parameters.length(); i = i + 1 {
      scope[declaration.parameters[i].0] = parameters[i]
    }
    resolved.push({
      declaration: {
        name: declaration.name,
        doc: declaration.doc,
        public: declaration.public,
        parameters: declaration.parameters,
        input_types: declaration.input_types,
        output_type: declaration.output_type,
        effect: declaration.effect,
        source: declaration.source,
        body_source: declaration.body_source,
      },
      parameters,
      names,
      types: Map([]),
      body: resolver.expression(declaration.body, scope),
    })
  }
  resolved
}

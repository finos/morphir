///|
/// Compile a pure Boolean library without host access or entry inference.
pub fn compile_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(input, limits, cancelled, scope)
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
fn library_compile_scoped(
  input : Input,
  limits : LibraryLimits,
  cancelled : () -> Bool,
  scope : @observe.Scope,
) -> LibraryOutput raise {
  limits.validate()

  if input.unit_id == "" ||
    input.unit_id.length() > 256 ||
    input.unit_id.to_array().any(c => c.to_int() < 32 || c.to_int() == 127) {
    library_error(
      "invalid_identity",
      "A bounded logical source identity is required",
      None,
    )
  }
  library_poll(cancelled)
  if @utf8.encode(input.source).length() > limits.max_bytes {
    library_error("byte_limit", "Source exceeds the byte budget", None)
  }
  let package_name = logical_path(input.package_name)
  let module_name = logical_path(input.module_name)
  let nodes = scope.observe(
    @observe.Parse,
    fn(_) raise { library_parse(input, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  let declarations = scope.observe(
    @observe.ProfileCheck,
    fn(_) raise { library_adapt(nodes, limits, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  let resolved = scope.observe(
    @observe.Resolve,
    fn(_) raise { library_resolve(declarations, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  let checked = scope.observe(
    @observe.ProfileCheck,
    fn(_) raise { library_check(resolved, limits, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  scope.observe(
    @observe.Lower,
    fn(_) raise {
      library_lower(input, package_name, module_name, checked, cancelled)
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Check library budgets without parsing a source document.
pub fn LibraryLimits::validate(
  self : LibraryLimits,
) -> Unit raise FrontendError {
  let hard = LibraryLimits::default()
  if self.max_bytes <= 0 ||
    self.max_bytes > hard.max_bytes ||
    self.max_functions <= 0 ||
    self.max_functions > hard.max_functions ||
    self.max_parameters < 0 ||
    self.max_parameters > hard.max_parameters ||
    self.max_lets < 0 ||
    self.max_lets > hard.max_lets ||
    self.max_expressions <= 0 ||
    self.max_expressions > hard.max_expressions ||
    self.max_calls < 0 ||
    self.max_calls > hard.max_calls ||
    self.max_depth < 0 ||
    self.max_depth > hard.max_depth ||
    self.max_call_depth < 0 ||
    self.max_call_depth > hard.max_call_depth {
    library_error(
      "invalid_limits",
      "Limits must stay within the supported library budgets",
      None,
    )
  }
}

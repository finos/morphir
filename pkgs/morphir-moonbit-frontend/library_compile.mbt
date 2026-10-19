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
  mode~ : LibraryMode = BooleanOnly,
  string_limit~ : Int32 = 1048576,
) -> LibraryOutput raise {
  limits.validate()
  if string_limit < 0 || string_limit > 1048576 {
    library_error(
      "invalid_limits",
      "String limit may only tighten the 1048576 code-unit bound",
      None,
    )
  }

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
  if mode.supports_strings() &&
    (
      package_name.to_canonical() == "morphir/SDK" ||
      package_name.to_canonical() == "morphir/moonbit-source"
    ) {
    library_error(
      "invalid_identity",
      "Source String libraries cannot own reserved SDK or source-runtime packages",
      None,
    )
  }
  let nodes = scope.observe(
    @observe.Parse,
    fn(_) raise { library_parse(input, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  let declarations = scope.observe(
    @observe.ProfileCheck,
    fn(_) raise { library_adapt(nodes, limits, cancelled, mode) },
    is_cancelled=frontend_cancelled,
  )
  let resolved = scope.observe(
    @observe.Resolve,
    fn(_) raise { library_resolve(declarations, cancelled) },
    is_cancelled=frontend_cancelled,
  )
  let checked = scope.observe(
    @observe.ProfileCheck,
    fn(_) raise { library_check(resolved, limits, cancelled, mode) },
    is_cancelled=frontend_cancelled,
  )
  scope.observe(
    @observe.Lower,
    fn(_) raise {
      library_lower(
        input, package_name, module_name, checked, cancelled, mode, string_limit,
      )
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

///|
/// Narrow mixed Bool/Int32 qualification profile. No numeric operators or literals.
pub fn compile_typed_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=TypedFoundation,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Signed Int32 source expressions with the existing Bool library subset.
pub fn compile_int32_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=NumericInt32,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Exact integral source forms with Bool and the previously qualified Int32 subset.
pub fn compile_integer_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=NumericInteger,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// IEEE binary32 and binary64 source expressions, with operation-local Float rounding.
pub fn compile_float_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=NumericFloat,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Compile String/Bool basics with executable source String boundary guards.
pub fn compile_string_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=StringBasics,
        string_limit=max_string_code_units,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Pinned cumulative v1 subset: Bool, bounded String basics and Int32
/// identity/selection/call paths. Ordering and numeric arithmetic are excluded.
pub fn compile_supported_library(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=SupportedLibrary,
        string_limit=max_string_code_units,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Cumulative v2 source subset, including String shortlex ordering.
/// Existing v1 source contracts remain pinned.
pub fn compile_supported_library_v2(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=SupportedLibraryV2,
        string_limit=max_string_code_units,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// The 2026-10-17 cumulative source snapshot. Historical APIs remain pinned.
pub fn compile_supported_library_2026_10_17(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=SupportedLibrary20261017,
        string_limit=max_string_code_units,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
/// Cumulative Bool, String, and signed Int32 source subset with indexed String operations.
pub fn compile_supported_library_2026_10_19(
  input : Input,
  limits~ : LibraryLimits = LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  strict_naming~ : Bool = false,
  cancelled~ : () -> Bool = fn() { false },
  scope~ : @observe.Scope = @observe.Observer::noop().scope(),
) -> LibraryOutput raise {
  scope.observe(
    @observe.Frontend,
    fn(scope) raise {
      let output = library_compile_scoped(
        input,
        limits,
        cancelled,
        scope,
        mode=SupportedLibrary20261019,
        string_limit=max_string_code_units,
      )
      check_naming_warnings(output.warnings, strict_naming)
      output
    },
    is_cancelled=frontend_cancelled,
  )
}

///|
fn library_expect(
  actual : LibraryTypeUse,
  expected : LibraryTypeUse,
  source : @ir.SourceLocation,
) -> Unit raise {
  if actual.scalar != expected.scalar {
    library_error(
      "type_mismatch",
      "Expected " + expected.spelling + ", received " + actual.spelling,
      Some(source),
    )
  }
}

///|
fn library_boolean(source : @ir.SourceLocation) -> LibraryTypeUse {
  { scalar: Boolean, spelling: "Bool", source, profile: "", }
}

///|
fn library_check_body(
  expr : ResolvedExpr,
  functions : Array[ResolvedFunction],
  types : Map[@ir.Name, LibraryTypeUse],
  edges : Map[Int32, Bool],
  cancelled : () -> Bool,
  mode : LibraryMode,
  bindings : PinnedSourceBindings,
  effect : LibraryEffect,
) -> LibraryTypeUse raise {
  library_poll(cancelled)
  fn check(e) raise {
    library_check_body(
      e, functions, types, edges, cancelled, mode, bindings, effect,
    )
  }
  match expr {
    Boolean(_, source) => library_boolean(source)
    Number(_, _, scalar, source) =>
      {
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: mode.profile(),
      }
    Floating(_, _, scalar, source) =>
      {
        scalar,
        spelling: scalar.source_name(),
        source,
        profile: mode.profile(),
      }
    Text(_, _, source) =>
      { scalar: Text, spelling: "String", source, profile: "", }
    Variable(name, _) => types[name]
    Constraint(value, ty, source) => {
      library_expect(check(value), ty, source)
      ty
    }
    Negation(value, source) => {
      let ty = library_boolean(source)
      library_expect(check(value), ty, source)
      ty
    }
    NumericNegation(value, source) => {
      let ty = check(value)
      if !(ty.scalar.is_signed() || ty.scalar.is_floating()) ||
        !mode.supports_numeric() {
        library_error(
          "unsupported_operator",
          "Unary minus requires a signed integer",
          Some(source),
        )
      }
      ty
    }
    StringLength(value, source) => {
      library_expect(
        check(value),
        { scalar: Text, spelling: "String", source, profile: mode.profile(), },
        source,
      )
      {
        scalar: SignedInt32,
        spelling: "Int32",
        source,
        profile: mode.profile(),
      }
    }
    StringSlice(value, start, end, source) => {
      library_expect(
        check(value),
        { scalar: Text, spelling: "String", source, profile: mode.profile(), },
        source,
      )
      let bound : LibraryTypeUse = {
        scalar: SignedInt32,
        spelling: "Int32",
        source,
        profile: mode.profile(),
      }
      library_expect(check(start), bound, source)
      library_expect(check(end), bound, source)
      { scalar: Text, spelling: "String", source, profile: mode.profile(), }
    }
    Binary(op, lhs, rhs, source) => {
      let left = check(lhs)
      let right = check(rhs)
      library_expect(right, left, source)
      if left.scalar.is_integer() && mode.supports_numeric() {
        if ["+", "-", "*"].contains(op) {
          left
        } else if ["==", "!=", "<", "<=", ">", ">="].contains(op) {
          library_boolean(source)
        } else {
          library_error(
            "unsupported_operator",
            "Operator is not defined for " + left.scalar.source_name(),
            Some(source),
          )
          abort("unreachable")
        }
      } else if left.scalar.is_floating() && mode.supports_float() {
        if ["+", "-", "*", "/"].contains(op) {
          left
        } else if ["==", "!=", "<", "<=", ">", ">="].contains(op) {
          library_boolean(source)
        } else {
          library_error(
            "unsupported_operator",
            "Unsupported floating operator",
            Some(source),
          )
          abort("unreachable")
        }
      } else if left.scalar == SdkInteger &&
        ["==", "!=", "<", "<=", ">", ">="].contains(op) {
        library_boolean(source)
      } else if left.scalar == Text {
        if op == "+" && mode.supports_strings() {
          left
        } else if ["==", "!="].contains(op) ||
          (mode.supports_string_order() && ["<", "<=", ">", ">="].contains(op)) {
          library_boolean(source)
        } else {
          library_error(
            "unsupported_operator",
            "Operator is not defined for String",
            Some(source),
          )
          abort("unreachable")
        }
      } else if ["&&", "||", "==", "!="].contains(op) {
        library_expect(left, library_boolean(source), source)
        library_boolean(source)
      } else {
        library_error(
          "unsupported_operator",
          "Operator is not defined for Bool",
          Some(source),
        )
        abort("unreachable")
      }
    }
    Conditional(cond, yes, no, source) => {
      library_expect(check(cond), library_boolean(source), source)
      let ty = check(yes)
      library_expect(check(no), ty, source)
      ty
    }
    Binding(name, _, _, value, body, _) => {
      types[name] = check(value)
      check(body)
    }
    Call(index, arguments, source) => {
      let signature = functions[index].declaration
      if signature.effect == SdkError && effect != SdkError {
        library_error(
          "error_contract",
          "A call that can raise SDK errors requires raise @sdk.SdkError",
          Some(source),
        )
      }
      if arguments.length() != signature.parameters.length() {
        library_error(
          "call_arity",
          "Library calls must supply every positional argument",
          Some(source),
        )
      }
      edges[index] = true
      for i = 0; i < arguments.length(); i = i + 1 {
        library_expect(check(arguments[i]), signature.input_types[i], source)
      }
      signature.output_type
    }
    SdkCall(index, arguments, source) => {
      let binding = bindings.entries[index]
      if binding.effect == SdkError && effect != SdkError {
        library_error(
          "error_contract",
          "The pinned SDK call requires raise @sdk.SdkError",
          Some(source),
        )
      }
      if arguments.length() != binding.inputs.length() {
        library_error(
          "binding_arity",
          "Pinned source binding requires " +
          binding.inputs.length().to_string() +
          " positional argument(s): @" +
          binding.source_alias +
          "." +
          binding.source_name,
          Some(source),
        )
      }
      for i = 0; i < arguments.length(); i = i + 1 {
        let expected : LibraryTypeUse = {
          scalar: binding.inputs[i],
          spelling: binding.inputs[i].source_name(),
          source,
          profile: mode.profile(),
        }
        library_expect(check(arguments[i]), expected, source)
      }
      {
        scalar: binding.output,
        spelling: binding.output.source_name(),
        source,
        profile: mode.profile(),
      }
    }
  }
}

///|
/// Leaf-first graph checking is bounded by declarations and distinct edges.
/// All declarations and syntactic branches count, even unreachable private ones.
fn library_check(
  functions : Array[ResolvedFunction],
  limits : LibraryLimits,
  cancelled : () -> Bool,
  mode : LibraryMode,
  bindings : PinnedSourceBindings,
) -> CheckedLibrary raise {
  let edges = functions.map(_ => Map([]))
  for i = 0; i < functions.length(); i = i + 1 {
    let function = functions[i]
    for j = 0; j < function.parameters.length(); j = j + 1 {
      function.types[function.parameters[j]] = function.declaration.input_types[j]
    }
    let result = library_check_body(
      function.body,
      functions,
      function.types,
      edges[i],
      cancelled,
      mode,
      bindings,
      function.declaration.effect,
    )
    library_expect(
      result,
      function.declaration.output_type,
      function.declaration.body_source,
    )
  }
  let remaining = edges.map(e => e.length())
  let depth = functions.map(_ => 0)
  let processed = functions.map(_ => false)
  let mut count = 0
  while count < functions.length() {
    library_poll(cancelled)
    let mut progress = false
    for i = 0; i < functions.length(); i = i + 1 {
      if processed[i] || remaining[i] != 0 {
        continue
      }
      processed[i] = true
      count += 1
      progress = true
      if depth[i] > limits.max_call_depth {
        library_error(
          "call_depth_limit",
          "Call graph exceeds the depth budget",
          Some(functions[i].declaration.source),
        )
      }
      for caller = 0; caller < functions.length(); caller = caller + 1 {
        if edges[caller].contains(i) {
          remaining[caller] -= 1
          depth[caller] = Int32::max(depth[caller], depth[i] + 1)
        }
      }
    }
    if !progress {
      for i = 0; i < functions.length(); i = i + 1 {
        if !processed[i] {
          library_error(
            "recursive_call",
            "Recursive library call graphs are unsupported",
            Some(functions[i].declaration.source),
          )
        }
      }
    }
  }
  { functions, }
}

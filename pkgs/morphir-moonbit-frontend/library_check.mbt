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
  { scalar: Boolean, spelling: "Bool", source, }
}

///|
fn library_check_body(
  expr : ResolvedExpr,
  functions : Array[ResolvedFunction],
  types : Map[@ir.Name, LibraryTypeUse],
  edges : Map[Int32, Bool],
  cancelled : () -> Bool,
) -> LibraryTypeUse raise {
  library_poll(cancelled)
  fn check(e) raise {
    library_check_body(e, functions, types, edges, cancelled)
  }
  match expr {
    Boolean(_, source) => library_boolean(source)
    Text(_, _, source) => { scalar: Text, spelling: "String", source, }
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
    Binary(op, lhs, rhs, source) => {
      let left = check(lhs)
      let right = check(rhs)
      library_expect(right, left, source)
      if op == "+" || ["<", "<=", ">", ">="].contains(op) {
        library_expect(
          left,
          { scalar: Text, spelling: "String", source, },
          source,
        )
        if op == "+" {
          left
        } else {
          library_boolean(source)
        }
      } else {
        if (op == "&&" || op == "||") || left.scalar != Text {
          library_expect(left, library_boolean(source), source)
        }
        library_boolean(source)
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
  }
}

///|
/// Leaf-first graph checking is bounded by declarations and distinct edges.
/// All declarations and syntactic branches count, even unreachable private ones.
fn library_check(
  functions : Array[ResolvedFunction],
  limits : LibraryLimits,
  cancelled : () -> Bool,
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

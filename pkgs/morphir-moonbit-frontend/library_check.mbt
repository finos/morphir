///|
/// Every expression in this closed grammar produces Bool. Calls require exact
/// signature arity; function values and partial applications never enter it.
fn library_check_body(
  expr : ResolvedExpr,
  functions : Array[ResolvedFunction],
  edges : Map[Int32, Bool],
  cancelled : () -> Bool,
) -> Unit raise {
  library_poll(cancelled)
  match expr {
    Boolean(_, _) | Variable(_, _) => ()
    Negation(value, _) => library_check_body(value, functions, edges, cancelled)
    Binary(_, lhs, rhs, _) => {
      library_check_body(lhs, functions, edges, cancelled)
      library_check_body(rhs, functions, edges, cancelled)
    }
    Conditional(cond, yes, no, _) => {
      library_check_body(cond, functions, edges, cancelled)
      library_check_body(yes, functions, edges, cancelled)
      library_check_body(no, functions, edges, cancelled)
    }
    Binding(_, _, _, value, body, _) => {
      library_check_body(value, functions, edges, cancelled)
      library_check_body(body, functions, edges, cancelled)
    }
    Call(index, arguments, source) => {
      if arguments.length() != functions[index].parameters.length() {
        library_error(
          "call_arity",
          "Library calls must supply every positional Boolean argument",
          Some(source),
        )
      }
      edges[index] = true
      for arg in arguments {
        library_check_body(arg, functions, edges, cancelled)
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
) -> CheckedLibrary raise {
  let edges = functions.map(_ => Map([]))
  for i = 0; i < functions.length(); i = i + 1 {
    library_check_body(functions[i].body, functions, edges[i], cancelled)
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

///|
/// The IR module path: the module name without the package segments.
pub fn module_path(
  module_name : Array[String],
  pkg_segs : Array[String],
) -> @ir.Path {
  @mapping.elm_path(module_name[pkg_segs.length():].to_owned())
}

///|
fn dotted(segments : Array[String]) -> String {
  segments.join(".")
}

///|
/// The package name in Elm module syntax. `morphir.json` may write it with `/` (for example `Morphir/Sample`, which
/// morphir-elm accepts); Elm module names use `.`.
fn elm_package(package_name : String) -> String {
  package_name.replace_all(old="/", new=".")
}

///|
fn package_segments(package_name : String) -> Array[String] {
  package_name.split(".").map(s => s.to_owned()).collect()
}

///|
/// Parses every source, then checks the module rules and the import cycles. All sources are parsed before the first
/// problem is raised. Unlike `compile_project`, it checks the module rules of every module, also of a module that no
/// exposed module imports.
pub fn parse_modules(
  sources : Array[ElmSource],
  package_name : String,
) -> Array[@resolve.ParsedModule] raise ElmFailed {
  let parsed = parse_sources(sources, elm_package(package_name))
  let problems : Array[ElmProblem] = []
  for entry in parsed {
    problems.append(entry.1)
  }
  fail_if_any(problems)
  let modules = parsed.map(entry => entry.0)
  check_cycles(modules)
  modules
}

///|
/// Parses every source and raises all parse problems. Each parsed module comes with the problems of its module
/// rules: a port or effect module, a module name that does not match the path or does not start with the package
/// name. The module name is the one in the header. morphir-elm checks these rules only for the modules that it
/// processes.
fn parse_sources(
  sources : Array[ElmSource],
  package_name : String,
) -> Array[(@resolve.ParsedModule, Array[ElmProblem])] raise ElmFailed {
  let pkg_segs = package_segments(package_name)
  let problems : Array[ElmProblem] = []
  let parsed : Array[(@resolve.ParsedModule, Array[ElmProblem])] = []
  for source in sources {
    let result = @krueger.parse_module(@krueger.SourceText::new(source.content))
    let errors = result.diagnostics.filter(d => d.severity is Error)
    for d in errors {
      problems.push({
        code: "elm.parse",
        message: d.code + ": " + d.message,
        path: source.path,
        location: Some({
          start_line: d.span.start.line,
          start_column: d.span.start.column,
          end_line: d.span.end.line,
          end_column: d.span.end.column,
        }),
      })
    }
    guard result.ast is Some(file) && errors.is_empty() else {
      if errors.is_empty() {
        problems.push(
          problem("elm.parse", "the module does not parse", source.path, None),
        )
      }
      continue
    }
    let m : @resolve.ParsedModule = { name: [], path: source.path, file, }
    let name = m.header().module_name.value.to_owned()
    parsed.push(({ ..m, name, }, module_rules(m, name, pkg_segs, package_name)))
  }
  fail_if_any(problems)
  parsed
}

///|
/// The module rule problems of one parsed module: at most one.
fn module_rules(
  m : @resolve.ParsedModule,
  name : Array[String],
  pkg_segs : Array[String],
  package_name : String,
) -> Array[ElmProblem] {
  let header = m.file.module_definition
  if !(header.value is NormalModule(_)) {
    return [
      problem(
        "elm.unsupported",
        "port and effect modules are not supported",
        m.path,
        Some(header.range),
      ),
    ]
  }
  let expected = m.path
    .strip_suffix(".elm")
    .unwrap_or(m.path)
    .split("/")
    .map(s => s.to_owned())
    .collect()
  if name != expected {
    return [
      problem(
        "elm.module_name",
        "the module \{dotted(name)} must be in \{dotted(name).replace_all(old=".", new="/")}.elm",
        m.path,
        Some(m.header().module_name.range),
      ),
    ]
  }
  if name.length() <= pkg_segs.length() ||
    name[:pkg_segs.length()].to_owned() != pkg_segs {
    return [
      problem(
        "elm.module_name",
        "the module \{dotted(name)} must start with the package name \{package_name} and have one more segment",
        m.path,
        Some(m.header().module_name.range),
      ),
    ]
  }
  []
}

///|
/// Elm forbids import cycles. A depth-first search visits the modules in source order and follows their imports in
/// source order. The first import that goes back to a module on the search path closes a cycle: the module of that
/// import gets the problem, at the range of the import, and the message lists the cycle from that module.
fn check_cycles(modules : Array[@resolve.ParsedModule]) -> Unit raise ElmFailed {
  let by_name : Map[String, @resolve.ParsedModule] = Map([])
  for m in modules {
    by_name[dotted(m.name)] = m
  }
  // 0 = new, 1 = on the stack, 2 = done
  let state : Map[String, Int] = Map([])
  let problems : Array[ElmProblem] = []
  fn visit(name : String, stack : Array[String]) -> Unit {
    if state.get(name) is Some(_) || !problems.is_empty() {
      return
    }
    guard by_name.get(name) is Some(m) else { return }
    state[name] = 1
    stack.push(name)
    for i in m.file.imports {
      let target = dotted(i.value.module_name.value.to_owned())
      if state.get(target) is Some(1) {
        // The stack ends with `name`; the cycle goes from `name` to `target` and back along the stack.
        let start = stack.search(target).unwrap_or(0)
        let cycle = [name]
        cycle.append(stack[start:].to_owned())
        problems.push(
          problem(
            "elm.import_cycle",
            "the imports form a cycle: " + cycle.join(" -> "),
            m.path,
            Some(i.range),
          ),
        )
        return
      }
      if by_name.contains(target) {
        visit(target, stack)
      }
    }
    ignore(stack.pop())
    state[name] = 2
  }
  for m in modules {
    visit(dotted(m.name), [])
  }
  fail_if_any(problems)
}

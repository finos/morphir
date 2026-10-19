///|
/// Compare two types by structure. References compare by FQName and variables by a
/// bijective renaming. Paired variables must have the same constraint class. Other attributes
/// are ignored.
fn same_type(
  a : @ir.Type,
  b : @ir.Type,
  ab : Map[@ir.Name, @ir.Name],
  ba : Map[@ir.Name, @ir.Name],
) -> Bool {
  match (a, b) {
    (Variable(cx, x), Variable(cy, y)) =>
      class_of_variable(x, cx) == class_of_variable(y, cy) && bind(x, y, ab, ba)
    (Reference(_, fa, xs), Reference(_, fb, ys)) =>
      fa == fb && same_types(xs, ys, ab, ba)
    (Tuple(_, xs), Tuple(_, ys)) => same_types(xs, ys, ab, ba)
    (Union(_, xs), Union(_, ys)) => same_types(xs, ys, ab, ba)
    (Record(_, fa), Record(_, fb)) => same_fields(fa, fb, ab, ba)
    (ExtensibleRecord(cx, x, fa), ExtensibleRecord(cy, y, fb)) =>
      class_of_variable(x, cx) == class_of_variable(y, cy) &&
      bind(x, y, ab, ba) &&
      same_fields(fa, fb, ab, ba)
    (Function(_, pa, ra), Function(_, pb, rb)) =>
      same_type(pa, pb, ab, ba) && same_type(ra, rb, ab, ba)
    (Unit(_), Unit(_)) => true
    _ => false
  }
}

///|
/// The constraint class of a variable: its `typeclass` constraint, else its name prefix. The
/// longest prefix wins.
fn class_of_variable(name : @ir.Name, attrs : @ir.TypeAttributes) -> String? {
  if attrs.constraints.get("typeclass") is Some(Text(class)) {
    return Some(class)
  }
  let text = name.to_canonical()
  for class in ["compappend", "appendable", "comparable", "number"] {
    if text.has_prefix(class) {
      return Some(class)
    }
  }
  None
}

///|
fn bind(
  x : @ir.Name,
  y : @ir.Name,
  ab : Map[@ir.Name, @ir.Name],
  ba : Map[@ir.Name, @ir.Name],
) -> Bool {
  match (ab.get(x), ba.get(y)) {
    (None, None) => {
      ab[x] = y
      ba[y] = x
      true
    }
    (Some(y2), Some(x2)) => y2 == y && x2 == x
    _ => false
  }
}

///|
fn same_types(
  xs : Array[@ir.Type],
  ys : Array[@ir.Type],
  ab : Map[@ir.Name, @ir.Name],
  ba : Map[@ir.Name, @ir.Name],
) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  for i in 0..<xs.length() {
    if !same_type(xs[i], ys[i], ab, ba) {
      return false
    }
  }
  true
}

///|
fn same_fields(
  fa : Map[@ir.Name, @ir.Type],
  fb : Map[@ir.Name, @ir.Type],
  ab : Map[@ir.Name, @ir.Name],
  ba : Map[@ir.Name, @ir.Name],
) -> Bool {
  if fa.length() != fb.length() {
    return false
  }
  for name, t in fa {
    guard fb.get(name) is Some(u) else { return false }
    if !same_type(t, u, ab, ba) {
      return false
    }
  }
  true
}

///|
/// The canonical parameter names of a signature, made unique. The IR refuses two parameters
/// with one name, and morphir-elm has some (`Result.map3` has `result2` twice). A repeated name
/// takes the next free number: `result-1`, `result-2`, `result-2` becomes `result-1`, `result-2`,
/// `result-3`.
fn unique_parameter_names(names : Array[String]) -> Array[String] {
  let used : Map[String, Bool] = Map([])
  names.map(name => {
    let mut candidate = name
    while used.contains(candidate) {
      candidate = bump(candidate)
    }
    used[candidate] = true
    candidate
  })
}

///|
fn bump(name : String) -> String {
  let mut cut = name.length()
  while cut > 0 && name[cut - 1] >= '0' && name[cut - 1] <= '9' {
    cut -= 1
  }
  if cut < name.length() && cut > 0 && name[cut - 1] == '-' {
    let number = @parse.parse_int(name[cut:].to_owned()) catch { _ => 1 }
    "\{name[:cut]}\{number + 1}"
  } else {
    "\{name}-2"
  }
}

///|
/// Compare the signature in bindings.json with the one in sdk.scm.
fn compare_signature(
  fq_name : String,
  params : Array[(String, @ir.Type)],
  result : @ir.Type,
  specification : @ir.ValueSpecification,
  problems : Array[String],
) -> Unit {
  if params.length() != specification.inputs.length() {
    problems.push(
      "\{fq_name}: bindings.json has \{params.length()} parameters, sdk.scm has \{specification.inputs.length()}",
    )
    return
  }
  let ab : Map[@ir.Name, @ir.Name] = Map([])
  let ba : Map[@ir.Name, @ir.Name] = Map([])
  let names = unique_parameter_names(
    params.map(p => @vspec.canonical_name(p.0)),
  )
  for i in 0..<params.length() {
    let expected = names[i]
    let actual = specification.inputs[i].0.to_canonical()
    if expected != actual {
      problems.push(
        "\{fq_name}: parameter \{i + 1} is `\{expected}` in bindings.json and `\{actual}` in sdk.scm",
      )
    }
    if !same_type(params[i].1, specification.inputs[i].1, ab, ba) {
      problems.push("\{fq_name}: the type of parameter `\{expected}` differs")
    }
  }
  if !same_type(result, specification.output, ab, ba) {
    problems.push("\{fq_name}: the result type differs")
  }
}

///|
/// Every difference between bindings.json, sdk.scm and sdk_data.mbt.
fn check() -> (Array[String], Int32) raise Error {
  let problems : Array[String] = []
  let scm = @fs.read_file_to_string(scm_path)
  let (_, specification) = @spec.read_package(scm)
  let root = @json.parse(@fs.read_file_to_string(bindings_path))
  guard root is Object(fields) && fields.get("values") is Some(Array(values)) else {
    raise ToolError("\{bindings_path} has no `values` array")
  }
  let seen : Map[String, Bool] = Map([])
  let mut count = 0
  for i, entry in values {
    guard entry is Object(object) else {
      problems.push("values[\{i}] is not an object")
      continue
    }
    let fq_name = string_field(object, "fqName", i)
    let elm_name = string_field(object, "elmName", i)
    let text = string_field(object, "specification", i)
    guard module_of(fq_name) is Some(module_text) else {
      problems.push("\{fq_name}: not a morphir/SDK:<module>#<name> name")
      continue
    }
    let path = @ir.Path::parse(module_text) catch {
      _ => {
        problems.push("\{fq_name}: bad module name")
        continue
      }
    }
    let (_, params, result) = @vspec.parse_vspec(text) catch {
      @vspec.VSpecError(message) => {
        problems.push("\{fq_name}: \{message}")
        continue
      }
    }
    let name = @vspec.elm_name(elm_name)
    seen["\{path.to_canonical()}#\{name.to_canonical()}"] = true
    count += 1
    let found = match specification.modules.get(path) {
      Some(m) => m.values.get(name)
      None => None
    }
    match found {
      None => problems.push("\{fq_name}: in bindings.json but not in sdk.scm")
      Some(documented) =>
        compare_signature(fq_name, params, result, documented.value, problems)
    }
  }
  for path, m in specification.modules {
    for name, _ in m.values {
      let key = "\{path.to_canonical()}#\{name.to_canonical()}"
      if !seen.contains(key) {
        problems.push("morphir/SDK:\{key}: in sdk.scm but not in bindings.json")
      }
    }
  }
  let expected = generated_text(scm)
  let actual = @fs.read_file_to_string(data_path) catch {
    _ => {
      problems.push(
        "\{data_path}: cannot read it; run `mise run sdk-spec:generate`",
      )
      return (problems, count)
    }
  }
  if actual != expected {
    problems.push("\{data_path}: is stale; run `mise run sdk-spec:generate`")
  }
  (problems, count)
}

///|
/// A failed bootstrap. The message lists every problem.
priv suberror BootstrapError {
  BootstrapError(String)
}

///|
/// The hand-written SDK types. They stay hand-maintained after the bootstrap.
let sdk_types : String =
  #|(package "morphir/SDK"
  #|  (module basics
  #|    (type int (opaque))
  #|    (type float (opaque))
  #|    (type bool (opaque))
  #|    (type never (opaque))
  #|    (type order (custom (LT) (EQ) (GT))))
  #|  (module char (type char (opaque)))
  #|  (module string (type string (opaque)))
  #|  (module list (type list (opaque) a))
  #|  (module maybe (type maybe (custom (just a) (nothing)) a))
  #|  (module result (type result (custom (ok a) (err e)) e a))
  #|  (module dict (type dict (opaque) k v))
  #|  (module set (type set (opaque) a))
  #|  (module decimal (type decimal (opaque)))
  #|  (module int (type int-8 (opaque)) (type int-16 (opaque)) (type int-32 (opaque)) (type int-64 (opaque))))

///|
/// The module part of `morphir/SDK:<module>#<name>`.
fn module_of(fq_name : String) -> String? {
  guard fq_name.find(":") is Some(colon) else { return None }
  guard fq_name.find("#") is Some(hash) else { return None }
  if hash <= colon {
    return None
  }
  Some(fq_name[colon + 1:hash].to_owned())
}

///|
fn string_field(
  object : Map[String, Json],
  key : String,
  entry : Int32,
) -> String raise BootstrapError {
  match object.get(key) {
    Some(String(s)) => s
    _ => raise BootstrapError("values[\{entry}] has no text field `\{key}`")
  }
}

///|
fn bootstrap(bindings : String, out : String) -> String raise Error {
  let text = @fs.read_file_to_string(bindings)
  let root = @json.parse(text)
  guard root is Object(fields) && fields.get("values") is Some(Array(values)) else {
    raise BootstrapError("\{bindings} has no `values` array")
  }
  let (package_name, base) = @spec.read_package(sdk_types)
  let modules : Map[@ir.Path, @ir.ModuleSpecification] = Map([])
  let problems : Array[String] = []
  let mut count = 0
  for i, entry in values {
    guard entry is Object(object) else {
      problems.push("values[\{i}] is not an object")
      continue
    }
    let fq_name = string_field(object, "fqName", i)
    let elm_name = string_field(object, "elmName", i)
    let specification = string_field(object, "specification", i)
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
    let (_, params, result) = @vspec.parse_vspec(specification) catch {
      @vspec.VSpecError(message) => {
        problems.push("\{fq_name}: \{message}")
        continue
      }
    }
    if !modules.contains(path) {
      let types = match base.modules.get(path) {
        Some(m) => m.types
        None => Map([])
      }
      modules[path] = { annotations: [], types, values: Map([]), doc: None, }
    }
    let module_ = modules.get(path).unwrap()
    let name = @vspec.elm_name(elm_name)
    if module_.values.contains(name) {
      problems.push("\{fq_name}: duplicate value `\{name.to_canonical()}`")
      continue
    }
    let names = unique_parameter_names(
      params.map(p => @vspec.canonical_name(p.0)),
    )
    let inputs = params.mapi((i, p) => {
      (@ir.Name::parse(names[i]) catch { _ => @vspec.elm_name(p.0) }, p.1)
    })
    module_.values[name] = {
      doc: None,
      value: { annotations: [], inputs, output: result, },
    }
    count += 1
  }
  if !problems.is_empty() {
    raise BootstrapError(
      "\{problems.length()} problems:\n" + problems.join("\n"),
    )
  }
  for path, m in base.modules {
    if !modules.contains(path) {
      modules[path] = m
    }
  }
  let printed = @spec.print_package(package_name, { modules, })
  // The result must read back.
  ignore(@spec.read_package(printed))
  @fs.write_string_to_file(out, printed + "\n")
  "wrote \{count} values in \{modules.length()} modules to \{out}"
}

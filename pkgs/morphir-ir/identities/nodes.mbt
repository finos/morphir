///|
fn part(text : String) -> String {
  // Most names have neither character, and need no escape.
  if !text.contains_char('~') && !text.contains_char('/') {
    return text
  }
  text
  .split("~")
  .map(StringView::to_owned)
  .collect()
  .join("~0")
  .split("/")
  .map(StringView::to_owned)
  .collect()
  .join("~1")
}

///|
/// The deepest JSON tree that identity collection walks. Deeper trees are refused, not walked.
const MAX_DEPTH : Int32 = 128

///|
/// The most identities that identity collection keeps for one unit.
const MAX_NODES : Int32 = 100000

///|
fn collect(
  prefix : String,
  value : Json,
  result : Map[String, Bool],
  depth~ : Int32 = 0,
) -> Unit raise {
  if depth > MAX_DEPTH {
    raise @codec_boundary.Invalid(
      "identity.tree_limit",
      "Identity depth exceeds the limit of \{MAX_DEPTH}",
    )
  }
  if result.length() > MAX_NODES {
    raise @codec_boundary.Invalid(
      "identity.tree_limit",
      "Identity node count exceeds the limit of \{MAX_NODES}",
    )
  }
  result[prefix] = true
  match value {
    Object(fields) =>
      for name, item in fields {
        collect(prefix + "/" + part(name), item, result, depth=depth + 1)
      }
    Array(items) =>
      for i, item in items {
        collect(prefix + "/" + i.to_string(), item, result, depth=depth + 1)
      }
    _ => ()
  }
}

///|
/// Stable declaration identities, with JSON-pointer suffixes for structural children.
/// Pair-array indices denote positions, not identities preserved through reordering.
pub fn nodes(unit_id : String, file : @ir.IRFile) -> Array[String] raise {
  let result = node_set(unit_id, file).keys().collect()
  result.sort()
  result
}

///|
/// The identities of `nodes` as a set, for a caller that only asks whether a
/// node exists: it is not sorted. A caller that has `@ir_json.to_json(file)`
/// already passes it as `json`, so that the file is not encoded again.
pub fn node_set(
  unit_id : String,
  file : @ir.IRFile,
  json? : Json,
) -> Map[String, Bool] raise {
  let owned = Map::from_array([("unit:" + unit_id, true)])
  let json = match json {
    Some(json) => json
    None => @ir_json.to_json(file)
  }
  collect("unit:" + unit_id + "/ir", json, owned)
  if file.distribution is Library(package_name, _, definition) {
    for module_name, module_def in definition.modules {
      let module_id = "module:" +
        package_name.to_canonical() +
        ":" +
        module_name.to_canonical()
      owned[module_id] = true
      for name, value in module_def.value.values {
        let id = "value:" +
          package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()
        owned[id] = true
        collect(
          id + "/definition",
          @codec.write_definition(value.value.value),
          owned,
        )
        match value.value.value {
          ExpressionBody(inputs, output, body) => {
            collect(id + "/output", @codec.write_type(output), owned)
            collect(id + "/body", @codec.write_value(body), owned)
            for input in inputs {
              collect(
                id + "/input/" + part(input.0.to_canonical()),
                @codec.write_type(input.1),
                owned,
              )
            }
          }
          _ => ()
        }
      }
      for name, entry in module_def.value.types {
        let id = "type:" +
          package_name.to_canonical() +
          ":" +
          module_name.to_canonical() +
          "#" +
          name.to_canonical()
        owned[id] = true
        if entry.value.value is CustomTypeDefinition(_, constructors) {
          for constructor_name, _ in constructors.value {
            owned["constructor:" +
            package_name.to_canonical() +
            ":" +
            module_name.to_canonical() +
            "#" +
            constructor_name.to_canonical()] = true
          }
        }
      }
    }
  }
  owned
}

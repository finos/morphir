///|
fn ion_field(value : @ion.IonValue, name : String) -> @ion.IonValue {
  match value.kind() {
    Struct(fields) => {
      for field in fields {
        if field.name().text() == Some(name) {
          return field.value()
        }
      }
      @ion.IonValue::untyped_null()
    }
    _ => @ion.IonValue::untyped_null()
  }
}

///|
fn ion_name(value : @ion.IonValue) -> String {
  match ion_field(value, "name").kind() {
    String(name) => name
    _ => ""
  }
}

///|
fn source_names(
  metadata : Array[@data.NodeMetadata],
  entry : String,
) -> (String, Array[String])? {
  for item in metadata {
    if item.node_id == "value:" + entry {
      let name = ion_name(ion_field(item.data, "declaration"))
      let parameters = match ion_field(item.data, "parameters").kind() {
        List(values) => values.map(ion_name)
        _ => []
      }
      if name != "" {
        return Some((name, parameters))
      }
    }
  }
  None
}

///|
/// Source spelling labels every declaration; canonical IR identities stay intact.
fn source_ui(
  fields : Array[(String, Json)],
  metadata : Array[@data.NodeMetadata],
) -> Unit {
  fn inputs(
    rows : Array[Json],
    parameters : Array[String],
    key : String,
  ) -> Json {
    Json::array(
      rows.mapi((index, input) => {
        if input is Object(row) {
          let row = row.copy()
          row[key] = @wire.text(
            parameters.get(index).unwrap_or(node_text(input, key)),
          )
          Json::object(row)
        } else {
          input
        }
      }),
    )
  }
  for i, (key, value) in fields {
    if key == "nodes" && value is Array(nodes) {
      fields[i] = (
        key,
        Json::array(
          nodes.map(node => {
            if node is Object(data) &&
              source_names(metadata, node_text(node, "id"))
              is Some((name, parameters)) {
              let data = data.copy()
              let original = node_text(node, "label")
              data["label"] = @wire.text(name)
              data["signature"] = @wire.text(
                node_text(node, "signature").replace_all(old=original, new=name),
              )
              if data.get("inputs") is Some(Array(rows)) {
                data["inputs"] = inputs(rows, parameters, "name")
              }
              Json::object(data)
            } else {
              node
            }
          }),
        ),
      )
    } else if key == "typedEvaluations" &&
      value is Object(profiles) &&
      profiles.get("entries") is Some(Object(entries)) {
      let entries = entries.copy()
      for entry, value in entries {
        if value is Object(profile) &&
          profile.get("inputs") is Some(Array(rows)) &&
          source_names(metadata, entry) is Some((_, parameters)) {
          let profile = profile.copy()
          profile["inputs"] = inputs(rows, parameters, "label")
          entries[entry] = Json::object(profile)
        }
      }
      fields[i] = (key, @wire.obj([("entries", Json::object(entries))]))
    }
  }
}

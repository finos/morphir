///|
pub(all) enum Segment {
  Index(Int32)
  Field(String)
}

///|
pub(all) enum Edit {
  Set(Array[Segment], Json)
  Scalar(Array[Segment], String, String)
  Float64(Array[Segment], String)
  TextUnits(Array[Segment], String)
  Append(Array[Segment], Json)
  Remove(Array[Segment], Int32)
}

///|
fn modify(
  value : Json,
  path : Array[Segment],
  at : Int32,
  change : (Json) -> Json raise,
) -> Json raise {
  if at == path.length() {
    return change(value)
  }
  match path[at] {
    Index(index) => {
      let values = @wire.array(value).copy()
      if index < 0 || index >= values.length() {
        raise @wire.Invalid(
          "invalid_path", "Argument index is no longer present",
        )
      }
      values[index] = modify(values[index], path, at + 1, change)
      Json::array(values)
    }
    Field(name) => {
      let fields = Map::from_array(@wire.object(value).iter().collect())
      let child = match fields.get(name) {
        Some(child) => child
        None =>
          raise @wire.Invalid(
            "invalid_path", "Argument field is no longer present",
          )
      }
      fields[name] = modify(child, path, at + 1, change)
      Json::object(fields)
    }
  }
}

///|
/// Preserve in-progress numeric text as a string; the runtime codec rejects it
/// until completed. Valid number lexemes retain their spelling in the JSON AST.
fn scalar(kind : String, value : String) -> Json raise {
  match kind {
    "float" => @wire.number(value) catch { _ => Json::string(value) }
    "bool" =>
      match value {
        "true" => Json::boolean(true)
        "false" => Json::boolean(false)
        _ => raise @wire.Invalid("invalid_boolean", "Expected true or false")
      }
    "int" | "string" | "char" => Json::string(value)
    _ => raise @wire.Invalid("invalid_scalar", "Unsupported input field")
  }
}

///|
/// Apply each action to the latest document, rather than a render-time snapshot.
pub fn edit(document : String, action : Edit) -> String raise {
  if action is Set([], replacement) {
    return replacement.stringify()
  }
  let value = @wire.parse(document)
  let (path, change) : (Array[Segment], (Json) -> Json raise) = match action {
    Set(path, replacement) => (path, fn(_) { replacement })
    Scalar(path, kind, text) => {
      let replacement = scalar(kind, text)
      (path, fn(_) { replacement })
    }
    Float64(path, text) => {
      let bits = @wire.text(
        @wire.float(@wire.number(text)).reinterpret_as_uint64().to_string(),
      ) catch {
        _ => @wire.text(text)
      }
      (path, fn(_) { bits })
    }
    TextUnits(path, text) => {
      let units = Json::array(
        text
        .code_units()
        .to_owned()
        .map(unit => Json::number(unit.to_int().to_double())),
      )
      (path, fn(_) { units })
    }
    Append(path, item) =>
      (
        path,
        fn(value) raise {
          let values = @wire.array(value).copy()
          values.push(item)
          Json::array(values)
        },
      )
    Remove(path, index) =>
      (
        path,
        fn(value) raise {
          let values = @wire.array(value)
          if index < 0 || index >= values.length() {
            raise @wire.Invalid(
              "invalid_path", "List item is no longer present",
            )
          }
          Json::array(
            values
            .mapi((i, value) => (i, value))
            .filter(pair => pair.0 != index)
            .map(pair => pair.1),
          )
        },
      )
  }
  modify(value, path, 0, change).stringify()
}

///|
pub fn scalar_text(value : Json) -> String {
  match value {
    String(text) => text
    Null => ""
    _ => value.stringify()
  }
}

///|
fn check_shape(
  schema : Json,
  value : Json,
  path : String,
  budget : Ref[Int32],
) -> Unit raise {
  budget.val -= 1
  if budget.val < 0 {
    raise @wire.Invalid(
      "form_limit", "This input is too large for fields. Use JSON inputs to edit it",
    )
  }
  fn mismatch() -> Unit raise {
    raise @wire.Invalid(
      "invalid_shape",
      path + ": expected " + @wire.string(@wire.field(schema, "label")),
    )
  }
  match @wire.string(@wire.field(schema, "kind")) {
    "unit" => if value != Json::null() { mismatch() }
    "float" =>
      match value {
        Number(_, ..) | String(_) => ()
        _ => mismatch()
      }
    "int" | "string" | "char" =>
      match value {
        String(_) => ()
        _ => mismatch()
      }
    "bool" =>
      match value {
        True | False => ()
        _ => mismatch()
      }
    "record" => {
      let fields = @wire.object(@wire.field(schema, "fields"))
      let data = @wire.object(value)
      if fields.length() != data.length() {
        return mismatch()
      }
      for key, child in fields {
        let value = match data.get(key) {
          Some(value) => value
          None => return mismatch()
        }
        check_shape(child, value, path + "." + key, budget)
      }
    }
    "list" =>
      for i, value in @wire.array(value) {
        check_shape(
          @wire.field(schema, "item"),
          value,
          path + "[" + (i + 1).to_string() + "]",
          budget,
        )
      }
    "tuple" => {
      let schemas = @wire.array(@wire.field(schema, "items"))
      let values = @wire.array(value)
      if schemas.length() != values.length() {
        return mismatch()
      }
      for i, child in schemas {
        check_shape(
          child,
          values[i],
          path + "[" + (i + 1).to_string() + "]",
          budget,
        )
      }
    }
    "custom" => {
      let data = @wire.object(value)
      if data.length() != 2 {
        return mismatch()
      }
      let tag = @wire.field(value, "constructor")
      let mut matched = false
      for variant in @wire.array(@wire.field(schema, "variants")) {
        if @wire.field(variant, "constructor") == tag {
          matched = true
          let schemas = @wire.array(@wire.field(variant, "arguments"))
          let values = @wire.array(@wire.field(value, "arguments"))
          if schemas.length() != values.length() {
            return mismatch()
          }
          for i, child in schemas {
            check_shape(
              child,
              values[i],
              path + ".arguments[" + (i + 1).to_string() + "]",
              budget,
            )
          }
        }
      }
      if !matched {
        mismatch()
      }
    }
    _ => mismatch()
  }
}

///|
/// Fields can display numeric drafts, but never silently discard an incompatible
/// JSON subtree. Runtime validation remains authoritative for actual input types.
pub fn form_error(profile : Json, document : String) -> String? {
  try {
    let inputs = @wire.array(@wire.field(profile, "inputs"))
    let values = @wire.array(@wire.parse(document))
    if inputs.length() != values.length() {
      raise @wire.Invalid(
        "invalid_shape", "The argument count does not match this function",
      )
    }
    let budget : Ref[Int32] = { val: 200, }
    for i, input in inputs {
      check_shape(
        @wire.field(input, "schema"),
        values[i],
        @wire.string(@wire.field(input, "label")),
        budget,
      )
    }
    None
  } catch {
    @wire.Invalid(_, message) => Some(message)
    _ => Some("The argument document is not valid JSON")
  }
}

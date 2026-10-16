///|
/// Form structure is a private projection of published ValueType JSON. Values
/// remain tagged throughout editing; the worker's shared codec validates runs.
fn tf(value : Json, name : String) -> Json raise {
  @wire.field(value, name)
}

///|
fn tt(value : Json, name : String) -> String raise {
  @wire.string(tf(value, name))
}

///|
fn tn(value : Json, key : String) -> String {
  tt(value, key) catch {
    _ => ""
  }
}

///|
pub fn typed_default(tpe : Json, definitions : Array[Json]) -> Json raise {
  typed_default_inner(tpe, definitions, 0, Ref(200))
}

///|
fn typed_default_inner(
  tpe : Json,
  definitions : Array[Json],
  depth : Int32,
  budget : Ref[Int32],
) -> Json raise {
  budget.val -= 1
  if depth > 24 || budget.val < 0 {
    raise @wire.Invalid("form_limit", "No finite default; use JSON inputs")
  }
  fn child(t : Json) -> Json raise {
    typed_default_inner(t, definitions, depth + 1, budget)
  }
  match tt(tpe, "type") {
    "int" => { "type": "int", "value": "0" }
    "bool" => { "type": "bool", "value": false }
    "unit" => { "type": "unit" }
    "decimal" => { "type": "decimal", "coefficient": "0", "exponent": 0 }
    "float64" => { "type": "float64", "bits": "0" }
    "text" => { "type": "text", "units": [] }
    "character" => { "type": "character", "units": [97] }
    "list" => { "type": "list", "items": [] }
    "tuple" =>
      { "type": "tuple", "items": @wire.array(tf(tpe, "items")).map(child) }
    "record" =>
      {
        "type": "record",
        "fields": @wire.array(tf(tpe, "fields")).map(f => {
          ({ "name": tt(f, "name"), "value": child(tf(f, "type")) } : Json)
        }),
      }
    "maybe" => { "type": "maybe", "case": "nothing" }
    "result" =>
      { "type": "result", "case": "ok", "value": child(tf(tpe, "ok")) }
    "custom" => {
      let name = tt(tpe, "name")
      let definition = definitions
        .iter()
        .find_first(d => tn(d, "name") == name)
        .unwrap_or(Json::null())
      let choices = @wire.array(tf(definition, "constructors")).copy()
      let sizes = choices.map(c => (c, @wire.array(tf(c, "inputs")).length()))
      sizes.sort_by((a, b) => a.1.compare(b.1))
      for (choice, _) in sizes {
        try {
          return {
            "type": "custom",
            "owner": name,
            "tag": tt(choice, "name"),
            "items": @wire.array(tf(choice, "inputs")).map(child),
          }
        } catch {
          _ => ()
        }
      }
      raise @wire.Invalid("form_default", "No finite default; use JSON inputs")
    }
    _ => raise @wire.Invalid("form_type", "Unsupported input type")
  }
}

///|
pub fn float64_text(value : Json) -> String {
  try {
    guard @protocol.Value::from_json(value) is Float64(bits) else { return "" }
    if bits == 9223372036854775808UL {
      "-0.0"
    } else {
      bits.reinterpret_as_double().to_string()
    }
  } catch {
    _ => tt(value, "bits") catch { _ => "" }
  }
}

///|
/// Unicode text controls are available only when SDK UTF-16 is representable.
/// Unit controls remain available for isolated surrogates and numeric drafts.
pub fn unicode_text(value : Json) -> String? {
  try {
    let units = match @protocol.Value::from_json(value) {
      Text(units) | Character(units) => units
      _ => return None
    }
    Some(@sdk.Text::from_units(units.map(n => n.to_uint16())).to_string())
  } catch {
    _ => None
  }
}

///|
fn typed_shape(
  tpe : Json,
  value : Json,
  definitions : Array[Json],
  path : String,
  depth : Int32,
  budget : Ref[Int32],
) -> Unit raise {
  budget.val -= 1
  if budget.val < 0 || depth > 32 {
    raise @wire.Invalid(
      "form_limit", "This input is too large or deep for fields. Use JSON inputs to edit it",
    )
  }
  fn mismatch() -> Unit raise {
    raise @wire.Invalid(
      "form_shape",
      path + ": tagged value does not match the input type",
    )
  }
  fn scalar(v : Json, numeric : Bool) -> Unit raise {
    match v {
      String(_) => ()
      Number(_, ..) if numeric => ()
      _ => mismatch()
    }
  }
  fn child(t : Json, v : Json, label : String) -> Unit raise {
    typed_shape(t, v, definitions, path + "." + label, depth + 1, budget)
  }
  let kind = tt(tpe, "type")
  if tt(value, "type") != kind {
    return mismatch()
  }
  let allowed = match kind {
    "int" | "bool" => ["type", "value"]
    "unit" => ["type"]
    "decimal" => ["type", "coefficient", "exponent"]
    "float64" => ["type", "bits"]
    "text" | "character" => ["type", "units"]
    "list" | "tuple" => ["type", "items"]
    "record" => ["type", "fields"]
    "custom" => ["type", "owner", "tag", "items"]
    "maybe" | "result" => ["type", "case", "value"]
    _ => return mismatch()
  }
  @wire.fields(value, allowed)
  match kind {
    "int" => scalar(tf(value, "value"), false)
    "bool" =>
      match tf(value, "value") {
        True | False => ()
        _ => mismatch()
      }
    "unit" => ()
    "decimal" => {
      scalar(tf(value, "coefficient"), false)
      scalar(tf(value, "exponent"), true)
    }
    "float64" => scalar(tf(value, "bits"), false)
    "text" | "character" =>
      for unit in @wire.array(tf(value, "units")) {
        budget.val -= 1
        if budget.val < 0 {
          raise @wire.Invalid(
            "form_limit", "This input is too large for fields. Use JSON inputs to edit it",
          )
        }
        scalar(unit, true)
      }
    "record" => {
      let types = @wire.array(tf(tpe, "fields"))
      let values = @wire.array(tf(value, "fields"))
      if types.length() != values.length() {
        return mismatch()
      }
      let seen : Map[String, Bool] = Map([])
      for v in values {
        @wire.fields(v, ["name", "value"])
        let name = tt(v, "name")
        if seen.contains(name) {
          return mismatch()
        }
        seen[name] = true
        guard types.iter().find_first(t => tn(t, "name") == name) is Some(t) else {
          return mismatch()
        }
        child(tf(t, "type"), tf(v, "value"), name)
      }
    }
    "list" =>
      for i, v in @wire.array(tf(value, "items")) {
        child(tf(tpe, "item"), v, i.to_string())
      }
    "tuple" | "custom" => {
      let types = if kind == "tuple" {
        @wire.array(tf(tpe, "items"))
      } else {
        let name = tt(tpe, "name")
        if tt(value, "owner") != name {
          return mismatch()
        }
        guard definitions.iter().find_first(d => tn(d, "name") == name)
          is Some(d) else {
          return mismatch()
        }
        guard @wire.array(tf(d, "constructors"))
          .iter()
          .find_first(c => tn(c, "name") == tn(value, "tag"))
          is Some(c) else {
          return mismatch()
        }
        @wire.array(tf(c, "inputs"))
      }
      let values = @wire.array(tf(value, "items"))
      if types.length() != values.length() {
        return mismatch()
      }
      for i, t in types {
        child(t, values[i], i.to_string())
      }
    }
    "maybe" =>
      match tt(value, "case") {
        "nothing" => if @wire.optional(value, "value") != None { mismatch() }
        "just" => child(tf(tpe, "item"), tf(value, "value"), "just")
        _ => mismatch()
      }
    "result" =>
      match tt(value, "case") {
        "ok" | "err" as tag => child(tf(tpe, tag), tf(value, "value"), tag)
        _ => mismatch()
      }
    _ => mismatch()
  }
}

///|
pub fn typed_form_error(profile : Json, document : String) -> String? {
  try {
    let inputs = @wire.array(tf(profile, "inputs"))
    let values = @wire.array(@wire.parse(document))
    let definitions = @wire.array(tf(profile, "definitions"))
    if inputs.length() != values.length() {
      raise @wire.Invalid(
        "form_shape", "The argument count does not match this function",
      )
    }
    let budget = Ref(200)
    for i, input in inputs {
      typed_shape(
        tf(input, "type"),
        values[i],
        definitions,
        tt(input, "label"),
        0,
        budget,
      )
    }
    None
  } catch {
    @wire.Invalid(_, message) => Some(message)
    _ => Some("The argument document is not valid tagged JSON")
  }
}

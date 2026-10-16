///|
/// This is field projection, not an exporter. No network or host imports.
pub(all) enum Destination {
  JSON
  OTLP
} derive(Eq, Show)

///|
pub extend Destination with Eq::{equal, not_equal}

///|
pub extend Destination with Show::{to_string, output}

///|
/// Reject is the default. Drop deliberately omits the entire field; Envelope
/// retains the complete native Ion value in a versioned binary wrapper.
pub(all) enum Policy {
  Reject
  Drop
  Envelope
} derive(Eq, Show)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Show::{to_string, output}

///|
pub(all) suberror ProjectionError {
  Invalid(String)
}

///|
pub(all) struct Issue {
  path : String
  reason : String
} derive(Eq, Show)

///|
pub extend Issue with Eq::{equal, not_equal}

///|
pub extend Issue with Show::{to_string, output}

///|
pub(all) struct Report {
  destination : Destination
  policy : Policy
  value : Json?
  encoded : Int32
  dropped : Int32
  lossy : Int32
  issues : Array[Issue]
}

///|
fn pointer(name : String) -> String {
  name.replace(old="~", new="~0").replace(old="/", new="~1")
}

///|
/// Validate all representability before writing. Never drop a list member and
/// accidentally shift positions. Limits fail independently of projection policy.
pub fn project(
  value : @ion.IonValue,
  destination : Destination,
  policy~ : Policy = Reject,
) -> Report raise {
  let nodes = Ref(0)
  let budget = Ref(8388608)
  fn charge(size : Int32) -> Unit raise {
    budget.val -= size
    if budget.val < 0 {
      raise Invalid("projection.limit")
    }
  }
  fn text_limit(text : String) -> Unit raise {
    if text.length() > 1048576 {
      raise Invalid("projection.limit")
    }
    charge(text.length() * 6)
  }
  fn validate(value : @ion.IonValue, depth : Int32) -> Unit raise {
    nodes.val += 1
    charge(16)
    if depth > 64 || nodes.val > 100000 || value.annotations().length() > 128 {
      raise Invalid("projection.limit")
    }
    for annotation in value.annotations() {
      if annotation.text() is Some(s) {
        text_limit(s)
      }
    }
    match value.kind() {
      String(s) => text_limit(s)
      Symbol(token) => if token.text() is Some(s) { text_limit(s) }
      Blob(b) | Clob(b) => {
        if b.length() > 1048576 {
          raise Invalid("projection.limit")
        }
        charge(b.length())
      }
      Int(n) => text_limit(n.to_string())
      Decimal(d) => text_limit(d.coefficient().to_string())
      List(a) | Sexp(a) =>
        for v in a {
          validate(v, depth + 1)
        }
      Struct(fields) =>
        for field in fields {
          if field.name.text() is Some(s) {
            text_limit(s)
          }
          validate(field.value, depth + 1)
        }
      _ => ()
    }
  }
  validate(value, 0)
  fn unsupported(v : @ion.IonValue, path : String) -> Issue? {
    fn problem(reason : String) -> Issue? {
      Some({ path, reason, })
    }
    if v.has_annotations() {
      return problem("annotations")
    }
    match v.kind() {
      Null(t) =>
        if destination is JSON && t is Null {
          None
        } else {
          problem("null_type")
        }
      Bool(_) | String(_) => None
      Int(n) => {
        let bound = if destination is JSON {
          9007199254740991L
        } else {
          9223372036854775807L
        }
        let lower = if destination is JSON {
          -9007199254740991L
        } else {
          -9223372036854775808L
        }
        if n.compare_int64(bound) > 0 || n.compare_int64(lower) < 0 {
          problem("integer_range")
        } else {
          None
        }
      }
      Float(n) =>
        if n.is_nan() || n.is_inf() || (n == 0.0 && 1.0 / n < 0.0) {
          problem("float_representation")
        } else {
          None
        }
      Blob(_) => if destination is OTLP { None } else { problem("binary") }
      List(a) => {
        for i, item in a {
          if unsupported(item, path + "/" + i.to_string()) is Some(issue) {
            return Some(issue)
          }
        }
        None
      }
      Struct(fields) => {
        let seen : Map[String, Bool] = Map([])
        for field in fields {
          guard field.name.text() is Some(name) else {
            return problem("symbol_field")
          }
          if seen.contains(name) {
            return problem("duplicate_field")
          }
          seen[name] = true
          if unsupported(field.value, path + "/" + pointer(name)) is Some(issue) {
            return Some(issue)
          }
        }
        None
      }
      Decimal(_) => problem("exact_decimal")
      Clob(_) => problem("clob")
      Timestamp(_) => problem("timestamp")
      Symbol(_) => problem("symbol")
      Sexp(_) => problem("sexp")
    }
  }
  fn encode(v : @ion.IonValue) -> Json {
    match v.kind() {
      Null(_) => Json::null()
      Bool(b) =>
        if destination is JSON {
          Json::boolean(b)
        } else {
          { "boolValue": b }
        }
      String(s) =>
        if destination is JSON {
          Json::string(s)
        } else {
          { "stringValue": s }
        }
      Int(n) =>
        if destination is JSON {
          Json::number(n.to_int64().to_double())
        } else {
          { "intValue": n.to_string() }
        }
      Float(n) =>
        if destination is JSON {
          Json::number(n)
        } else {
          { "doubleValue": n }
        }
      Blob(b) => { "bytesValue": @base64.encode(b[:]) }
      List(a) =>
        if destination is JSON {
          Json::array(a.map(encode))
        } else {
          { "arrayValue": { "values": a.map(encode) } }
        }
      Struct(fields) =>
        if destination is JSON {
          Json::object(
            Map::from_array(
              fields.map(f => (f.name.text().unwrap(), encode(f.value))),
            ),
          )
        } else {
          {
            "kvlistValue": {
              "values": fields.map(f => {
                (
                  { "key": f.name.text().unwrap(), "value": encode(f.value) } :
                  Json)
              }),
            },
          }
        }
      _ => abort("validated projection")
    }
  }
  let issue = unsupported(value, "")
  let base : Report = {
    destination,
    policy,
    value: None,
    encoded: 0,
    dropped: 0,
    lossy: 0,
    issues: issue.map(i => [i]).unwrap_or([]),
  }
  if issue is None {
    let projected = encode(value)
    if projected.stringify().length() > 8388608 {
      raise Invalid("projection.limit")
    }
    return { ..base, value: Some(projected), }
  }
  match policy {
    Reject =>
      raise Invalid(
        "projection.unsupported: " +
        issue.unwrap().path +
        ": " +
        issue.unwrap().reason,
      )
    Drop => { ..base, dropped: 1, lossy: 1, }
    Envelope => {
      let bytes = @binary.write_binary([value])
      if bytes.length() > 8388608 {
        raise Invalid("projection.limit")
      }
      let data = @base64.encode(bytes[:])
      let wrapper : Json = if destination is JSON {
        {
          "profile": "morphir-ion-field-v1",
          "encoding": "ion-binary-base64",
          "data": data,
        }
      } else {
        {
          "kvlistValue": {
            "values": [
              {
                "key": "profile",
                "value": { "stringValue": "morphir-ion-field-v1" },
              },
              { "key": "encoding", "value": { "stringValue": "ion-binary" } },
              { "key": "data", "value": { "bytesValue": data } },
            ],
          },
        }
      }
      if wrapper.stringify().length() > 8388608 {
        raise Invalid("projection.limit")
      }
      { ..base, value: Some(wrapper), encoded: 1, }
    }
  }
}

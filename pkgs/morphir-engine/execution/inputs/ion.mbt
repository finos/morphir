///|
/// A single Ion list contains arguments in parameter order. Typed values reuse
/// the published Ion codec; local values use an explicit JSON-compatible subset.
pub fn ion_arguments(
  profile : Json,
  source : String,
  typed : Bool,
) -> Json raise {
  let limit = if typed { 1048576 } else { 16 * 1024 * 1024 }
  if source.length() > limit || @utf8.encode(source).length() > limit {
    raise @wire.Invalid(
      "input_limit", "Ion arguments exceed the input byte limit",
    )
  }
  let list = @ion_text.read_ion(source[:])
  if list.has_annotations() {
    raise @wire.Invalid(
      "ion_arguments", "The argument list cannot have annotations",
    )
  }
  guard list.kind() is List(values) else {
    raise @wire.Invalid(
      "ion_arguments", "Ion arguments must be one list in parameter order",
    )
  }
  if typed {
    return Json::array(values.map(v => @protocol.Value::from_ion(v).to_json()))
  }
  let inputs = @wire.array(@wire.field(profile, "inputs"))
  if inputs.length() != values.length() {
    raise @wire.Invalid(
      "ion_arguments", "The argument count does not match this function",
    )
  }
  Json::array(
    values.mapi((i, v) => {
      local_integer_strings(
        @wire.field(inputs[i], "schema"),
        strict_ion_json(v, 0, Ref(100000)),
      )
    }),
  )
}

///|
fn strict_ion_json(
  value : @ion.IonValue,
  depth : Int32,
  budget : Ref[Int32],
) -> Json raise {
  budget.val -= 1
  if depth > 64 || budget.val < 0 {
    raise @wire.Invalid("ion_arguments", "Ion argument value limit exceeded")
  }
  if value.has_annotations() {
    raise @wire.Invalid(
      "ion_arguments", "Local Scheme inputs do not support Ion annotations; use Typed invocation for published Morphir values",
    )
  }
  match value.kind() {
    Int(n) => @wire.write_integer(n.to_string())
    Bool(b) => Json::boolean(b)
    String(s) => Json::string(s)
    Null(@ion.Null) => Json::null()
    Float(n) => @wire.write_float(n)
    Decimal(d) => {
      // Local Float semantics already use binary64. Retain the exact lexeme
      // until its declared input validator performs that explicit conversion.
      let number = @wire.number(
        d.coefficient().to_string() + "e" + d.exponent().to_string(),
      )
      if d.is_negative_zero() {
        @wire.number("-0.0")
      } else {
        number
      }
    }
    List(values) =>
      Json::array(values.map(v => strict_ion_json(v, depth + 1, budget)))
    Struct(fields) => {
      let result : Map[String, Json] = Map([])
      for field in fields {
        guard field.name.text() is Some(name) else {
          raise @wire.Invalid("ion_arguments", "Unknown Ion field symbol")
        }
        if result.contains(name) {
          raise @wire.Invalid("ion_arguments", "Duplicate Ion field: " + name)
        }
        result[name] = strict_ion_json(field.value, depth + 1, budget)
      }
      Json::object(result)
    }
    _ =>
      raise @wire.Invalid(
        "ion_arguments", "This Ion type has no lossless local argument projection; use a published typed value",
      )
  }
}

///|
/// Local Int controls use strings; native Ion Int values preserve their lexemes.
fn local_integer_strings(schema : Json, value : Json) -> Json raise {
  match @wire.string(@wire.field(schema, "kind")) {
    "int" =>
      match value {
        Number(_, ..) => Json::string(@wire.integer_text(value))
        _ => value
      }
    "record" => {
      let types = @wire.object(@wire.field(schema, "fields"))
      let values = @wire.object(value)
      @wire.obj(
        values
        .iter()
        .collect()
        .map(p => {
          (
            p.0,
            match types.get(p.0) {
              Some(t) => local_integer_strings(t, p.1)
              None => p.1
            },
          )
        }),
      )
    }
    "list" =>
      Json::array(
        @wire.array(value).map(v => {
          local_integer_strings(@wire.field(schema, "item"), v)
        }),
      )
    "tuple" => {
      let types = @wire.array(@wire.field(schema, "items"))
      Json::array(
        @wire.array(value).mapi((i, v) => {
          match types.get(i) {
            Some(t) => local_integer_strings(t, v)
            None => v
          }
        }),
      )
    }
    "custom" => {
      let tag = @wire.field(value, "constructor")
      let variant = @wire.array(@wire.field(schema, "variants"))
        .iter()
        .find_first(v => {
          (@wire.field(v, "constructor") catch { _ => Json::null() }) == tag
        })
      guard variant is Some(variant) else { return value }
      let types = @wire.array(@wire.field(variant, "arguments"))
      let fields = @wire.object(value).copy()
      fields["arguments"] = Json::array(
        @wire.array(@wire.field(value, "arguments")).mapi((i, v) => {
          match types.get(i) {
            Some(t) => local_integer_strings(t, v)
            None => v
          }
        }),
      )
      Json::object(fields)
    }
    _ => value
  }
}

///|
pub fn convert_inputs(
  profile : Json,
  document : String,
  from_ion : Bool,
  to_ion : Bool,
  typed : Bool,
) -> String raise {
  if from_ion == to_ion {
    return document
  }
  if from_ion {
    return ion_arguments(profile, document, typed).stringify(indent=2)
  }
  let values = @wire.array(@wire.parse(document))
  let list = if typed {
    @ion.IonValue::list(values.map(v => @protocol.Value::from_json(v).to_ion()))
  } else {
    // read_json keeps exact JSON number lexemes; generic down-conversion is never used.
    @ion_json.read_json(document[:])
  }
  @ion_text.write_ion_pretty(list)
}

///|
pub fn input_error(error : Error) -> String {
  match error {
    @wire.Invalid(_, message) => message
    @protocol.Invalid(code) => code
    @ion.Syntax(message)
    | @ion.DataModel(message)
    | @ion.Unsupported(message) => message
    _ => "Invalid evaluation inputs"
  }
}

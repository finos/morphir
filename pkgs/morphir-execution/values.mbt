///|
pub(all) suberror ExecutionError {
  Invalid(String)
} derive(Eq, Debug)

///|
pub extend ExecutionError with Eq::{equal, not_equal}

///|
pub extend ExecutionError with @debug.Debug::{to_repr}

///|
pub(all) enum Value {
  Integer(@bigint.BigInt)
  Boolean(Bool)
  Unit
  Decimal(@bigint.BigInt, Int32)
  Float64(UInt64)
  Text(Array[Int32])
  Character(Array[Int32])
  Sequence(Array[Value])
  Product(Array[Value])
  Record(Array[(String, Value)])
  Constructor(String, String, Array[Value])
  Optional(Value?)
  Outcome(Result[Value, Value])
  ModelError(String)
} derive(Eq, Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub(all) enum ValueType {
  Int
  Bool
  Unit
  Decimal
  Float64
  Text
  Character
  Sequence(ValueType)
  Product(Array[ValueType])
  Record(Array[(String, ValueType)])
  Custom(String)
  Optional(ValueType)
  Outcome(ValueType, ValueType)
  Function
} derive(Eq, Debug)

///|
pub extend ValueType with Eq::{equal, not_equal}

///|
pub extend ValueType with @debug.Debug::{to_repr}

///|
pub(all) struct Call {
  id : String
  entry : String
  arguments : Array[Value]
} derive(Eq, Debug)

///|
pub extend Call with Eq::{equal, not_equal}

///|
pub extend Call with @debug.Debug::{to_repr}

///|
pub(all) struct Suite {
  calls : Array[Call]
  extensions : Bytes?
} derive(Eq, Debug)

///|
pub extend Suite with Eq::{equal, not_equal}

///|
pub extend Suite with @debug.Debug::{to_repr}

///|
pub fn Suite::validate(self : Suite) -> Unit raise {
  if self.calls.is_empty() || self.calls.length() > 1000 {
    raise Invalid("execution.call_limit")
  }
  if self.extensions is Some(bytes) {
    if bytes.length() > 65536 {
      raise Invalid("execution.extension_limit")
    }
    ignore(@binary.read_binary_value(bytes[:]))
  }
  let seen = Map([])
  for call in self.calls {
    if call.id == "" ||
      call.id.length() > 128 ||
      call.entry == "" ||
      call.entry.length() > 1024 ||
      seen.contains(call.id) {
      raise Invalid("execution.invalid_call_identity")
    }
    seen[call.id] = true
    if call.arguments.length() > 64 {
      raise Invalid("execution.argument_limit")
    }
    let budget = Ref(100000)
    for argument in call.arguments {
      validate_value(argument, 0, budget)
    }
  }
}

///|
pub fn fields(
  value : @ion.IonValue,
  allowed : Array[String],
) -> Map[String, @ion.IonValue] raise {
  let result = Map([])
  guard value.kind() is Struct(items) else {
    raise Invalid("execution.expected_struct")
  }
  for item in items {
    let name = item.name().text().unwrap_or("")
    if !allowed.contains(name) || result.contains(name) {
      raise Invalid("execution.invalid_field: " + name)
    }
    result[name] = item.value()
  }
  result
}

///|
pub fn required(
  fields : Map[String, @ion.IonValue],
  name : String,
) -> @ion.IonValue raise {
  match fields.get(name) {
    Some(v) => v
    None => raise Invalid("execution.missing_field: " + name)
  }
}

///|
pub fn string(value : @ion.IonValue) -> String raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  match value.kind() {
    String(s) => s
    _ => raise Invalid("execution.expected_string")
  }
}

///|
fn list(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  match value.kind() {
    List(v) => v
    _ => raise Invalid("execution.expected_list")
  }
}

///|
pub fn record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::from_fields(fields.map(p => @ion.Field::new(p.0, p.1)))
}

///|
pub fn Suite::to_ion(self : Suite) -> @ion.IonValue raise {
  self.validate()
  let pairs = [
    ("profile", @ion.IonValue::string("morphir-invocations-v1")),
    (
      "calls",
      @ion.IonValue::list(
        self.calls.map(call => {
          record([
            ("id", @ion.IonValue::string(call.id)),
            ("entry", @ion.IonValue::string(call.entry)),
            (
              "arguments",
              @ion.IonValue::list(call.arguments.map(Value::to_ion)),
            ),
          ])
        }),
      ),
    ),
  ]
  if self.extensions is Some(_) {
    pairs.push(("extensions", self.extension_value()))
  }
  record(pairs)
}

///|
pub fn Suite::from_ion(value : @ion.IonValue) -> Suite raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  let f = fields(value, ["profile", "calls", "extensions"])
  if string(required(f, "profile")) != "morphir-invocations-v1" {
    raise Invalid("execution.unsupported_profile")
  }
  let suite = Suite::{
    extensions: f.get("extensions").map(v => @binary.write_binary_value(v)),
    calls: list(required(f, "calls")).map(v => {
      if v.has_annotations() {
        raise Invalid("execution.unexpected_annotation")
      }
      let f = fields(v, ["id", "entry", "arguments"])
      Call::{
        id: string(required(f, "id")),
        entry: string(required(f, "entry")),
        arguments: list(required(f, "arguments")).map(Value::from_ion),
      }
    }),
  }
  suite.validate()
  suite
}

///|
pub fn Suite::to_json(self : Suite) -> Json {
  let result : Json = {
    "profile": "morphir-invocations-v1",
    "calls": self.calls.map(call => {
      (
        {
          "id": call.id,
          "entry": call.entry,
          "arguments": call.arguments.map(Value::to_json),
        } : Json)
    }),
  }
  if self.extensions is Some(bytes) && result is Object(fields) {
    fields["extensions"] = {
      "format": "ion-binary",
      "bytes": bytes.to_array().map(b => b.to_int()),
    }
  }
  result
}

///|
pub fn Suite::from_json(value : Json) -> Suite raise {
  json_ion_suite(@text.read_ion(value.stringify()[:]))
}

///|
pub fn Suite::decode(bytes : Bytes, format : String) -> Suite raise {
  if bytes.length() > 1048576 {
    raise Invalid("execution.input_limit")
  }
  match format {
    "ion-binary" => Suite::from_ion(@binary.read_binary_value(bytes[:]))
    "ion-text" => Suite::from_ion(@text.read_ion(@utf8.decode(bytes[:])[:]))
    "json" => {
      let source = @utf8.decode(bytes[:])
      ignore(@json.parse(source))
      json_ion_suite(@text.read_ion(source[:]))
    }
    _ => raise Invalid("execution.unsupported_format")
  }
}

///|
pub fn Suite::encode(self : Suite, format : String) -> Bytes raise {
  let value = self.to_ion()
  match format {
    "ion-binary" => @binary.write_binary_value(value)
    "ion-text" => @utf8.encode(@text.write_ion(value))
    "json" => @utf8.encode(self.to_json().stringify())
    _ => raise Invalid("execution.unsupported_format")
  }
}

///|
// Reading the schema as Ion after JSON syntax validation preserves duplicate keys.
fn json_ion_suite(value : @ion.IonValue) -> Suite raise {
  let f = fields(value, ["profile", "calls", "extensions"])
  if string(required(f, "profile")) != "morphir-invocations-v1" {
    raise Invalid("execution.unsupported_profile")
  }
  let extensions = match f.get("extensions") {
    None => None
    Some(v) => Some(json_extension(v))
  }
  let suite = Suite::{
    extensions,
    calls: list(required(f, "calls")).map(call => {
      let f = fields(call, ["id", "entry", "arguments"])
      Call::{
        id: string(required(f, "id")),
        entry: string(required(f, "entry")),
        arguments: list(required(f, "arguments")).map(v => payload_value(v, 0)),
      }
    }),
  }
  suite.validate()
  suite
}

///|
fn json_extension(value : @ion.IonValue) -> Bytes raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  let f = fields(value, ["format", "bytes"])
  if string(required(f, "format")) != "ion-binary" {
    raise Invalid("execution.extension_format")
  }
  let bytes = Bytes::from_array(
    list(required(f, "bytes")).map(v => {
      let n = small_integer(v)
      if n < 0 || n > 255 {
        raise Invalid("execution.extension_byte")
      }
      n.to_byte()
    }),
  )
  ignore(@binary.read_binary_value(bytes[:]))
  bytes
}

///|
/// Extensions preserve Ion types and annotations outside semantic arguments.
pub fn Suite::extension_value(self : Suite) -> @ion.IonValue raise {
  match self.extensions {
    Some(bytes) => @binary.read_binary_value(bytes[:])
    None => @ion.IonValue::untyped_null()
  }
}

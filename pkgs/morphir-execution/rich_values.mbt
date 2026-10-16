///|
pub(all) struct ConstructorType {
  name : String
  inputs : Array[ValueType]
}

///|
pub(all) struct CustomType {
  name : String
  constructors : Array[ConstructorType]
}

///|
pub fn ValueType::name(self : ValueType) -> String {
  match self {
    Int => "int"
    Bool => "bool"
    Unit => "unit"
    Decimal => "decimal"
    Float64 => "float64"
    Text => "text"
    Character => "character"
    Sequence(_) => "list"
    Product(_) => "tuple"
    Record(_) => "record"
    Custom(_) => "custom"
    Optional(_) => "maybe"
    Outcome(_, _) => "result"
    Function => "function"
  }
}

///|
fn integer_string(source : String) -> @bigint.BigInt raise {
  let chars = source.to_array()
  let start = if source.has_prefix("-") { 1 } else { 0 }
  if chars.length() <= start ||
    chars.length() > 10000 ||
    !chars[start:].iter().all(c => c >= '0' && c <= '9') {
    raise Invalid("execution.invalid_integer")
  }
  @bigint.BigInt::from_string(source)
}

///|
fn small_integer(value : @ion.IonValue) -> Int32 raise {
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  match value.kind() {
    Int(n) => {
      if n.compare_int(-2147483648) < 0 || n.compare_int(2147483647) > 0 {
        raise Invalid("execution.integer_range")
      }
      n.to_int()
    }
    _ => raise Invalid("execution.expected_integer")
  }
}

///|
pub fn normalize_decimal(
  coefficient : @bigint.BigInt,
  exponent : Int32,
) -> (@bigint.BigInt, Int32) raise {
  if coefficient.to_string().length() > 10000 ||
    exponent < -10000 ||
    exponent > 10000 {
    raise Invalid("execution.decimal_limit")
  }
  if coefficient.is_zero() {
    return (coefficient, 0)
  }
  let ten = @bigint.BigInt::from_int(10)
  let mut n = coefficient
  let mut e = exponent
  while n / ten * ten == n {
    n = n / ten
    e += 1
  }
  if e < -32 || e > 10000 {
    raise Invalid("execution.decimal_precision")
  }
  (n, e)
}

///|
/// Scientific form accepted by the concrete SDK without loss of precision.
pub fn decimal_source(
  coefficient : @bigint.BigInt,
  exponent : Int32,
) -> String raise {
  let (n, e) = normalize_decimal(coefficient, exponent)
  if n.is_zero() {
    return "0"
  }
  let source = n.to_string()
  let negative = source.has_prefix("-")
  let digits = if negative { source[1:].to_owned() } else { source }
  (if negative { "-" } else { "" }) +
  digits[0:1].to_owned() +
  (if digits.length() > 1 { "." + digits[1:].to_owned() } else { "" }) +
  "e" +
  (e + digits.length() - 1).to_string()
}

///|
fn valid_model_error(code : String) -> Bool {
  [
    "sdk.division_by_zero", "sdk.invalid_number", "sdk.out_of_range", "sdk.invalid_comparison",
    "sdk.unrepresentable_text",
  ].contains(code)
}

///|
fn validate_value(
  value : Value,
  depth : Int32,
  budget : Ref[Int32],
) -> Unit raise {
  budget.val -= 1
  if depth > 64 || budget.val < 0 {
    raise Invalid("execution.value_limit")
  }
  fn child(v : Value) -> Unit raise {
    validate_value(v, depth + 1, budget)
  }
  match value {
    Integer(n) =>
      if n.to_string().length() > 10000 {
        raise Invalid("execution.integer_limit")
      }
    Decimal(n, e) => ignore(normalize_decimal(n, e))
    Text(units) | Character(units) => {
      budget.val -= units.length()
      if units.any(n => n < 0 || n > 65535) || budget.val < 0 {
        raise Invalid("execution.utf16_units")
      }
    }
    Sequence(items) | Product(items) =>
      for item in items {
        child(item)
      }
    Record(items) => {
      let seen = Map([])
      for (name, v) in items {
        if name == "" || name.length() > 1024 || seen.contains(name) {
          raise Invalid("execution.record_field: " + name)
        }
        seen[name] = true
        child(v)
      }
    }
    Constructor(owner, tag, items) => {
      if owner == "" ||
        tag == "" ||
        owner.length() > 1024 ||
        tag.length() > 1024 {
        raise Invalid("execution.constructor_identity")
      }
      for item in items {
        child(item)
      }
    }
    Optional(Some(v)) | Outcome(Ok(v)) | Outcome(Err(v)) => child(v)
    ModelError(code) =>
      if !valid_model_error(code) {
        raise Invalid("execution.model_error_code")
      }
    _ => ()
  }
}

///|
/// A declared type is authoritative, including empty containers and recursive ADTs.
pub fn validate_as(
  value : Value,
  expected : ValueType,
  definitions : Array[CustomType],
  output~ : Bool = false,
) -> Unit raise {
  validate_value(value, 0, Ref(100000))
  if value is ModelError(_) {
    if output {
      return
    }
    raise Invalid("execution.model_error_argument")
  }
  validate_typed(value, expected, definitions, "value", 0)
}

///|
fn validate_typed(
  value : Value,
  expected : ValueType,
  definitions : Array[CustomType],
  path : String,
  depth : Int32,
) -> Unit raise {
  if depth > 64 {
    raise Invalid("execution.value_limit: " + path)
  }
  fn child(v : Value, t : ValueType, name : String) -> Unit raise {
    validate_typed(v, t, definitions, path + "." + name, depth + 1)
  }
  match (value, expected) {
    (Integer(_), Int)
    | (Boolean(_), Bool)
    | (Unit, Unit)
    | (Decimal(_, _), Decimal)
    | (Float64(_), Float64)
    | (Text(_), Text)
    | (Character(_), Character) => ()
    (Sequence(items), Sequence(t)) =>
      for i, item in items {
        child(item, t, i.to_string())
      }
    (Product(items), Product(types)) => {
      if items.length() != types.length() {
        raise Invalid("execution.tuple_arity: " + path)
      }
      for i, item in items {
        child(item, types[i], i.to_string())
      }
    }
    (Record(items), Record(types)) => {
      let fields = Map(items)
      for (name, t) in types {
        guard fields.get(name) is Some(v) else {
          raise Invalid("execution.missing_record_field: " + path + "." + name)
        }
        child(v, t, name)
      }
      for (name, _) in items {
        if !types.any(p => p.0 == name) {
          raise Invalid("execution.extra_record_field: " + path + "." + name)
        }
      }
    }
    (Constructor(owner, tag, items), Custom(name)) => {
      if owner != name {
        raise Invalid("execution.constructor_owner: " + path)
      }
      guard definitions.filter(d => d.name == name).get(0) is Some(definition) else {
        raise Invalid("execution.unresolved_custom_type: " + name)
      }
      guard definition.constructors.filter(c => c.name == tag).get(0)
        is Some(variant) else {
        raise Invalid("execution.constructor_tag: " + path)
      }
      if variant.inputs.length() != items.length() {
        raise Invalid("execution.constructor_arity: " + path)
      }
      for i, item in items {
        child(item, variant.inputs[i], i.to_string())
      }
    }
    (Optional(None), Optional(_)) => ()
    (Optional(Some(v)), Optional(t)) => child(v, t, "just")
    (Outcome(Ok(v)), Outcome(ok, _)) => child(v, ok, "ok")
    (Outcome(Err(v)), Outcome(_, err)) => child(v, err, "err")
    (_, Function) => raise Invalid("execution.boundary_function: " + path)
    _ =>
      raise Invalid(
        "execution.wrong_type: " + path + ": expected " + expected.name(),
      )
  }
}

///|
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Integer(n) => { "type": "int", "value": n.to_string() }
    Boolean(b) => { "type": "bool", "value": b }
    Unit => { "type": "unit" }
    Decimal(n, e) =>
      { "type": "decimal", "coefficient": n.to_string(), "exponent": e }
    Float64(bits) => { "type": "float64", "bits": bits.to_string() }
    Text(units) => { "type": "text", "units": units }
    Character(units) => { "type": "character", "units": units }
    Sequence(items) => { "type": "list", "items": items.map(Value::to_json) }
    Product(items) => { "type": "tuple", "items": items.map(Value::to_json) }
    Record(items) =>
      {
        "type": "record",
        "fields": items.map(p => {
          ({ "name": p.0, "value": p.1.to_json() } : Json)
        }),
      }
    Constructor(owner, tag, items) =>
      {
        "type": "custom",
        "owner": owner,
        "tag": tag,
        "items": items.map(Value::to_json),
      }
    Optional(None) => { "type": "maybe", "case": "nothing" }
    Optional(Some(v)) =>
      { "type": "maybe", "case": "just", "value": v.to_json() }
    Outcome(Ok(v)) => { "type": "result", "case": "ok", "value": v.to_json() }
    Outcome(Err(v)) => { "type": "result", "case": "err", "value": v.to_json() }
    ModelError(code) => { "type": "model-error", "code": code }
  }
}

///|
fn payload_value(value : @ion.IonValue, depth : Int32) -> Value raise {
  if depth > 64 {
    raise Invalid("execution.value_limit")
  }
  if value.has_annotations() {
    raise Invalid("execution.unexpected_annotation")
  }
  let header = fields(value, [
    "type", "value", "coefficient", "exponent", "bits", "units", "items", "fields",
    "owner", "tag", "case", "code",
  ])
  let kind = string(required(header, "type"))
  let allowed = match kind {
    "unit" => ["type"]
    "int" | "bool" => ["type", "value"]
    "decimal" => ["type", "coefficient", "exponent"]
    "float64" => ["type", "bits"]
    "text" | "character" => ["type", "units"]
    "list" | "tuple" => ["type", "items"]
    "record" => ["type", "fields"]
    "custom" => ["type", "owner", "tag", "items"]
    "maybe" =>
      if string(required(header, "case")) == "nothing" {
        ["type", "case"]
      } else {
        ["type", "case", "value"]
      }
    "result" => ["type", "case", "value"]
    "model-error" => ["type", "code"]
    _ => raise Invalid("execution.unsupported_value")
  }
  let f = fields(value, allowed)
  if f.length() != allowed.length() {
    raise Invalid("execution.invalid_json_value")
  }
  fn child(v : @ion.IonValue) -> Value raise {
    payload_value(v, depth + 1)
  }
  let result = match kind {
    "int" => Integer(integer_string(string(required(f, "value"))))
    "bool" =>
      match required(f, "value").kind() {
        Bool(b) => {
          if required(f, "value").has_annotations() {
            raise Invalid("execution.unexpected_annotation")
          }
          Boolean(b)
        }
        _ => raise Invalid("execution.expected_bool")
      }
    "unit" => Unit
    "decimal" =>
      Decimal(
        integer_string(string(required(f, "coefficient"))),
        small_integer(required(f, "exponent")),
      )
    "float64" => {
      let bits = integer_string(string(required(f, "bits")))
      if bits.compare_int(0) < 0 ||
        bits.compare_uint64(18446744073709551615UL) > 0 {
        raise Invalid("execution.float_bits")
      }
      Float64(bits.to_uint64())
    }
    "text" | "character" => {
      let units = list(required(f, "units")).map(small_integer)
      if kind == "text" {
        Text(units)
      } else {
        Character(units)
      }
    }
    "list" | "tuple" => {
      let items = list(required(f, "items")).map(child)
      if kind == "list" {
        Sequence(items)
      } else {
        Product(items)
      }
    }
    "record" =>
      Record(
        list(required(f, "fields")).map(v => {
          if v.has_annotations() {
            raise Invalid("execution.unexpected_annotation")
          }
          let f = fields(v, ["name", "value"])
          (string(required(f, "name")), child(required(f, "value")))
        }),
      )
    "custom" =>
      Constructor(
        string(required(f, "owner")),
        string(required(f, "tag")),
        list(required(f, "items")).map(child),
      )
    "maybe" =>
      match string(required(f, "case")) {
        "nothing" => Optional(None)
        "just" => Optional(Some(child(required(f, "value"))))
        _ => raise Invalid("execution.maybe_case")
      }
    "result" =>
      match string(required(f, "case")) {
        "ok" => Outcome(Ok(child(required(f, "value"))))
        "err" => Outcome(Err(child(required(f, "value"))))
        _ => raise Invalid("execution.result_case")
      }
    "model-error" => ModelError(string(required(f, "code")))
    _ => raise Invalid("execution.unsupported_value")
  }
  result
}

///|
pub fn Value::from_json(value : Json) -> Value raise {
  let result = payload_value(@text.read_ion(value.stringify()[:]), 0)
  validate_value(result, 0, Ref(100000))
  result
}

///|
pub fn Value::to_ion(self : Value) -> @ion.IonValue {
  match self {
    Integer(n) => @ion.IonValue::new(@ion.Int(n))
    Boolean(b) => @ion.IonValue::bool(b)
    Unit =>
      @ion.IonValue::untyped_null().with_annotation(
        @ion.SymbolToken::new("morphir_unit"),
      )
    Decimal(n, e) => @ion.IonValue::decimal(@ion.Decimal::new(n, e))
    _ =>
      value_payload(self).with_annotation(
        @ion.SymbolToken::new("morphir_value"),
      )
  }
}

///|
pub fn Value::from_ion(value : @ion.IonValue) -> Value raise {
  let annotations = value.annotations()
  let result = if annotations.is_empty() {
    match value.kind() {
      Int(n) => Integer(n)
      Bool(b) => Boolean(b)
      Decimal(d) => Decimal(d.coefficient(), d.exponent())
      _ => raise Invalid("execution.unsupported_value")
    }
  } else if annotations.length() == 1 &&
    annotations[0].text() == Some("morphir_unit") &&
    value.kind() is Null(@ion.Null) {
    Unit
  } else if annotations.length() == 1 &&
    annotations[0].text() == Some("morphir_value") {
    payload_value(@ion.IonValue::new(value.kind()), 0)
  } else {
    raise Invalid("execution.value_annotation")
  }
  validate_value(result, 0, Ref(100000))
  result
}

///|
fn value_payload(value : Value) -> @ion.IonValue {
  fn text(s : String) -> @ion.IonValue {
    @ion.IonValue::string(s)
  }
  fn items(vs : Array[Value]) -> @ion.IonValue {
    @ion.IonValue::list(vs.map(value_payload))
  }
  let pairs = match value {
    Integer(n) => [("type", text("int")), ("value", text(n.to_string()))]
    Boolean(b) => [("type", text("bool")), ("value", @ion.IonValue::bool(b))]
    Unit => [("type", text("unit"))]
    Decimal(n, e) =>
      [
        ("type", text("decimal")),
        ("coefficient", text(n.to_string())),
        ("exponent", @ion.IonValue::int(e)),
      ]
    Float64(bits) =>
      [("type", text("float64")), ("bits", text(bits.to_string()))]
    Text(units) | Character(units) =>
      [
        ("type", text(if value is Text(_) { "text" } else { "character" })),
        ("units", @ion.IonValue::list(units.map(@ion.IonValue::int))),
      ]
    Sequence(vs) | Product(vs) =>
      [
        ("type", text(if value is Sequence(_) { "list" } else { "tuple" })),
        ("items", items(vs)),
      ]
    Record(fields) =>
      [
        ("type", text("record")),
        (
          "fields",
          @ion.IonValue::list(
            fields.map(p => {
              record([("name", text(p.0)), ("value", value_payload(p.1))])
            }),
          ),
        ),
      ]
    Constructor(owner, tag, vs) =>
      [
        ("type", text("custom")),
        ("owner", text(owner)),
        ("tag", text(tag)),
        ("items", items(vs)),
      ]
    Optional(None) => [("type", text("maybe")), ("case", text("nothing"))]
    Optional(Some(v)) =>
      [
        ("type", text("maybe")),
        ("case", text("just")),
        ("value", value_payload(v)),
      ]
    Outcome(Ok(v)) | Outcome(Err(v)) =>
      [
        ("type", text("result")),
        ("case", text(if value is Outcome(Ok(_)) { "ok" } else { "err" })),
        ("value", value_payload(v)),
      ]
    ModelError(code) => [("type", text("model-error")), ("code", text(code))]
  }
  record(pairs)
}

///|
pub fn ValueType::to_json(self : ValueType) -> Json {
  match self {
    Sequence(t) | Optional(t) => { "type": self.name(), "item": t.to_json() }
    Product(types) =>
      { "type": "tuple", "items": types.map(ValueType::to_json) }
    Record(fields) =>
      {
        "type": "record",
        "fields": fields.map(p => {
          ({ "name": p.0, "type": p.1.to_json() } : Json)
        }),
      }
    Custom(name) => { "type": "custom", "name": name }
    Outcome(ok, err) =>
      { "type": "result", "ok": ok.to_json(), "err": err.to_json() }
    _ => { "type": self.name() }
  }
}

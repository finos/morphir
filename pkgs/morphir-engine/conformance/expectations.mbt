///|
pub(all) struct ExpectedCase {
  call : @protocol.Call
  expected : @protocol.Value
}

///|
pub(all) struct Expectations {
  version : String
  provenance : String
  cases : Array[ExpectedCase]
}

///|
fn items(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  guard value.kind() is List(values) && !value.has_annotations() else {
    raise @protocol.Invalid("conformance.expected_list")
  }
  values
}

///|
pub fn Expectations::suite(self : Expectations) -> @protocol.Suite {
  { calls: self.cases.map(c => c.call), extensions: None, }
}

///|
pub fn Expectations::validate(self : Expectations) -> Unit raise {
  if self.version == "" ||
    self.version.length() > 128 ||
    self.provenance == "" ||
    self.provenance.length() > 4096 {
    raise @protocol.Invalid("conformance.missing_provenance")
  }
  self.suite().validate()
  for case in self.cases {
    // Reuse the bounded execution value validation for expected output values.
    @protocol.Suite::{
      calls: [
        {
          id: case.call.id,
          entry: case.call.entry,
          arguments: [case.expected],
        },
      ],
      extensions: None,
    }.validate()
  }
}

///|
pub fn Expectations::to_ion(self : Expectations) -> @ion.IonValue raise {
  self.validate()
  @protocol.record([
    ("profile", @ion.IonValue::string("morphir-conformance-v1")),
    ("version", @ion.IonValue::string(self.version)),
    ("provenance", @ion.IonValue::string(self.provenance)),
    (
      "cases",
      @ion.IonValue::list(
        self.cases.map(c => {
          @protocol.record([
            ("id", @ion.IonValue::string(c.call.id)),
            ("entry", @ion.IonValue::string(c.call.entry)),
            (
              "arguments",
              @ion.IonValue::list(c.call.arguments.map(v => v.to_ion())),
            ),
            ("expected", c.expected.to_ion()),
          ])
        }),
      ),
    ),
  ])
}

///|
pub fn Expectations::from_ion(value : @ion.IonValue) -> Expectations raise {
  decode_document(value, false)
}

///|
fn decode_document(value : @ion.IonValue, json : Bool) -> Expectations raise {
  fn semantic(v : @ion.IonValue) -> @protocol.Value raise {
    if json {
      if v.has_annotations() {
        raise @protocol.Invalid("conformance.annotation")
      }
      @protocol.Value::from_ion(
        v.with_annotation(@ion.SymbolToken::new("morphir_value")),
      )
    } else {
      @protocol.Value::from_ion(v)
    }
  }
  if value.has_annotations() {
    raise @protocol.Invalid("conformance.annotation")
  }
  let f = @protocol.fields(value, ["profile", "version", "provenance", "cases"])
  if @protocol.string(@protocol.required(f, "profile")) !=
    "morphir-conformance-v1" {
    raise @protocol.Invalid("conformance.profile")
  }
  let result = Expectations::{
    version: @protocol.string(@protocol.required(f, "version")),
    provenance: @protocol.string(@protocol.required(f, "provenance")),
    cases: items(@protocol.required(f, "cases")).map(value => {
      if value.has_annotations() {
        raise @protocol.Invalid("conformance.annotation")
      }
      let f = @protocol.fields(value, ["id", "entry", "arguments", "expected"])
      {
        call: {
          id: @protocol.string(@protocol.required(f, "id")),
          entry: @protocol.string(@protocol.required(f, "entry")),
          arguments: items(@protocol.required(f, "arguments")).map(semantic),
        },
        expected: semantic(@protocol.required(f, "expected")),
      }
    }),
  }
  result.validate()
  result
}

///|
pub fn Expectations::decode(
  bytes : Bytes,
  format~ : String = "ion-text",
) -> Expectations raise {
  if bytes.length() > 8388608 {
    raise @protocol.Invalid("conformance.input_limit")
  }
  if format == "json" {
    // Validate JSON syntax, then parse the original lexemes with Ion. The JSON
    // AST is deliberately unused so no semantic number passes through Double.
    ignore(@json.parse(@utf8.decode(bytes)))
    return decode_document(@text.read_ion(@utf8.decode(bytes)[:]), true)
  }
  let value = match format {
    "ion-text" => @text.read_ion(@utf8.decode(bytes)[:])
    "ion-binary" => @binary.read_binary_value(bytes[:])
    _ => raise @protocol.Invalid("conformance.format")
  }
  Expectations::from_ion(value)
}

///|
pub fn Expectations::to_json(self : Expectations) -> Json raise {
  self.validate()
  {
    "profile": "morphir-conformance-v1",
    "version": self.version,
    "provenance": self.provenance,
    "cases": self.cases.map(c => {
      (
        {
          "id": c.call.id,
          "entry": c.call.entry,
          "arguments": c.call.arguments.map(v => v.to_json()),
          "expected": c.expected.to_json(),
        } : Json)
    }),
  }
}

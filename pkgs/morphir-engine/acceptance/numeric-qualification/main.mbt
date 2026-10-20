///|
/// Pure test bridge: Node owns files and processes; production codecs own Ion
/// and execution values. This fixture is never included in an installed package.
fn field(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard value.kind() is Struct(fields) &&
    fields.filter(f => f.name().text() == Some(name)) is [found] else {
    fail("Expected exactly one Ion field: " + name)
  }
  found.value()
}

///|
fn text(value : @ion.IonValue) -> String raise {
  guard value.kind() is String(value) else { fail("Expected Ion string") }
  value
}

///|
fn items(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  guard value.kind() is List(values) else { fail("Expected Ion list") }
  values
}

///|
fn binary(request : Json) -> Bytes raise {
  if @wire.optional(request, "base64") is Some(encoded) {
    guard @wire.optional(request, "bytes") is None else {
      fail("Ambiguous binary encoding")
    }
    return @base64.decode(@wire.string(encoded)[:])
  }
  Bytes::from_array(
    @wire.array(@wire.field(request, "bytes")).map(value => {
      guard value is Number(n, ..) && n >= 0.0 && n <= 255.0 && n.floor() == n else {
        fail("Expected byte")
      }
      n.to_int().to_byte()
    }),
  )
}

///|
fn document(request : Json) -> @ion.IonValue raise {
  if @wire.optional(request, "bytes") is Some(_) ||
    @wire.optional(request, "base64") is Some(_) {
    @ion_binary.read_binary_value(binary(request)[:])
  } else {
    @ion_text.read_ion(@wire.string(@wire.field(request, "source"))[:])
  }
}

///|
fn unit(request : Json) -> @data.IRUnit raise {
  @data.Registry::new().decode(@wire.string(@wire.field(request, "format")), {
    unit_id: "Main",
    content: if @wire.optional(request, "bytes") is Some(_) ||
      @wire.optional(request, "base64") is Some(_) {
      @data.Binary(binary(request))
    } else {
      @data.Text(@wire.string(@wire.field(request, "source")))
    },
  })
}

///|
fn encoded(value : @ion.IonValue) -> Json raise {
  let bytes = @ion_binary.write_binary_value(value)
  let source = @ion_text.write_ion_pretty(value)
  guard @ion_binary.read_binary_value(bytes[:]).equals(value) &&
    @ion_text.read_ion(source[:]).equals(value) else {
    fail("Ion text/binary replay changed the value")
  }
  { "bytes": bytes.to_array().map(b => b.to_int()), "source": source }
}

///|
fn outcome(value : @ion.IonValue) -> Json raise {
  if value.kind() is Null(_) {
    Json::null()
  } else {
    @protocol.Value::from_ion(value).to_json()
  }
}

///|
fn receipt_calls(value : @ion.IonValue) -> Json raise {
  Json::array(
    items(field(value, "calls")).map(call => {
      (
        {
          "id": text(field(call, "id")),
          "actual": outcome(field(call, "actual")),
          "expected": outcome(field(call, "expected")),
        } : Json)
    }),
  )
}

///|
fn handle(source : String) -> Json raise {
  let request = @wire.parse_bounded(
    source,
    max_depth=512,
    max_string_units=8388608,
  )
  match @wire.string(@wire.field(request, "op")) {
    "inspect" | "augment" as operation => {
      let original = unit(request)
      let value = if operation == "augment" {
        guard !original.metadata.is_empty() &&
          original.metadata[0].data.kind() is Struct(fields) else {
          fail("Expected owned metadata to enrich")
        }
        let metadata = original.metadata.copy()
        metadata[0] = {
          ..metadata[0],
          data: @ion.IonValue::from_fields(
            fields +
            [
              @ion.Field::new(
                "future_numeric_contract",
                @ion_text.read_ion(
                  "future_numeric::{amount:12.340d0,blob:{{/wCA}},nil:null.int}"[:],
                ),
              ),
            ],
          ),
        }
        @data.IRUnit::{ ..original, metadata, }
      } else {
        original
      }
      let registry = @data.Registry::new()
      guard registry.encode("ion-text", value) is Text(ion_text) &&
        registry.encode("ion-binary", value) is Binary(ion_binary) else {
        fail("Expected rich checkpoint encodings")
      }
      let restored = registry.decode("ion-binary", {
        unit_id: "Main",
        content: Binary(ion_binary),
      })
      guard restored.distribution == value.distribution &&
        restored.metadata.length() == value.metadata.length() else {
        fail("Checkpoint replay changed its semantic model or owners")
      }
      for (a, b) in value.metadata.zip(restored.metadata) {
        guard a.node_id == b.node_id && a.data.equals(b.data) else {
          fail("Checkpoint replay changed rich metadata")
        }
      }
      let projection = try {
        ignore(registry.encode("morphir-json", value))
        ({ "accepted": true } : Json)
      } catch {
        @data.Invalid(code, _) => { "accepted": false, "code": code }
      }
      {
        "unitId": value.id,
        "source": ion_text,
        "bytes": ion_binary.to_array().map(b => b.to_int()),
        "metadata": value.metadata.map(m => {
          ({ "owner": m.node_id, "source": @ion_text.write_ion(m.data) } : Json)
        }),
        "jsonProjection": projection,
      }
    }
    "scheme" => {
      let suite = @protocol.Suite::from_json(@wire.field(request, "suite"))
      let values = @execution.plan_scheme(unit(request), suite).evaluate()
      { "values": values.map(@protocol.Value::to_json) }
    }
    "symbols" => {
      let symbols = document(request)
      guard text(field(symbols, "profile")) ==
        "morphir-moonbit-symbols-2026-10-17" else {
        fail("Unexpected generated symbol contract")
      }
      {
        "unitId": text(field(symbols, "unit_id")),
        "metadata": @ion_text.write_ion(field(symbols, "metadata")),
        "provenance": @ion_text.write_ion(field(symbols, "source_provenance")),
        "symbols": items(field(symbols, "symbols")).map(symbol => {
          guard field(symbol, "public").kind() is Bool(public) else {
            fail("Expected generated visibility")
          }
          (
            {
              "fqname": text(field(symbol, "fqname")),
              "function": text(field(symbol, "generated_name")),
              "public": public,
            } : Json)
        }),
      }
    }
    "conformance" => {
      let receipt = document(request)
      guard text(field(receipt, "profile")) == "morphir-conformance-report-v1" &&
        field(receipt, "successful").kind() is Bool(successful) else {
        fail("Expected conformance receipt")
      }
      {
        "successful": successful,
        "execution": receipt_calls(field(receipt, "execution")),
        "coverage": items(field(receipt, "coverage")).map(lane => {
          (
            {
              "provider": text(field(lane, "provider")),
              "calls": receipt_calls(lane),
            } : Json)
        }),
        "roundtrip": encoded(receipt),
      }
    }
    "cases" => {
      let rows = @wire.array(@wire.field(request, "rows"))
      guard !rows.is_empty() else {
        fail("Expected independent conformance rows")
      }
      encoded(
        @ion.IonValue::from_fields([
          @ion.Field::new(
            "profile",
            @ion.IonValue::string("morphir-conformance-v1"),
          ),
          @ion.Field::new(
            "version",
            @ion.IonValue::string("installed-numeric-1"),
          ),
          @ion.Field::new(
            "provenance",
            @ion.IonValue::string(
              "Authored scalar, IEEE and Decimal references; no evaluator or generator computes expectations",
            ),
          ),
          @ion.Field::new(
            "cases",
            @ion.IonValue::list(
              rows.map(row => {
                @ion.IonValue::from_fields([
                  @ion.Field::new(
                    "id",
                    @ion.IonValue::string(@wire.string(@wire.field(row, "id"))),
                  ),
                  @ion.Field::new(
                    "entry",
                    @ion.IonValue::string(
                      @wire.string(@wire.field(row, "entry")),
                    ),
                  ),
                  @ion.Field::new(
                    "arguments",
                    @ion.IonValue::list(
                      @wire.array(@wire.field(row, "arguments")).map(value => {
                        @protocol.Value::from_json(value).to_ion()
                      }),
                    ),
                  ),
                  @ion.Field::new(
                    "expected",
                    @protocol.Value::from_json(@wire.field(row, "expected")).to_ion(),
                  ),
                ])
              }),
            ),
          ),
        ]),
      )
    }
    _ => fail("Unknown numeric qualification fixture operation")
  }
}

///|
extern "js" fn expose(handler : (String) -> String) =
  #| handler => { globalThis.morphirNumericQualificationFixture = handler; }

///|
fn main {
  expose(source => {
    let response = ({ "ok": true, "value": handle(source) } : Json) catch {
      error => { "ok": false, "error": error.to_string() }
    }
    response.stringify()
  })
}

///|
fn scan_budget(depth~ : Int32 = 128, nodes~ : Int32 = 100) -> ModelBudget {
  ModelBudget::new({ encoded: 4096, decoded: 4096, depth, nodes, })
}

///|
test "binary admission counts value depth from one and excludes annotation wrappers" {
  let list = b"\xe0\x01\x00\xea\xb1\x20"
  let exact = scan_budget(depth=2, nodes=2)
  exact.inspect_binary(list)
  assert_eq(exact.nodes, 2)
  assert_eq(
    try {
      scan_budget(depth=1).inspect_binary(list)
      "accepted"
    } catch {
      Refused(reason) => reason
      _ => "other"
    },
    "depth_limit",
  )
  assert_eq(
    try {
      scan_budget(nodes=1).inspect_binary(list)
      "accepted"
    } catch {
      Refused(reason) => reason
      _ => "other"
    },
    "node_limit",
  )
  let annotated = b"\xe0\x01\x00\xea\xe3\x81\x84\x0f"
  let exact = scan_budget(depth=1, nodes=1)
  exact.inspect_binary(annotated)
  ignore(read_model_binary(annotated, exact.limits))
  assert_eq(exact.nodes, 1)
}

///|
test "preflight bounds truncated and overflowing lengths and validates scalar bodies with Ion" {
  for
    bytes in [
      b"\xe0\x01\x00\xea\xbe\x7f\x7f\x7f\x7f\xff", b"\xe0\x01\x00\xea\xb5\x20", b"\xe0\x01\x00\xea\xe3\x85\x84\x20",
      b"\xe0\x01\x00\xea\xd1\x81",
    ] {
    let mut refused = false
    scan_budget().inspect_binary(bytes) catch {
      _ => refused = true
    }
    assert_true(refused)
  }
  let invalid_scalar = b"\xe0\x01\x00\xea\x42\x00\x00"
  let budget = scan_budget()
  budget.inspect_binary(invalid_scalar)
  let mut refused = false
  ignore(read_model_binary(invalid_scalar, budget.limits)) catch {
    _ => refused = true
  }
  assert_true(refused)
}

///|
test "resolved aliases cannot bypass shared import refusal" {
  let aliases = @ion.IonValue::from_fields([
    @ion.Field::new(
      "symbols",
      @ion.IonValue::list([
        @ion.IonValue::string("$ion_symbol_table"),
        @ion.IonValue::string("imports"),
      ]),
    ),
  ]).with_annotation(@ion.SymbolToken::new("$ion_symbol_table"))
  let imported = @ion.IonValue::from_fields([
    @ion.Field::from_token(
      @ion.SymbolToken::from_sid(11),
      @ion.IonValue::list([
        @ion.IonValue::from_fields([
          @ion.Field::new("name", @ion.IonValue::string("unavailable")),
          @ion.Field::new("max_id", @ion.IonValue::int(2147483647)),
        ]),
      ]),
    ),
  ]).with_annotation(@ion.SymbolToken::from_sid(10))
  let symbols = @ion.SymbolTable::system()
  symbols.reserve(2)
  let bytes = Buffer()
  bytes.write_bytes(@ion_binary.write_binary([aliases])[:])
  bytes.write_bytes(@ion_binary.encode_value(imported, symbols)[:])
  bytes.write_byte(b'\x0f')
  let bytes = bytes.to_bytes()
  let budget = scan_budget()
  budget.inspect_binary(bytes)
  assert_eq(
    try {
      ignore(read_model_binary(bytes, budget.limits))
      "accepted"
    } catch {
      Refused(reason) => reason
      _ => "other"
    },
    "unsupported_shared_symbols",
  )
}

///|
test "JSON payload depth and aggregate nodes use the same MEP convention as Ion" {
  let budget = scan_budget(depth=2, nodes=4)
  ignore(budget.read_json(b"[0]"))
  ignore(budget.read_json(b"[1]"))
  assert_eq(budget.nodes, 4)
  assert_eq(
    try {
      ignore(budget.read_json(b"null"))
      "accepted"
    } catch {
      Refused(reason) => reason
      _ => "other"
    },
    "node_limit",
  )
  let mut refused = false
  ignore(scan_budget(depth=1).read_json(b"[0]")) catch {
    _ => refused = true
  }
  assert_true(refused)
}

///|
test "base64 decoding refuses whitespace and noncanonical padding bits" {
  for content in ["AB==", "AA=", " AA==", "AA==\n"] {
    let payload : Json = {
      "codec": "morphir-json",
      "layout": "single-document",
      "decodedByteLength": 1,
      "sha256": model_sha256(b"\x00"),
      "content": content,
    }
    let mut refused = false
    ignore(scan_budget().decode(payload)) catch {
      _ => refused = true
    }
    assert_true(refused)
  }
}

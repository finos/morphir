///|
/// Header recognition is independent of typed inspection and supported formats.
test "projection header recognition preserves historical aliases and future releases" {
  for
    (bytes, expected) in [
      (b"{\"formatVersion\":2,\"distribution\":null}", "2.0.0"),
      (b"{\"formatVersion\":99,\"distribution\":false}", "99.0.0"),
      (b"{\"formatVersion\":4294967295}", "4294967295.0.0"),
      (b"{\"formatVersion\":\"99.2.7\"}", "99.2.7"),
    ] {
    let header = @data.recognize_projection_header(bytes, {
      max_bytes: 256,
      max_depth: 8,
      max_values: 16,
    })
    assert_eq(header.to_release_string(), expected)
  }
}

///|
fn projection_header_error(bytes : Bytes, limits : @data.Limits) -> String {
  try {
    ignore(@data.recognize_projection_header(bytes, limits))
    "accepted"
  } catch {
    @data.Invalid(code, _) => code
  }
}

///|
test "projection header rejects a BOM instead of recognizing modified JSON bytes" {
  assert_eq(
    projection_header_error(b"\xef\xbb\xbf{\"formatVersion\":4}", {
      max_bytes: 64,
      max_depth: 1,
      max_values: 2,
    }),
    "invalid_json",
  )
}

///|
test "projection header rejects noncanonical versions and malformed whole documents" {
  let limits : @data.Limits = { max_bytes: 1024, max_depth: 8, max_values: 32, }
  for
    (bytes, code) in [
      (b"{\"formatVersion\":4.0}", "invalid_format_version_type"),
      (b"{\"formatVersion\":4e0}", "invalid_format_version_type"),
      (b"{\"formatVersion\":-1}", "invalid_format_version_type"),
      (b"{\"formatVersion\":-0}", "invalid_format_version_type"),
      (b"{\"formatVersion\":0}", "invalid_format_version_syntax"),
      (b"{\"formatVersion\":4294967296}", "format_version_out_of_range"),
      (b"{\"formatVersion\":\"1.0.0\"}", "invalid_format_version_syntax"),
      (b"{\"formatVersion\":\"2.0.0\"}", "invalid_format_version_syntax"),
      (b"{\"formatVersion\":\"3.01.0\"}", "invalid_format_version_syntax"),
      (b"{\"formatVersion\":\"4.0.0+build\"}", "invalid_format_version_syntax"),
      (
        b"{\"formatVersion\":\"99.4294967296.0\"}", "format_version_out_of_range",
      ),
      (b"{\"formatVersion\":true}", "invalid_format_version_type"),
      (b"{\"formatVersion\":null}", "invalid_format_version_type"),
      (b"{\"formatVersion\":[4]}", "invalid_format_version_type"),
      (b"{}", "missing_format_version"),
      (b"{\"formatVersion\":4,\"formatVersion\":4}", "duplicate_format_version"),
      (
        b"{\"formatVersion\":4,\"\\u0066ormatVersion\":4}", "duplicate_format_version",
      ),
      (
        b"{\"formatVersion\":4,\"later\":{\"a\":1,\"\\u0061\":2}}", "duplicate_member",
      ),
      (b"{\"formatVersion\":4} {}", "invalid_json"),
      (b"{\"formatVersion\":4,\"later\":}", "invalid_json"),
      (b"{\"formatVersion\":04}", "invalid_json"),
      (b"{\"formatVersion\":4,\"later\":\"\xff\"}", "data.invalid_utf8"),
    ] {
    assert_eq(projection_header_error(bytes, limits), code)
  }
}

///|
test "projection header enforces caller bytes limits before UTF8 and parser limits" {
  let exact = b"{\"formatVersion\":4}"
  let limits : @data.Limits = {
    max_bytes: exact.length(),
    max_depth: 1,
    max_values: 2,
  }
  assert_eq(
    @data.recognize_projection_header(exact, limits).to_release_string(),
    "4.0.0",
  )
  assert_eq(
    projection_header_error(exact, { ..limits, max_bytes: exact.length() - 1, }),
    "data.byte_limit",
  )
  assert_eq(
    projection_header_error(b"\xff\xff", { ..limits, max_bytes: 1, }),
    "data.byte_limit",
  )
  assert_eq(projection_header_error(b"\xff", limits), "data.invalid_utf8")
  for
    invalid in [
      { ..limits, max_bytes: 0, },
      { ..limits, max_bytes: -1, },
      { ..limits, max_depth: -1, },
      { ..limits, max_values: 0, },
    ] {
    assert_eq(projection_header_error(b"\xff", invalid), "data.invalid_limits")
  }
  assert_eq(
    projection_header_error(exact, { ..limits, max_depth: 0, }),
    "json_limit",
  )
  assert_eq(
    projection_header_error(exact, { ..limits, max_values: 1, }),
    "json_limit",
  )
  let nested = b"{\"formatVersion\":4,\"later\":[[0]]}"
  let nested_limits : @data.Limits = {
    max_bytes: nested.length(),
    max_depth: 3,
    max_values: 5,
  }
  assert_eq(
    @data.recognize_projection_header(nested, nested_limits).to_release_string(),
    "4.0.0",
  )
  assert_eq(
    projection_header_error(nested, { ..nested_limits, max_depth: 2, }),
    "json_limit",
  )
  assert_eq(
    projection_header_error(nested, { ..nested_limits, max_values: 4, }),
    "json_limit",
  )
}

///|
test "projection header admits explicit large documents without a manifest ceiling" {
  let bytes : Array[Byte] = b"{\"formatVersion\":99,\"padding\":\""
    .iter()
    .collect()
  for _index = 0; _index < 131073; _index = _index + 1 {
    bytes.push(0x61)
  }
  for byte in b"\"}" {
    bytes.push(byte)
  }
  let source = Bytes::from_array(bytes)
  assert_true(source.length() > 128 * 1024)
  let limits : @data.Limits = {
    max_bytes: source.length(),
    max_depth: 1,
    max_values: 3,
  }
  assert_eq(
    @data.recognize_projection_header(source, limits).to_release_string(),
    "99.0.0",
  )
  assert_eq(
    projection_header_error(source, {
      ..limits,
      max_bytes: source.length() - 1,
    }),
    "data.byte_limit",
  )
  assert_eq(
    @data.recognize_projection_header(
      b"{\"formatVersion\":\"3.1.0\",\"label\":\"\xf0\x9f\x98\x80\"}",
      { ..limits, max_bytes: 2147483647, },
    ).to_release_string(),
    "3.1.0",
  )
}

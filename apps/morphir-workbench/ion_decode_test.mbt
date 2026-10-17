///|
/// The base64 bytes of the generated `symbols.10n` of a MoonBit compile.
fn generated_symbols() -> String {
  let reply = @pipeline.execute({
    "operation": "compile",
    "source": "pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }",
    "languageId": "moonbit",
    "target": "moonbit",
  })
  let found = match json_member(reply, "artifacts") {
    Array(files) =>
      files.filter(file => {
        json_member(file, "path") == Json::string("symbols.10n")
      })
    _ => []
  }
  match found {
    [file, ..] =>
      match json_member(file, "content") {
        String(content) => content
        _ => ""
      }
    [] => ""
  }
}

///|
fn decode(source : String) -> Json {
  @pipeline.execute({
    "operation": "decode-ion",
    "path": "symbols.10n",
    "source": source,
  })
}

///|
test "a generated binary Ion file decodes to Ion text that reads back to the same values" {
  let source = generated_symbols()
  let reply = decode(source)
  let text = match json_member(reply, "text") {
    String(text) => text
    _ => ""
  }
  @expect.expect_all(s => {
    s.expect(source, label="generated").not().to_be_empty()
    s
    .expect(reply, label="reply")
    .to_contain_json({ "success": true, "path": "symbols.10n" })
    s.expect(text, label="text").not().to_be_empty()
    // Round trip: the text reads back to the values of the original binary.
    let original = @ion_binary.read_binary(@base64.decode(source[:])[:])
    let read_back = @ion_text.read_ion_datagram(text[:])
    s
    .expect(
      read_back.length() == original.length() &&
      original.mapi((i, value) => value.equals(read_back[i])).all(same => same),
      label="round trip",
    )
    .to_be_true()
    s
    .expect(json_member(reply, "values"), label="values")
    .to_equal(Json::number(original.length().to_double()))
  })
}

///|
test "corrupt, non-Ion and oversized files fail with their codes" {
  // The version marker followed by a struct descriptor whose length runs past the end.
  let corrupt = @base64.encode(b"\xE0\x01\x00\xEA\xDE\x9F\x81"[:])
  let plain = @base64.encode(b"module A"[:])
  let large = "A".repeat((@pipeline.ion_input_limit + 2) / 3 * 4 + 4)
  let code = fn(reply : Json) { json_member(reply, "code") }
  @expect.expect_all(s => {
    s
    .expect(code(decode(corrupt)), label="corrupt")
    .to_satisfy(c => c is String(text) && text.has_prefix("ion."))
    s
    .expect(decode(corrupt), label="corrupt stage")
    .to_contain_json({ "success": false, "stage": "decode" })
    s
    .expect(code(decode(plain)), label="not Ion")
    .to_equal(Json::string("workbench.not_binary_ion"))
    s
    .expect(code(decode("%%%")), label="not base64")
    .to_equal(Json::string("workbench.invalid_encoding"))
    s
    .expect(code(decode(large)), label="too large")
    .to_equal(Json::string("workbench.ion_input_too_large"))
  })
}

///|
/// The base64 of the binary form of Ion `text`.
fn binary_of(text : String) -> String raise {
  @base64.encode(
    @ion_binary.write_binary(@ion_text.read_ion_datagram(text[:]))[:],
  )
}

///|
fn code_of(reply : Json) -> Json {
  json_member(reply, "code")
}

///|
test "the budgeted writer writes what write_all_pretty writes" {
  let texts = [
    "a::b::{name: \"x\", list: [1, 2.5e0, 3.25, null.int, true], empty: {}, none: []}",
    "(f 'quoted symbol' [] () + -) 2024-01-02T03:04:05Z {{ aGVsbG8= }} {{ \"clob\" }}",
    "$ion_symbol_table::{symbols: [\"one\", \"two\"]} $10 $11 'one'::[[[1]], {a: (b c)}]",
    "\"line\\nbreak \\u00e9\" nan +inf -0e0 1.0d2",
  ]
  let symbols = @ion_binary.read_binary(
    @base64.decode(generated_symbols()[:])[:],
  )
  @expect.expect_all(s => {
    for text in texts {
      let values = @ion_text.read_ion_datagram(text[:])
      s
      .expect(
        @pipeline.ion_text_within(values, @pipeline.ion_text_limit) ==
        Written(@ion_text.write_all_pretty(values)),
        label=text,
      )
      .to_be_true()
    }
    s
    .expect(
      @pipeline.ion_text_within(symbols, @pipeline.ion_text_limit) ==
      Written(@ion_text.write_all_pretty(symbols)),
      label="symbols.10n",
    )
    .to_be_true()
  })
}

///|
test "the text budget stops the writer before it passes the limit" {
  let values = @ion_text.read_ion_datagram(
    ("[".repeat(20) + "0,".repeat(1000) + "]".repeat(20))[:],
  )
  @expect.expect_all(s => {
    for limit in [0, 1, 100, 5000] {
      let stopped = @pipeline.ion_text_within(values, limit) is OverBudget(used) &&
        used <= limit
      s.expect(stopped, label="limit " + limit.to_string()).to_be_true()
    }
  })
}

///|
test "a small file whose text passes the limit is refused" {
  // About 100 KB of binary: 99,000 zeros 30 lists deep. Each prints on a line of 63 characters, over 6 Mi in all.
  let source = binary_of("[".repeat(30) + "0,".repeat(99000) + "]".repeat(30))
  @expect.expect_all(s => {
    s.expect(source.length(), label="small input").to_be_less_than(200 * 1024)
    s
    .expect(decode(source), label="reply")
    .to_contain_json({
      "success": false,
      "code": "workbench.ion_text_too_large",
      "stage": "decode",
    })
  })
}

///|
test "container depth is bounded before reading even an empty innermost container" {
  // Build bytes directly: the Ion 0.5 text reader independently rejects depth
  // 129, so parsing text here would never exercise Workbench's binary guard.
  for type_code in [11, 12, 13] {
    for annotated in [false, true] {
      for
        (leaf_name, leaf) in [
          ("empty", []),
          ("scalar", [b'\x20']),
          ("null.list", [b'\xBF']),
          ("null.sexp", [b'\xCF']),
          ("null.struct", [b'\xDF']),
          ("annotated scalar", [b'\xE3', b'\x81', b'\x84', b'\x20']),
          ("annotated typed null", [b'\xE3', b'\x81', b'\x84', b'\xBF']),
        ] {
        let label = "type " +
          type_code.to_string() +
          ", annotated " +
          annotated.to_string() +
          ", leaf " +
          leaf_name
        assert_eq(
          json_member(
            decode(nested_binary(type_code, 128, leaf, annotated~)),
            "success",
          ),
          Json::boolean(true),
          msg=label,
        )
        assert_eq(
          code_of(decode(nested_binary(type_code, 129, leaf, annotated~))),
          Json::string("workbench.ion_too_deep"),
          msg=label,
        )
      }
    }
  }
}

///|
test "a file with too many values is refused before it is read" {
  let many = after_marker(
    [..long_header(11, 100000), ..Array::make(100000, b'\x20')],
  )
  assert_eq(
    code_of(decode(many)),
    Json::string("workbench.ion_too_many_values"),
  )
}

///|
test "every prefix of a real file gives a code or its values, never an abort" {
  let bytes = @base64.decode(generated_symbols()[:])
  @expect.expect_all(s => {
    for length in 0..<=bytes.length() {
      let reply = decode(@base64.encode(bytes[0:length]))
      let label = "prefix " + length.to_string()
      if json_member(reply, "success") != Json::boolean(true) {
        s
        .expect(code_of(reply), label~)
        .to_satisfy(code => code is String(text) && text != "")
      }
    }
    for length in 0..<4 {
      s
      .expect(
        code_of(decode(@base64.encode(bytes[0:length]))),
        label="marker prefix " + length.to_string(),
      )
      .to_equal(Json::string("workbench.not_binary_ion"))
    }
  })
}

///|
/// Property: random bytes after the version marker give a code or values, never an abort.
test "random bytes after the version marker never abort the decode" {
  @expect.for_all((octets : Array[UInt32]) => {
    let bytes = Bytes::from_array(
      [
        b'\xE0',
        b'\x01',
        b'\x00',
        b'\xEA',
        ..octets.map(o => (o % 256).to_byte()),
      ],
    )
    let reply = decode(@base64.encode(bytes[:]))
    if json_member(reply, "success") != Json::boolean(true) {
      @expect.expect(code_of(reply), label=reply.stringify()).to_satisfy(code => {
        code is String(text) && text != ""
      })
    }
  })
}

///|
/// The base64 of the version marker followed by `body`.
fn after_marker(body : Array[Byte]) -> String {
  @base64.encode(
    Bytes::from_array([b'\xE0', b'\x01', b'\x00', b'\xEA', ..body])[:],
  )
}

///|
/// The descriptor and VarUInt length of a value of type `type_code` with a `length`-byte body.
fn long_header(type_code : Int32, length : Int32) -> Array[Byte] {
  let width : Array[Byte] = [((length & 0x7F) | 0x80).to_byte()]
  let mut rest = length >> 7
  while rest > 0 {
    width.insert(0, (rest & 0x7F).to_byte())
    rest = rest >> 7
  }
  [((type_code << 4) | 0x0E).to_byte(), ..width]
}

///|
/// Direct binary fixture, independent of the Ion readers' nesting limit.
/// Each annotation uses system symbol 4 (`name`) and adds no container level.
fn nested_binary(
  type_code : Int32,
  depth : Int32,
  leaf : Array[Byte],
  annotated~ : Bool = false,
) -> String {
  let mut body = leaf
  for _ in 0..<depth {
    let contents = if type_code == 13 && !body.is_empty() {
      [b'\x84', ..body]
    } else {
      body
    }
    body = [..long_header(type_code, contents.length()), ..contents]
    if annotated {
      body = [..long_header(14, body.length() + 2), b'\x81', b'\x84', ..body]
    }
  }
  after_marker(body)
}

///|
test "untyped nulls count as values and NOP pads do not" {
  let nulls = fn(count : Int32) { Array::make(count, b'\x0F') }
  @expect.expect_all(s => {
    s
    .expect(code_of(decode(after_marker(nulls(100001)))), label="100,001 nulls")
    .to_equal(Json::string("workbench.ion_too_many_values"))
    s
    .expect(decode(after_marker(nulls(100000))), label="100,000 nulls")
    .to_contain_json({ "success": true, "values": 100000 })
    // One-byte pads (0x00) and a two-byte pad (0x01 0x00) between the nulls.
    s
    .expect(
      decode(
        after_marker(
          [..nulls(100000), ..Array::make(500, b'\x00'), b'\x01', b'\x00'],
        ),
      ),
      label="pads",
    )
    .to_contain_json({ "success": true, "values": 100000 })
  })
}

///|
test "annotation wrappers count as values but annotation symbols add no values" {
  // Three system-symbol annotations around one zero: one wrapper plus one
  // scalar, independent of the number of annotation symbols in the wrapper.
  let annotated = [b'\xE5', b'\x83', b'\x84', b'\x84', b'\x84', b'\x20']
  let body : Array[Byte] = []
  for _ in 0..<50000 {
    for byte in annotated {
      body.push(byte)
    }
  }
  assert_eq(
    json_member(decode(after_marker(body)), "success"),
    Json::boolean(true),
  )
  assert_eq(
    code_of(decode(after_marker([..body, ..annotated]))),
    Json::string("workbench.ion_too_many_values"),
  )
}

///|
test "an annotation wrapper around another is a syntax error" {
  // Outer wrapper: annotations length 1, symbol 4, then an inner wrapper: annotations length 1, symbol 4, null.
  let nested = after_marker([
    b'\xE6', b'\x81', b'\x84', b'\xE3', b'\x81', b'\x84', b'\x0F',
  ])
  let single = after_marker([b'\xE3', b'\x81', b'\x84', b'\x0F'])
  @expect.expect_all(s => {
    s
    .expect(decode(nested), label="nested")
    .to_contain_json({
      "success": false,
      "code": "ion.syntax",
      "stage": "decode",
    })
    s
    .expect(decode(single), label="single")
    .to_contain_json({ "success": true, "text": "name::null" })
  })
}

///|
test "an integer or decimal longer than 64 KiB is refused" {
  let limit = @pipeline.ion_number_limit
  let int = fn(length : Int32) {
    after_marker([..long_header(2, length), ..Array::make(length, b'\xFF')])
  }
  // A decimal: exponent 0 (VarInt 0x80), then the coefficient.
  let decimal = fn(length : Int32) {
    after_marker(
      [..long_header(5, length), b'\x80', ..Array::make(length - 1, b'\x7F')],
    )
  }
  @expect.expect_all(s => {
    s
    .expect(code_of(decode(int(limit + 1))), label="long int")
    .to_equal(Json::string("workbench.ion_number_too_large"))
    s
    .expect(decode(int(limit)), label="64 KiB int")
    .to_contain_json({ "success": true })
    s
    .expect(code_of(decode(decimal(limit + 1))), label="long decimal")
    .to_equal(Json::string("workbench.ion_number_too_large"))
  })
}

///|
/// Ion text for a random value: `seeds` choose each value's kind and contents, `depth` stops the nesting.
fn random_ion(seeds : Array[UInt32], at : Ref[Int32], depth : Int32) -> String {
  let next = fn() -> Int32 {
    let seed = if seeds.is_empty() {
      0U
    } else {
      seeds[at.val % seeds.length()]
    }
    at.val += 1
    (seed % 1000U).reinterpret_as_int()
  }
  let annotation = if next() % 5 == 0 { "tag::" } else { "" }
  let kind = if depth >= 4 { next() % 9 } else { next() % 12 }
  let n = next()
  annotation +
  (match kind {
    0 => n.to_string()
    1 => "-1" + n.to_string() + "23456789012345678901234567890"
    2 => n.to_string() + ".25e" + (n % 7).to_string()
    3 => n.to_string() + ".0d-" + (n % 5).to_string()
    4 => "\"text \\n \\u00e9 \\\"" + n.to_string() + "\\\"\""
    5 => if n % 2 == 0 { "'quoted symbol'" } else { "plain_" + n.to_string() }
    6 => if n % 3 == 0 { "null" } else { "null.string" }
    7 => "{{ aGVsbG8= }}"
    8 => "2024-01-02T03:04:05Z"
    9 => {
      let items = Array::makei(n % 4, _ => random_ion(seeds, at, depth + 1))
      "[" + items.join(", ") + "]"
    }
    10 => {
      let items = Array::makei(n % 4, _ => random_ion(seeds, at, depth + 1))
      "(" + items.join(" ") + ")"
    }
    _ => {
      let fields = Array::makei(n % 4, i => {
        "f" + i.to_string() + ": " + random_ion(seeds, at, depth + 1)
      })
      "{" + fields.join(", ") + "}"
    }
  })
}

///|
/// Property: on random values read back from binary, the budgeted writer writes what write_all_pretty writes.
test "the budgeted writer matches write_all_pretty on random values" {
  @expect.for_all((seeds : Array[UInt32]) => {
    let at = Ref(0)
    let text = Array::makei(3, _ => random_ion(seeds, at, 0)).join(" ")
    let values = @ion_binary.read_binary(
      @ion_binary.write_binary(@ion_text.read_ion_datagram(text[:]))[:],
    )
    @expect.expect(
      @pipeline.ion_text_within(values, @pipeline.ion_text_limit) ==
      Written(@ion_text.write_all_pretty(values)),
      label=text,
    ).to_be_true()
  })
}

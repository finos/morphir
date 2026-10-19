///|
fn binary(path : String, bytes : Bytes) -> Json {
  {
    "path": path,
    "content": @base64.encode(bytes[:]),
    "binary": true,
    "encoding": "base64",
  }
}

///|
let ion_file : Json = binary("data/symbols.bin", b"\xE0\x01\x00\xEA\x0F")

///|
let other_file : Json = binary("symbols.10n", b"\x00\x01\x02\x03\x04")

///|
let text_file : Json = {
  "path": "library.mbt",
  "content": "fn f() {}",
  "binary": false,
}

///|
let files : Array[Json] = [ion_file, other_file, text_file]

///|
test "binary Ion is found by its version marker, not its name" {
  @expect.expect_all(s => {
    s.expect(@generated.is_binary_ion(ion_file), label="marker").to_be_true()
    s
    .expect(
      @generated.is_binary_ion(other_file),
      label=".10n without the marker",
    )
    .to_be_false()
    s.expect(@generated.is_binary_ion(text_file), label="text").to_be_false()
    s
    .expect(
      @generated.is_binary_ion({
        "path": "x.10n",
        "content": "4AEA6g==",
        "binary": true,
      }),
      label="no declared encoding",
    )
    .to_be_false()
  })
}

///|
test "a file's menu offers what applies to it" {
  let entries = fn(file : Json) {
    @generated.menu_items(file).map(entry => {
      (entry.0, entry.1.label, entry.1.enabled)
    })
  }
  @expect.expect_all(s => {
    s
    .expect(entries(ion_file), label="binary Ion")
    .to_equal([
      (ViewIonText, "View as Ion text", true),
      (ViewHex, "View raw (hex)", true),
      (CopyPath, "Copy path", true),
      (Download, "Download", true),
    ])
    s
    .expect(
      entries(other_file).map(e => e.2),
      label="other binary: Ion text disabled",
    )
    .to_equal([false, true, true, true])
    s
    .expect(entries(text_file).map(e => e.0), label="text file")
    .to_equal([CopyPath, Download])
  })
}

///|
test "the menu opens, moves with keys and asks for the Ion text" {
  let state = @generated.State::new()
  let (opened, focus) = state.apply(
    files,
    OpenMenu("data/symbols.bin", 10, 20, 1200, 800),
  )
  let (asked, effects) = opened.apply(
    files,
    MenuKey(@keys.Chord::plain("Enter")),
  )
  let (hex, _) = opened.apply(files, Choose(ViewHex))
  let (refused, nothing) = state.apply(
    files,
    OpenMenu("symbols.10n", 0, 0, 800, 600),
  ).0.apply(files, Choose(ViewIonText))
  let (decoded, _) = asked.apply(
    files,
    ShowIonText("data/symbols.bin", "{}", 1),
  )
  let (back, _) = decoded.apply(files, ShowSummary)
  @expect.expect_all(s => {
    s
    .expect(opened.menu, label="menu")
    .to_equal(Some({ path: "data/symbols.bin", left: 10, top: 20, index: 0, }))
    s.expect(focus, label="focus").to_equal([FocusMenu(0)])
    s
    .expect(effects, label="decode as a execution")
    .to_equal([
      RequestIonText("data/symbols.bin"),
      FocusFile("data/symbols.bin"),
    ])
    s.expect(asked.menu, label="closed").to_be_none()
    s.expect(hex.preview, label="hex").to_equal(Hex("data/symbols.bin"))
    s.expect(nothing, label="disabled entry does nothing").to_be_empty()
    s.expect(refused.menu is Some(_), label="menu stays").to_be_true()
    s
    .expect(decoded.preview, label="decoded")
    .to_equal(IonText("data/symbols.bin", "{}", 1))
    s.expect(back.preview, label="back").to_equal(Summary)
    s.expect(decoded.reset().preview, label="new output").to_equal(Summary)
  })
}

///|
test "raw bytes show as hex rows with printable text" {
  let dump = @generated.hex_dump(b"\xE0\x01\x00\xEAhello, Ion!\x00\x7F\x10\x20")
  @expect.expect(dump).to_equal(
    "00000000  e0 01 00 ea 68 65 6c 6c  6f 2c 20 49 6f 6e 21 00  |....hello, Ion!.|\n00000010  7f 10 20                                          |.. |\n",
  )
}

///|
/// Property: the size read from the base64 length and padding is the decoded size.
test "a binary file's size comes from its base64 without decoding it" {
  @expect.for_all((octets : Array[UInt32]) => {
    let bytes = Bytes::from_array(octets.map(o => (o % 256).to_byte()))
    @expect.expect(
      @generated.binary_size(binary("x.bin", bytes)),
      label=bytes.length().to_string(),
    ).to_equal(Some(bytes.length()))
  })
  @expect.expect_all(s => {
    s.expect(@generated.binary_size(text_file), label="text").to_be_none()
    s
    .expect(
      @generated.binary_size({
        "path": "x",
        "content": "abc",
        "binary": true,
        "encoding": "base64",
      }),
      label="not base64",
    )
    .to_be_none()
  })
}

///|
test "a hex dump of a file's first bytes says how many more there are" {
  @expect.expect(@generated.hex_dump(b"\x01\x02", total=1000)).to_equal(
    "00000000  01 02                                             |..|\n… 998 more bytes not shown\n",
  )
}

///|
test "verified byte references enable downloads and bounded raw previews" {
  let file : Json = {
    "path": "original.bin",
    "content": "not a byte encoding",
    "binary": true,
    "encoding": "verified-bytes",
    "verifiedArtifact": { "setId": "local-output", "artifactId": "file" },
    "previewBase64": @base64.encode(b"\x00\x01\x02\x03"[:]),
    "byteLength": 16777216,
  }
  @expect.expect_all(s => {
    s.expect(@generated.binary_size(file)).to_equal(Some(16777216))
    s.expect(@generated.is_binary_ion(file)).to_be_false()
    s
    .expect(@generated.menu_items(file).map(entry => entry.1.enabled))
    .to_equal([false, true, true, true])
    s
    .expect(
      @generated.menu_items({
        "path": "invalid.txt",
        "binary": false,
        "content": "Invalid UTF-8 preview",
      }).map(entry => entry.1.enabled),
    )
    .to_equal([true, true])
  })
}

///|
test "verified Ion previews never authorize whole-file decoding" {
  let file : Json = {
    "path": "original.ion",
    "binary": true,
    "encoding": "verified-bytes",
    "verifiedArtifact": { "setId": "local-output", "artifactId": "file" },
    "previewBase64": @base64.encode(b"\xE0\x01\x00\xEA"[:]),
    "byteLength": 16777216,
  }
  @expect.expect_all(s => {
    s.expect(@generated.is_binary_ion(file), label="marker").to_be_true()
    s
    .expect(@generated.menu_items(file).map(entry => entry.1.enabled))
    .to_equal([false, true, true, true])
    s
    .expect(
      @generated.State::new().apply([file], ViewIonTextOf("original.ion")).1,
      label="no decode effect",
    )
    .to_equal([])
  })
}

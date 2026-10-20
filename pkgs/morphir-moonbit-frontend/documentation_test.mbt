///|
test "MoonBit documentation survives library IR and generated backends" {
  let output = @frontend.compile_library(
    input(
      "/// Compare names without normalization.\n///\n/// Uses **shortlex** order. λ😀\npub fn before(a : String, b : String) -> Bool { helper(a) < b }\n/// Preserve the exact text.\nfn helper(s : String) -> String { s }\n// Ordinary comment stays out of the API docs.\npub fn plain() -> Bool { true }",
    ),
  )
  let stored = @ir_json.write(output.ir)
  assert_true(
    stored.contains("Compare names without normalization."),
    msg="source documentation in IR",
  )
  assert_true(stored.contains("Preserve the exact text."))
  assert_false(stored.contains("Ordinary comment stays out"))
  let generated = library_generated(output)
  let artifact = generated.artifacts.filter(a => a.path == "library.mbt")[0]
  guard artifact.content is Text(source) else {
    fail("Expected generated source")
  }
  assert_true(
    source.contains(
      "/// Compare names without normalization.\n///\n/// Uses **shortlex** order. λ😀",
    ),
    msg="source documentation in MoonBit",
  )
  assert_true(source.contains("/// Preserve the exact text."))
  let scheme = @backend.emit_file(output.ir)
  assert_true(
    scheme.contains("; Compare names without normalization."),
    msg="source documentation in Scheme",
  )
}

///|
fn documented_ir() -> @frontend.LibraryOutput raise {
  let output = @frontend.compile_library(input("pub fn f() -> Bool { true }"))
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let module_def = package_def.modules.values().collect()[0].value
  let name = @ir.Name::parse("f")
  let item = module_def.values[name]
  module_def.values[name] = {
    ..item,
    value: {
      ..item.value,
      doc: Some("First line.\r\n\r\n**Second** λ😀\rLast line."),
    },
  }
  output
}

///|
test "MoonBit backend emits documentation already present in IR" {
  let generated = library_generated(documented_ir())
  guard generated.artifacts.filter(a => a.path == "library.mbt")[0].content
    is Text(source) else {
    fail("Expected source")
  }
  assert_true(
    source.contains(
      "/// First line.\n///\n/// **Second** λ😀\n/// Last line.",
    ),
  )
}

///|
test "Scheme backend emits documentation already present in IR" {
  let scheme = @backend.emit_file(documented_ir().ir)
  assert_true(
    scheme.contains("; First line.\n;\n; **Second** λ😀\n; Last line."),
  )
}

///|
test "legacy seed profile retains docs and separators do not invent empty docs" {
  let output = @frontend.compile(
    input(
      "///|\n/// A Boolean gate.\n///\n///   Indented Markdown.\npub fn gate(a : Bool) -> Bool { a }",
    ),
  )
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let module_def = package_def.modules.values().collect()[0].value
  assert_eq(
    module_def.values[@ir.Name::parse("gate")].value.doc,
    Some("A Boolean gate.\n\n  Indented Markdown."),
  )
  let empty = @frontend.compile_library(
    input("///|\npub fn f() -> Bool { true }\npub fn plain() -> Bool { false }"),
  )
  guard empty.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  for module_def in package_def.modules.values() {
    for value in module_def.value.values.values() {
      assert_eq(value.value.doc, None)
    }
  }
}

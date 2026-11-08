///|
let extension_test_digest : String = "a".repeat(64)

///|
fn extension_test_pin(
  runtime~ : Json = {
    "kind": "process",
    "platform": "aarch64-apple-darwin",
    "args": ["--serve", ""],
  },
) -> Map[String, Json] {
  {
    "contractVersion": "0.2.0",
    "artifact": {
      "path": "/opt/guest/morphir-extension",
      "sha256": extension_test_digest,
    },
    "runtime": runtime,
    "origin": "finos/morphir-moonbit apps/morphir-extension",
  }
}

///|
fn extension_test_refusal(value : Json) -> (String, String, Int32) {
  try {
    ignore(ExtensionPin::decode(value, Posix))
    ("decoded", "", 0)
  } catch {
    ExtensionError(status~, code~, message~) =>
      (code.name(), message, status.exit_code())
  }
}

///|
test "a contract 0.2.0 pin decodes into a worker specification" {
  let pin = ExtensionPin::decode(Json::object(extension_test_pin()), Posix)
  assert_eq(
    pin.spec.runtime,
    Process(platform=Aarch64AppleDarwin, args=["--serve", ""]),
  )
  assert_eq(pin.spec.artifact.sha256.to_string(), extension_test_digest)
  assert_eq(pin.descriptor, None)
  assert_eq(pin.origin, "finos/morphir-moonbit apps/morphir-extension")
  let described = extension_test_pin()
  described["descriptor"] = {
    "path": "/opt/guest/release.json",
    "sha256": "b".repeat(64),
  }
  let pin = ExtensionPin::decode(Json::object(described), Posix)
  assert_true(pin.descriptor is Some(_))
  let wasm = extension_test_pin(runtime={
    "kind": "wasm",
    "abi": "extism-kernel-v1",
  })
  assert_eq(
    ExtensionPin::decode(Json::object(wasm), Posix).spec.runtime,
    Wasm(abi=Some(ExtismKernelV1)),
  )
}

///|
test "a pin with an unknown field, a relative path or no digest is refused" {
  let host = extension_test_pin()
  host["host"] = { "root": "/tools" }
  let (code, message, status) = extension_test_refusal(Json::object(host))
  assert_eq(code, "extension.pin_invalid")
  assert_eq(status, 2)
  assert_true(message.contains("host"), msg=message)
  let relative = extension_test_pin()
  relative["artifact"] = {
    "path": "guest/morphir-extension",
    "sha256": extension_test_digest,
  }
  assert_eq(
    extension_test_refusal(Json::object(relative)).0,
    "extension.pin_invalid",
  )
  let undigested = extension_test_pin()
  undigested["artifact"] = { "path": "/opt/guest/morphir-extension" }
  assert_eq(
    extension_test_refusal(Json::object(undigested)).0,
    "extension.pin_invalid",
  )
  let no_origin = extension_test_pin()
  no_origin.remove("origin")
  assert_eq(
    extension_test_refusal(Json::object(no_origin)).0,
    "extension.pin_invalid",
  )
  let mixed = extension_test_pin(runtime={
    "kind": "process",
    "platform": "aarch64-apple-darwin",
    "args": [],
    "abi": "extism-kernel-v1",
  })
  assert_eq(
    extension_test_refusal(Json::object(mixed)).0,
    "extension.pin_invalid",
  )
  assert_eq(extension_test_refusal([1, 2]).0, "extension.pin_invalid")
}

///|
test "old pin contracts are retired with a pointer to the migration" {
  for contract in ["0.1.0", "0.1.0-draft.1"] {
    let old : Json = {
      "contractVersion": contract,
      "binding": "core-wasm-process",
      "origin": "old",
    }
    let (code, message, status) = extension_test_refusal(old)
    assert_eq(code, "extension.pin_retired")
    assert_eq(status, 2)
    assert_true(message.contains("0.2.0"), msg=message)
    assert_true(message.contains(extension_migration), msg=message)
  }
  let future : Json = { "contractVersion": "0.3.0" }
  assert_eq(extension_test_refusal(future).0, "extension.pin_invalid")
}

///|
test "retired helper options are refused before a pin is read" {
  for option in ["--extension-helper", "--node"] {
    let cli = parse_cli([
      "extension", "describe", option, "/tools/helper", "--extension-pin", "pin.json",
    ])
    let refusal = try {
      extension_retired_options(cli)
      None
    } catch {
      ExtensionError(status~, code~, message~) => Some((status, code, message))
    }
    guard refusal is Some((status, code, message)) else {
      fail("\{option} was accepted")
    }
    assert_eq(status.exit_code(), 2)
    assert_eq(code.name(), "extension.option_retired")
    assert_true(message.contains(option), msg=message)
    assert_true(message.contains(extension_migration), msg=message)
  }
  extension_retired_options(
    parse_cli(["extension", "describe", "--extension-pin", "pin.json"]),
  )
}

///|
test "each status has one exit code and one report shape" {
  assert_eq(Refused.exit_code(), 2)
  assert_eq(Failed.exit_code(), 1)
  assert_eq(TimedOut.exit_code(), 124)
  assert_eq(Cancelled.exit_code(), 130)
  let report = ExtensionReport::failure(
    Compile,
    refused(Worker(ClaimsMismatch), "the descriptor claims differ"),
  )
  assert_eq(report.exit_code(), 2)
  assert_eq(
    report.to_json().stringify(),
    "{\"profile\":\"morphir/command-result\",\"contractVersion\":\"0.1.0\",\"command\":\"extension.compile\",\"state\":\"failed\",\"exitCode\":2,\"diagnostics\":[],\"error\":{\"code\":\"extension.claims_mismatch\",\"message\":\"the descriptor claims differ\"}}",
  )
}

///|
fn extension_test_claims(
  frontend~ : Json = {
    "languages": [{ "id": "gleam", "fileExtensions": [".gleam"] }],
    "irVersions": ["4"],
    "compile": true,
  },
  backend? : Json,
  tuples~ : Array[Json] = [],
  protocol? : String,
) -> Json {
  let capabilities : Map[String, Json] = { "frontend": frontend }
  if backend is Some(backend) {
    capabilities["backend"] = backend
  }
  if !tuples.is_empty() {
    capabilities["modelTransport"] = {
      "tuples": Json::array(tuples),
      "limits": {
        "maxEncodedBytes": 5592408,
        "maxDecodedBytes": 4194304,
        "maxDepth": 128,
        "maxNodes": 100000,
      },
      "guarantees": [],
    }
  }
  let result : Map[String, Json] = {
    "extension": { "id": "fixture-gleam", "version": "1.0.0" },
    "capabilities": Json::object(capabilities),
  }
  match protocol {
    Some(line) => result["protocolVersion"] = Json::string(line)
    None =>
      result["protocolVersions"] = if tuples.is_empty() {
        ["0.1"]
      } else {
        ["0.2.0-draft.1", "0.1"]
      }
  }
  Json::object(result)
}

///|
fn extension_test_tuple(operation : String, codec : String) -> Json {
  {
    "operation": operation,
    "profile": if codec == "ion-binary" {
      "morphir-model"
    } else {
      "morphir-ir"
    },
    "codec": codec,
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
}

///|
/// A source base for the tests, with POSIX paths. Without `base` the input
/// directory is the base, so a directory gives URIs relative to it and a
/// single file follows the rule without `--source-base`.
fn extension_test_base(path : String, base? : String) -> ExtensionSourceBase {
  { given: base, cwd: path, style: Posix, }
}

///|
/// Reads a source snapshot and returns its URIs, or the error code.
fn extension_test_sources(
  path : String,
  base? : String,
  limits~ : ExtensionSourceLimits = extension_source_limits,
) -> Result[Array[String], String] {
  try
    extension_sources(
      path,
      [".gleam"],
      () => (),
      base=extension_test_base(path, base?),
      limits~,
    )
  catch {
    ExtensionError(code~, message~, ..) => Err(code.name() + ": " + message)
  } noraise {
    documents => Ok(documents.map(document => document.uri))
  }
}

///|
fn extension_test_input_invalid(result : Result[Array[String], String]) -> Bool {
  result is Err(message) && message.has_prefix("extension.input_invalid: ")
}

///|
/// The refusal of `action`: its code, message and exit status.
fn extension_test_error(
  action : () -> Unit raise ExtensionError,
) -> (String, String, Int32) {
  try action() catch {
    ExtensionError(status~, code~, message~) =>
      (code.name(), message, status.exit_code())
  } noraise {
    _ => ("accepted", "", 0)
  }
}

///|
test "compile selects sources by the claimed file extensions and sends the claimed language" {
  let claims = @worker.Claims::from_describe(extension_test_claims())
  let language = extension_language(claims, None)
  assert_eq(language.language_id.to_string(), "gleam")
  let extensions = language.file_extensions.map(extension => {
    extension.to_string()
  })
  assert_eq(extensions, [".gleam"])
  let root = @platform.temporary()
  @platform.mkdir(root + "/src")
  @platform.mkdir(root + "/src/nested")
  @platform.write(root + "/src/lib.gleam", "pub fn lib() { 2 }")
  @platform.write(root + "/src/app.gleam", "pub fn main() { 1 }")
  @platform.write(root + "/src/nested/deep.gleam", "pub fn deep() { 3 }")
  @platform.write(root + "/src/README.md", "not a source")
  let documents = extension_sources(
    root + "/src",
    extensions,
    () => (),
    base=extension_test_base(root + "/src"),
  )
  assert_eq(documents.map(document => document.uri), [
    "app.gleam", "lib.gleam", "nested/deep.gleam",
  ])
  assert_eq(documents.map(document => document.text), [
    "pub fn main() { 1 }", "pub fn lib() { 2 }", "pub fn deep() { 3 }",
  ])
  // A single file keeps its clean relative path; a file without a claimed
  // extension is refused.
  assert_eq(extension_test_sources(root + "/src/app.gleam"), Ok(["app.gleam"]))
  assert_true(
    extension_test_input_invalid(
      extension_test_sources(root + "/src/README.md"),
    ),
  )
  // A directory with no claimed file gives no document and is refused.
  @platform.mkdir(root + "/docs")
  @platform.write(root + "/docs/guide.md", "only text")
  match extension_test_sources(root + "/docs") {
    Err(message) =>
      assert_true(
        message.has_prefix("extension.input_invalid: ") &&
        message.contains(".gleam"),
        msg=message,
      )
    Ok(uris) => fail("accepted \{uris.join(", ")}")
  }
}

///|
test "language from claims: the only language, the one that --language names, or a refusal" {
  let claims = (languages : Array[Json]) => {
    @worker.Claims::from_describe(
      extension_test_claims(frontend={
        "languages": Json::array(languages),
        "irVersions": ["4"],
        "compile": true,
      }),
    )
  }
  let gleam : Json = { "id": "gleam", "fileExtensions": [".gleam"] }
  let elm : Json = { "id": "elm", "fileExtensions": [".elm"] }
  let language = (text : String) => Some(@ids.LanguageId::parse(text))
  let several = claims([elm, gleam])
  let python = language("python")
  // One claimed language: the CLI uses it.
  assert_eq(
    extension_language(claims([gleam]), None).language_id.to_string(),
    "gleam",
  )
  // Several claimed languages and no choice: input_invalid, exit 2, and the
  // message names every claimed language.
  let (code, message, status) = extension_test_error(() => {
    ignore(extension_language(several, None))
  })
  assert_eq((code, status), ("extension.input_invalid", 2))
  assert_true(
    message.contains("elm") &&
    message.contains("gleam") &&
    message.contains("--language"),
    msg=message,
  )
  // --language selects one of them, with only its file extensions.
  let selected = extension_language(several, language("gleam"))
  assert_eq(selected.language_id.to_string(), "gleam")
  assert_eq(selected.file_extensions.map(extension => extension.to_string()), [
    ".gleam",
  ])
  // A language that the extension does not claim is a capability refusal.
  let (code, message, status) = extension_test_error(() => {
    ignore(extension_language(several, python))
  })
  assert_eq((code, status), ("extension.capability_unavailable", 2))
  assert_true(message.contains("python"), msg=message)
}

///|
test "the source base gives each URI its path relative to the base" {
  let base = (given : String?, cwd : String) => ExtensionSourceBase::{
    given,
    cwd,
    style: Posix,
  }
  // Without --source-base the input is its own base, wherever the current
  // directory is.
  assert_eq(base(None, "/work/shop").segments("src/app/"), [])
  assert_eq(base(None, "/tmp").segments("/work/shop/src"), [])
  // A base of the current directory names the path from it.
  assert_eq(base(Some("."), "/work/shop").segments("src"), ["src"])
  assert_eq(base(Some("."), "/work/shop").segments("src/app/"), ["src", "app"])
  assert_eq(base(Some("."), "/work/shop").segments("."), [])
  // An explicit base gives the same segments for an absolute input.
  assert_eq(base(Some("/work/shop"), "/tmp").segments("/work/shop/src"), ["src"])
  // A relative base is relative to the current directory.
  assert_eq(base(Some("shop"), "/work").segments("shop/src/../src"), ["src"])
  // An input outside the base is refused, and the message names the base.
  for
    (refused, path) in [
      (base(Some("/work/shop"), "/tmp"), "/other/src"),
      (base(Some("/work/shop/src"), "/work/shop/src"), ".."),
      (base(Some("/work/shop"), "/tmp"), "/work/shopping/src"),
    ] {
    let (code, message, status) = extension_test_error(() => {
      ignore(refused.segments(path))
    })
    assert_eq((code, status), ("extension.input_invalid", 2), msg=path)
    assert_true(message.contains(refused.given.unwrap()), msg=message)
  }
  // Windows paths compare drive letters without case.
  let windows = ExtensionSourceBase::{
    given: Some("C:\\work\\shop"),
    cwd: "C:\\",
    style: Windows,
  }
  assert_eq(windows.segments("c:\\work\\shop\\src\\app"), ["src", "app"])
  assert_eq(
    extension_test_error(() => ignore(windows.segments("D:\\work\\shop"))).0,
    "extension.input_invalid",
  )
}

///|
test "a tree has URIs from the input directory, or from --source-base when given" {
  let root = @platform.temporary()
  @platform.mkdir(root + "/src")
  @platform.mkdir(root + "/src/app")
  @platform.mkdir(root + "/src/shared")
  @platform.write(root + "/src/app/money.gleam", "import shared/numbers\n")
  @platform.write(root + "/src/app/orders.gleam", "import app/money\n")
  @platform.write(root + "/src/shared/numbers.gleam", "pub type Number = Int\n")
  let expected = [
    "src/app/money.gleam", "src/app/orders.gleam", "src/shared/numbers.gleam",
  ]
  // Without --source-base the input directory is the base, also when the
  // current directory is elsewhere: `compile src` names `app/money.gleam`
  // and `compile .` names `src/app/money.gleam`.
  let own = (path : String, cwd : String) => {
    extension_sources(path, [".gleam"], () => (), base={
      given: None,
      cwd,
      style: Posix,
    }).map(document => document.uri)
  }
  let uris = own(root + "/src", "/elsewhere") catch {
    ExtensionError(message~, ..) => fail("refused: \{message}")
  }
  assert_eq(uris, [
    "app/money.gleam", "app/orders.gleam", "shared/numbers.gleam",
  ])
  let uris = own(root, "/elsewhere") catch {
    ExtensionError(message~, ..) => fail("refused: \{message}")
  }
  assert_eq(uris, expected)
  // An explicit source base names each file from the base.
  assert_eq(extension_test_sources(root + "/src", base=root), Ok(expected))
  // A deeper input keeps the URIs from the base, so module names do not
  // depend on the directory that the user names.
  assert_eq(
    extension_test_sources(root + "/src/app", base=root),
    Ok(expected[:2].to_owned()),
  )
  // A single file with --source-base takes the directory rule; without it,
  // the earlier rule gives the name of an absolute path.
  assert_eq(
    extension_test_sources(root + "/src/app/money.gleam", base=root),
    Ok(["src/app/money.gleam"]),
  )
  assert_eq(
    extension_test_sources(root + "/src/app/money.gleam"),
    Ok(["money.gleam"]),
  )
  // An input outside the source base is refused and names the base.
  match extension_test_sources(root + "/src", base=root + "/other") {
    Err(message) =>
      assert_true(
        message.has_prefix("extension.input_invalid: ") &&
        message.contains(root + "/other"),
        msg=message,
      )
    Ok(uris) => fail("accepted \{uris.join(", ")}")
  }
}

///|
test "URI segments are percent-encoded and plain names stay the same" {
  let plain = "AZaz09-._~"
  assert_eq(extension_uri_segment(plain), plain)
  assert_eq(extension_uri_segment("money.gleam"), "money.gleam")
  for
    (name, encoded) in [
      ("my module.gleam", "my%20module.gleam"),
      ("a:b", "a%3Ab"),
      ("100%", "100%25"),
      ("why?", "why%3F"),
      ("#1", "%231"),
      ("a\\b", "a%5Cb"),
      ("tab\t", "tab%09"),
      ("caf\u{e9}", "caf%C3%A9"),
      ("\u{65e5}", "%E6%97%A5"),
      ("a+b@c", "a%2Bb%40c"),
    ] {
    assert_eq(extension_uri_segment(name), encoded, msg=name)
  }
  assert_eq(
    extension_document_uri("src/my module.gleam"),
    "src/my%20module.gleam",
  )
  // Names that a URI cannot carry as a segment are refused; any other name
  // is encoded.
  assert_eq(extension_source_name("lib.gleam"), None)
  assert_eq(extension_source_name(".hidden.gleam"), None)
  assert_eq(extension_source_name("a:b.gleam"), None)
  assert_eq(extension_source_name("a\\b.gleam"), None)
  for name in ["", ".", "..", "a/b.gleam", "/abs.gleam", "nul\u0000.gleam"] {
    assert_true(extension_source_name(name) is Some(_), msg=name)
  }
  let root = @platform.temporary()
  @platform.mkdir(root + "/src")
  @platform.write(root + "/src/my module.gleam", "pub fn main() { 1 }")
  @platform.write(root + "/src/a:b.gleam", "pub fn main() { 2 }")
  assert_eq(
    extension_test_sources(root + "/src", base=root),
    Ok(["src/a%3Ab.gleam", "src/my%20module.gleam"]),
  )
}

///|
test "documents are sorted by the whole URI in byte order, and a repeated URI is refused" {
  let root = @platform.temporary()
  @platform.mkdir(root + "/a")
  @platform.write(root + "/a/b.gleam", "1")
  @platform.write(root + "/a-c.gleam", "2")
  @platform.write(root + "/B.gleam", "3")
  @platform.write(root + "/caf\u{e9}.gleam", "4")
  // `-` (0x2D) comes before `/` (0x2F), so `a-c.gleam` is before
  // `a/b.gleam`, though the directory `a` sorts before the file `a-c.gleam`.
  assert_eq(
    extension_test_sources(root),
    Ok(["B.gleam", "a-c.gleam", "a/b.gleam", "caf%C3%A9.gleam"]),
  )
  let file = (uri : String) => ExtensionSourceFile::{
    uri,
    relative: uri,
    path: "/tree/" + uri,
  }
  assert_eq(
    extension_source_order([file("b"), file("a-c"), file("a/b")]).map(file => {
      file.uri
    }),
    ["a-c", "a/b", "b"],
  )
  let (code, message, status) = extension_test_error(() => {
    ignore(extension_source_order([file("x.gleam"), file("x.gleam")]))
  })
  assert_eq((code, status), ("extension.input_invalid", 2))
  assert_true(message.contains("x.gleam"), msg=message)
}

///|
test "the source walk skips hidden, build and dependency directories" {
  let root = @platform.temporary()
  @platform.write(root + "/app.gleam", "pub fn main() { 1 }")
  for
    directory in [
      ".git", ".mooncakes", "_build", "node_modules", ".venv", ".cache",
    ] {
    @platform.mkdir(root + "/" + directory)
    @platform.write(root + "/" + directory + "/skipped.gleam", "skipped")
  }
  @platform.mkdir(root + "/build")
  @platform.write(root + "/build/kept.gleam", "kept")
  assert_eq(extension_test_sources(root), Ok(["app.gleam", "build/kept.gleam"]))
}

///|
test "the source snapshot enforces its file, byte, entry and depth limits" {
  let root = @platform.temporary()
  @platform.mkdir(root + "/a")
  @platform.mkdir(root + "/a/b")
  @platform.write(root + "/one.gleam", "1234")
  @platform.write(root + "/two.gleam", "5678")
  @platform.write(root + "/a/b/three.gleam", "9")
  let limits = extension_source_limits
  assert_eq(
    extension_test_sources(root),
    Ok(["a/b/three.gleam", "one.gleam", "two.gleam"]),
  )
  let refused = (limits : ExtensionSourceLimits, words : String) => {
    match extension_test_sources(root, limits~) {
      Err(message) =>
        assert_true(
          message.has_prefix("extension.input_invalid: ") &&
          message.contains(words),
          msg=message,
        )
      Ok(uris) => fail("accepted \{uris.join(", ")}")
    }
  }
  // Each message names the limit and its value.
  refused({ ..limits, files: 2, }, "limit of 2 documents")
  refused({ ..limits, bytes: 8, }, "limit of 8 bytes")
  refused({ ..limits, file_bytes: 3, }, "one.gleam")
  refused({ ..limits, file_bytes: 3, }, "limit of 3 bytes for one file")
  refused({ ..limits, entries: 4, }, "limit of 4 entries")
  refused({ ..limits, depth: 1, }, "limit of 1 directories")
  // Each limit is inclusive.
  assert_true(
    extension_test_sources(root, limits={
      files: 3,
      file_bytes: 4,
      bytes: 9,
      entries: 5,
      depth: 2,
    })
    is Ok(_),
  )
}

///|
test "the default limits refuse 1,025 documents and a file larger than 1 MiB" {
  assert_eq(extension_source_limits.files, 1024)
  assert_eq(extension_source_limits.file_bytes, 1048576)
  assert_eq(extension_source_limits.bytes, 2097152)
  assert_eq(extension_source_limits.entries, 16384)
  assert_eq(extension_source_limits.depth, 32)
  let many = @platform.temporary()
  for index in 0..<1025 {
    @platform.write(many + "/m\{index}.gleam", "")
  }
  match extension_test_sources(many) {
    Err(message) =>
      assert_true(message.contains("limit of 1024 documents"), msg=message)
    Ok(uris) => fail("accepted \{uris.length()} documents")
  }
  let large = @platform.temporary()
  @platform.write(large + "/large.gleam", "x".repeat(1048577))
  match extension_test_sources(large) {
    Err(message) =>
      assert_true(
        message.contains("large.gleam") &&
        message.contains("limit of 1048576 bytes for one file"),
        msg=message,
      )
    Ok(_) => fail("accepted a file larger than 1 MiB")
  }
  @platform.write(large + "/large.gleam", "x".repeat(1048576))
  assert_eq(extension_test_sources(large), Ok(["large.gleam"]))
}

///|
test "text that is not UTF-8 is refused with the URI of the file" {
  let root = @platform.temporary()
  @platform.mkdir(root + "/src")
  @platform.write(root + "/src/good.gleam", "pub fn main() { 1 }")
  @platform.write_bytes(root + "/src/my latin.gleam", b"caf\xe9")
  match extension_test_sources(root + "/src", base=root) {
    Err(message) =>
      assert_true(
        message.has_prefix("extension.input_invalid: ") &&
        message.contains("src/my%20latin.gleam"),
        msg=message,
      )
    Ok(uris) => fail("accepted \{uris.join(", ")}")
  }
}

///|
#cfg(target="native")
async fn extension_test_symlink(target : String, path : String) -> Unit {
  @record_fs.symlink(target~, path)
}

///|
#cfg(target="js")
extern "js" fn extension_test_symlink_js(
  target : String,
  path : String,
) -> Unit =
  #| (target, path) => process.getBuiltinModule('node:fs').symlinkSync(target, path)

///|
#cfg(target="js")
fn extension_test_symlink(target : String, path : String) -> Unit {
  extension_test_symlink_js(target, path)
}

///|
async test "a symbolic link in the sources is refused with its relative path" {
  let root = @platform.temporary()
  @platform.mkdir(root + "/src")
  @platform.mkdir(root + "/other")
  @platform.write(root + "/src/app.gleam", "pub fn main() { 1 }")
  @platform.write(root + "/other/lib.gleam", "pub fn lib() { 2 }")
  extension_test_symlink(root + "/src/app.gleam", root + "/src/link.gleam")
  match extension_test_sources(root + "/src", base=root) {
    Err(message) =>
      assert_true(
        message.has_prefix("extension.input_invalid: ") &&
        message.contains("src/link.gleam") &&
        !message.contains(root),
        msg=message,
      )
    Ok(uris) => fail("accepted \{uris.join(", ")}")
  }
  // A link to a directory is refused and not followed.
  @platform.remove_file(root + "/src/link.gleam")
  extension_test_symlink(root + "/other", root + "/src/vendor")
  match extension_test_sources(root + "/src", base=root) {
    Err(message) => assert_true(message.contains("src/vendor"), msg=message)
    Ok(uris) => fail("accepted \{uris.join(", ")}")
  }
  // A link given as the source itself is refused too.
  extension_test_symlink(root + "/src/app.gleam", root + "/link.gleam")
  assert_true(
    extension_test_input_invalid(extension_test_sources(root + "/link.gleam")),
  )
}

///|
test "an operation that the extension does not claim is refused before any call" {
  let claims = @worker.Claims::from_describe(extension_test_claims())
  let refusal = try {
    ignore(@worker.GenerateChoice::of_plain_ir(claims, b"{}", {}))
    None
  } catch {
    Refusal(code~, ..) => Some(code.to_string())
  }
  assert_eq(refusal, Some("extension.capability_unavailable"))
  // A frontend with model tuples compiles on the model line; one without
  // compiles on MEP 0.1.
  assert_eq(extension_compile_offer(claims, None, None).offer, Legacy)
  let model = @worker.Claims::from_describe(
    extension_test_claims(
      frontend={
        "languages": [{ "id": "moonbit", "fileExtensions": [".mbt"] }],
        "compile": false,
      },
      tuples=[
        extension_test_tuple("morphir.frontend.compileModel", "morphir-json"),
        extension_test_tuple("morphir.frontend.compileModel", "ion-binary"),
      ],
    ),
  )
  // Without a flag the host offers all of its tuples, IR 4.0.0 first and Ion
  // first in each version, though the extension declares JSON first.
  guard extension_compile_offer(model, None, None).offer is Model(tuples) else {
    fail("no model offer")
  }
  assert_eq(tuples.map(tuple => (tuple.ir_version, tuple.codec)), [
    (V4_0_0, IonBinary),
    (V4_0_0, MorphirJson),
    (V3_0_0, IonBinary),
    (V3_0_0, MorphirJson),
  ])
  // --model-format narrows the offer to the tuples of that format.
  guard extension_compile_offer(model, Some(MorphirJson), None).offer
    is Model(tuples) else {
    fail("no model offer")
  }
  assert_eq(tuples.map(tuple => (tuple.profile, tuple.ir_version)), [
    (MorphirIr, V4_0_0),
    (MorphirIr, V3_0_0),
  ])
  guard extension_compile_offer(model, Some(IonBinary), None).offer
    is Model(tuples) else {
    fail("no model offer")
  }
  assert_eq(tuples.map(tuple => (tuple.profile, tuple.ir_version)), [
    (MorphirModel, V4_0_0),
    (MorphirModel, V3_0_0),
  ])
  // --ir-version narrows it to that version, and the flags intersect.
  let ir4 = Some(@worker.IrVersionName::parse("4"))
  guard extension_compile_offer(model, None, ir4).offer is Model(tuples) else {
    fail("no model offer")
  }
  assert_eq(tuples.map(tuple => tuple.codec), [IonBinary, MorphirJson])
  assert_true(tuples.iter().all(tuple => tuple.ir_version is V4_0_0))
  guard extension_compile_offer(model, Some(MorphirJson), ir4).offer
    is Model(tuples) else {
    fail("no model offer")
  }
  assert_eq(tuples.map(tuple => (tuple.codec, tuple.ir_version)), [
    (MorphirJson, V4_0_0),
  ])
  // This extension claims IR 4.0.0 only, and no legacy compile: no line serves
  // IR 3.
  let refusal = try {
    ignore(
      extension_compile_offer(
        model,
        None,
        Some(@worker.IrVersionName::parse("3")),
      ),
    )
    None
  } catch {
    ExtensionError(status~, code~, ..) =>
      Some((status.exit_code(), code.name()))
    _ => None
  }
  assert_eq(refusal, Some((2, "extension.tuple_unavailable")))
}

///|
fn extension_test_version(
  claimed : Array[String],
  selected : String,
) -> Result[String?, String] {
  try
    extension_ir_version(
      @worker.Claims::from_describe(extension_test_claims()),
      claimed.map(name => @worker.IrVersionName::parse(name)),
      if selected == "" {
        None
      } else {
        Some(@worker.IrVersionName::parse(selected))
      },
    )
  catch {
    ExtensionError(code~, ..) => Err(code.name())
    _ => Err("other")
  } noraise {
    version => Ok(version)
  }
}

///|
test "--ir-version takes an exact claimed version, and the highest one for a major" {
  // An exact claimed name comes first, also among versions of one major.
  assert_eq(
    extension_test_version(["4.0.0", "4.1.0"], "4.1.0"),
    Ok(Some("4.1.0")),
  )
  assert_eq(
    extension_test_version(["4.0.0", "4.1.0"], "4.0.0"),
    Ok(Some("4.0.0")),
  )
  assert_eq(extension_test_version(["3", "4"], "4"), Ok(Some("4")))
  // A full version that is not claimed is refused, even when its major is.
  assert_eq(
    extension_test_version(["4.0.0", "4.1.0"], "4.2.0"),
    Err("extension.capability_unavailable"),
  )
  assert_eq(
    extension_test_version(["4"], "4.0.0"),
    Err("extension.capability_unavailable"),
  )
  // A major-only name selects the highest claimed version with that major,
  // ordered by number.
  assert_eq(extension_test_version(["3", "4.0.0"], "4"), Ok(Some("4.0.0")))
  assert_eq(extension_test_version(["4.0.0", "4.1.0"], "4"), Ok(Some("4.1.0")))
  assert_eq(
    extension_test_version(["4.1.0", "4.10.0", "4.9.0"], "4"),
    Ok(Some("4.10.0")),
  )
  assert_eq(extension_test_version(["4.1", "4.0.0"], "4"), Ok(Some("4.1")))
  assert_eq(
    extension_test_version(["3"], "4"),
    Err("extension.capability_unavailable"),
  )
  assert_eq(extension_test_version(["3"], ""), Ok(Some("3")))
  assert_eq(extension_test_version([], ""), Ok(None))
}

///|
test "document identities keep relative nesting and never expose absolute host paths" {
  assert_eq(extension_document_uri("src/main.mbt"), "src/main.mbt")
  assert_eq(extension_document_uri("/home/user/src/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("../src/main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("C:\\work\\main.mbt"), "main.mbt")
  assert_eq(extension_document_uri("./main.mbt"), "main.mbt")
}

///|
test "extension results publish only intact models and confined artifacts" {
  let bytes = b"\xe0\x01\x00\xea"
  let tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirModel,
    IonBinary,
    V0_1_0Draft1,
    V4_0_0,
  )
  let result : Json = {
    "success": true,
    "model": {
      "envelopeVersion": "0.1.0-draft.1",
      "irVersion": "4.0.0",
      "profile": "morphir-model",
      "payload": {
        "codec": "ion-binary",
        "decodedByteLength": 4,
        "sha256": extension_sha256(bytes),
        "content": @base64.encode(bytes[:]),
      },
    },
  }
  assert_eq(extension_model_bytes(result, tuple).1, bytes)
  let json_tuple = @worker.ModelTuple::new(
    CompileModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  assert_true(
    try {
      ignore(extension_model_bytes(result, json_tuple))
      false
    } catch {
      _ => true
    },
  )
  let tampered = result
    .stringify()
    .replace(old="\"decodedByteLength\":4", new="\"decodedByteLength\":5")
  assert_eq(
    try {
      ignore(extension_model_bytes(@json.parse(tampered), tuple))
      ""
    } catch {
      ExtensionError(code~, ..) => code.name()
      _ => "other"
    },
    "extension.result_invalid",
  )
  let artifact = fn(path : String) -> Json {
    {
      "success": true,
      "artifacts": [{ "path": path, "content": "x", "binary": false }],
    }
  }
  assert_eq(
    extension_artifacts(artifact("mep/source.json"))[0].0,
    "mep/source.json",
  )
  for path in ["../escape", "/abs", "a//b", "a\\b", "c:x", "./a"] {
    assert_true(
      try {
        ignore(extension_artifacts(artifact(path)))
        false
      } catch {
        _ => true
      },
      msg=path,
    )
  }
  let collision : Json = {
    "artifacts": [
      { "path": "a", "content": "x", "binary": false },
      { "path": "a/b", "content": "y", "binary": false },
    ],
  }
  assert_true(
    try {
      ignore(extension_artifacts(collision))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "extension command syntax keeps its own options" {
  let cli = parse_cli([
    "extension", "compile", "src/main.mbt", "--extension-pin", "pin.json", "--package",
    "my/pkg", "--output", "out", "--ir-version", "4", "--model-format", "json", "--json",
  ])
  assert_eq(cli.command, "extension compile")
  assert_eq(value(cli, "path"), "src/main.mbt")
  assert_eq(value(cli, "ir-version"), "4")
  assert_true(flag(cli, "json"))
  let cli = parse_cli([
    "extension", "compile", "src", "--extension-pin", "pin.json", "--package", "my/pkg",
    "--output", "out", "--language", "gleam", "--source-base", "/work/shop",
  ])
  assert_eq(value(cli, "language"), "gleam")
  assert_eq(value(cli, "source-base"), "/work/shop")
  for
    args in [
      ["extension", "describe", "--package", "x"],
      ["extension"],
      ["extension", "describe", "--services-pin", "pin.json"],
      ["extension", "describe", "--language", "gleam"],
      ["extension", "generate", "model.json", "--source-base", "."],
    ] {
    assert_true(
      try {
        ignore(parse_cli(args))
        false
      } catch {
        _ => true
      },
      msg=args.join(" "),
    )
  }
}

///|
test "a write that fails partway through leaves no staging directory" {
  let root = @platform.temporary()
  let output = root + "/out"
  let files : Array[(String, Bytes)] = [
    ("a/first.txt", b"first"),
    ("b/c/second.txt", b"second"),
    ("third.txt", b"third"),
  ]
  // The writer creates the second file, writes part of it and fails.
  let failed = try {
    ignore(
      extension_publish(output, files, write=(path, bytes) => {
        if path.has_suffix("second.txt") {
          @platform.write_bytes(path, bytes[:2].to_owned())
          raise @config.Invalid("the disk is full")
        }
        @platform.write_bytes(path, bytes)
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(@platform.kind(output + ".morphir-partial"), 0)
  assert_eq(@platform.kind(output), 0)
  // A real write failure after an earlier file: a name that is too long.
  let refused = try {
    ignore(
      extension_publish(output, [
        ("a/first.txt", b"first"),
        ("a/" + "n".repeat(300), b"long"),
      ]),
    )
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_eq(@platform.kind(output + ".morphir-partial"), 0)
  assert_eq(@platform.kind(output), 0)
  @platform.remove_dir(root)
}

///|
fn extension_test_artifacts(paths : Array[String]) -> String {
  let result : Json = {
    "success": true,
    "artifacts": Json::array(
      paths.map(path => { "path": path, "content": "x", "binary": false }),
    ),
  }
  try {
    ignore(extension_generated(result))
    "published"
  } catch {
    ExtensionError(code~, ..) => code.name()
  }
}

///|
test "artifact paths that collide by case, by Unicode form or as a file and a directory are refused" {
  for
    paths in [
      ["Readme.md", "README.md"],
      // U+00E9 and e with U+0301 are the same name in NFC.
      ["caf\u00e9.txt", "cafe\u0301.txt"],
      ["Caf\u00e9.txt", "CAFE\u0301.TXT"],
      // A file and a directory of the same name, by case.
      ["docs", "Docs/index.md"],
      ["src/Main", "src/main/lib.mbt"],
      // The exact clashes stay refused.
      ["a", "a/b"],
      ["a/b", "a/b"],
    ] {
    assert_eq(
      extension_test_artifacts(paths),
      "extension.result_invalid",
      msg=paths.join(" "),
    )
  }
  assert_eq(
    extension_test_artifacts(["a/b.txt", "a/c.txt", "b.txt", "a.txt"]),
    "published",
  )
}

///|
test "the output's parent directory is found for each path form" {
  assert_eq(output_parent("out"), ".")
  assert_eq(output_parent("work/out"), "work")
  assert_eq(output_parent("/out"), "/")
  assert_eq(output_parent("/work/model/out"), "/work/model")
  assert_eq(output_parent("C:\\out"), "C:\\")
  assert_eq(output_parent("C:\\work\\out"), "C:\\work")
}

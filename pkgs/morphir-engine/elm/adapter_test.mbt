///|
let api_elm : String = "module My.Pkg.Api exposing (blank, total)\n\nimport My.Pkg.Sig exposing (Amount)\nimport My.Pkg.Util as U\n\n\nblank : Amount -> Bool\nblank a =\n    a == \"\"\n\n\ntotal : Int\ntotal =\n    U.one + 1\n"

///|
let util_elm : String = "module My.Pkg.Util exposing (one)\n\n\none : Int\none =\n    1\n"

///|
let sig_elm : String = "module My.Pkg.Sig exposing (Amount)\n\n\ntype alias Amount =\n    String\n"

///|
fn elm_files(
  exposed~ : String = "[\"Api\"]",
  util~ : String = util_elm,
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.json",
      "{\"name\":\"My.Pkg\",\"sourceDirectory\":\"src\",\"exposedModules\":" +
      exposed +
      "}",
    ),
    ("src/My/Pkg/Api.elm", api_elm),
    ("src/My/Pkg/Util.elm", util),
    ("src/My/Pkg/Sig.elm", sig_elm),
    ("src/notes.md", "# Not Elm"),
  ])
}

///|
/// The files of `elm_files` with a `morphir.toml` project file, for the tests that check TOML behaviour.
/// `exposed` is a TOML line for the project table.
fn toml_files(
  exposed~ : String = "\nexposed_modules=['Api']",
) -> Map[String, String] {
  let files = elm_files()
  files.remove("morphir.json")
  files["morphir.toml"] = "[project]\nname='My.Pkg'" +
    exposed +
    "\n[frontend]\nlanguage='elm'\n[pipeline]\nbackend='checkpoint'\nvalidation='source-only'"
  files
}

///|
/// Runs `files` through the engine with the Elm provider. A `backend` and a `format` (the checkpoint format) go in
/// the request overlay; without them the project file decides.
fn elm_report(
  files : Map[String, String],
  backend~ : String = "",
  format~ : String = "",
  profile~ : String = "",
) -> @engine.ContentReport raise {
  let engine = @engine.Engine::new()..register_source_provider(
    @adapter.provider(),
  )
  let host = @engine.Host::memory(files)
  let profile_table = if profile == "" {
    ""
  } else {
    "[frontend]\nprofile='\{profile}'\n"
  }
  let overlay = if backend == "" && profile == "" {
    @config.empty()
  } else if backend == "" {
    @config.parse(profile_table)
  } else {
    let format_line = if format == "" {
      ""
    } else {
      "\ncheckpoint_format='\{format}'"
    }
    "\{profile_table}[pipeline]\nbackend='\{backend}'\nvalidation='source-only'\{format_line}"
    |> @config.parse()
  }
  let plan = engine.plan(
    host,
    @workspace.discover({ files, directories: ["", "src"], }),
    { ..@engine.Request::new(), overlay, },
  )
  engine.execute_content(plan, fn(path, _) raise {
    @data.Text((host.read)(path))
  })
}

///|
fn messages(report : @engine.ContentReport) -> String {
  report.diagnostics
  .map(d => d.path + " [" + d.stage + "] " + d.message)
  .join("\n")
}

///|
test "the provider offers Elm projects" {
  let provider = @adapter.provider()
  assert_eq(provider.id.to_string(), "finos/morphir-elm")
  let language = provider.languages[0]
  assert_eq(
    (
      language.id.to_string(),
      language.extensions.map(e => e.to_string()),
      language.default_profile.to_string(),
    ),
    ("elm", [".elm"], "library"),
  )
  assert_true(language.profiles[0].compile is @engine.PerProject(_))
  // The Elm provider has no document limit; the output budget bounds the unit.
  assert_eq(language.profiles[0].capabilities.max_documents, None)
}

///|
test "an Elm project compiles to one checkpoint unit with the modules it names" {
  let report = elm_report(
    elm_files(),
    backend="checkpoint",
    format="ion-binary",
  )
  if !report.successful() {
    fail(messages(report))
  }
  assert_eq(report.processed, 1)
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "my/pkg",
    content: report.artifacts[0].content,
  })
  guard unit.distribution.distribution is Library(_, _, def) else {
    fail("library")
  }
  let modules = def.modules.keys().map(k => k.to_canonical()).collect()
  modules.sort()
  // `Sig` is named only in a signature: the `Referenced` output keeps it.
  assert_eq(modules, ["api", "sig", "util"])
}

///|
test "Elm problems are diagnostics at their files" {
  let report = elm_report(
    elm_files(
      util="module My.Pkg.Util exposing (one)\n\n\none : Int\none =\n    missing\n",
    ),
  )
  assert_eq(report.diagnostics.length(), 1, msg=messages(report))
  let d = report.diagnostics[0]
  assert_eq((d.path, d.stage), ("src/My/Pkg/Util.elm", "frontend"))
  assert_true(d.message.has_prefix("elm.unresolved_name: "), msg=d.message)
  assert_true(
    d.message.contains(
      "[provider finos/morphir-elm; profile library] at 6:5-6:12",
    ),
    msg=d.message,
  )
}

///|
test "a project without exposed modules reports elm.exposed_module" {
  let report = elm_report(toml_files(exposed=""))
  assert_eq(report.diagnostics.map(d => d.path), ["src"])
  assert_true(report.diagnostics[0].message.has_prefix("elm.exposed_module: "))
}

///|
test "review focus 4: an exposed module with the package prefix is a missing module" {
  let report = elm_report(elm_files(exposed="[\"My.Pkg.Api\"]"))
  assert_eq(report.diagnostics.map(d => d.path), ["src/My/Pkg/My/Pkg/Api.elm"])
  assert_true(report.diagnostics[0].message.has_prefix("elm.exposed_module: "))
}

///|
test "Elm generates Elm through the engine, with the signature-only module" {
  let report = elm_report(elm_files(), backend="elm")
  if !report.successful() {
    fail(messages(report))
  }
  let paths = report.artifacts.map(a => a.path)
  assert_true(paths.any(p => p.has_suffix("src/My/Pkg/Api.elm")))
  assert_true(paths.any(p => p.has_suffix("src/My/Pkg/Sig.elm")))
  assert_eq(report.projects[0].build_contract, "elm-package-v1")
}

///|
test "Elm generates MoonBit through the engine" {
  let report = elm_report(elm_files(), backend="moonbit")
  if !report.successful() {
    fail(messages(report))
  }
  assert_eq(report.projects[0].build_contract, "moonbit-library-v1")
}

///|
/// The files of review I1: the exposed `Api` names `Sig.Amount`, so `Sig` is Public. `Sig.g` names `Deep.Box`, and
/// nothing exposed names `Deep`, so `Deep` is Private.
fn private_module_files() -> Map[String, String] {
  let files = elm_files()
  files["src/My/Pkg/Sig.elm"] = "module My.Pkg.Sig exposing (Amount, g)\n\nimport My.Pkg.Deep exposing (Box(..))\n\n\ntype alias Amount =\n    String\n\n\ng : Box -> Int\ng (Box n) =\n    n\n"
  files["src/My/Pkg/Deep.elm"] = "module My.Pkg.Deep exposing (Box(..))\n\n\ntype Box\n    = Box Int\n"
  files
}

///|
test "review I1: a public signature of a Public module names a type of a Private module" {
  let elm = elm_report(private_module_files(), backend="elm")
  if !elm.successful() {
    fail(messages(elm))
  }
  let report = elm_report(private_module_files(), backend="moonbit")
  if !report.successful() {
    fail(messages(report))
  }
  guard report.artifacts.search_by(a => a.path.has_suffix("library.mbt"))
    is Some(i) &&
    report.artifacts[i].content is Text(source) else {
    fail("library.mbt")
  }
  // `Box` is abstract: no visibility modifier, so the constructor is not exported.
  assert_true(source.contains("///|\nenum Box {"), msg=source)
  assert_true(source.contains("pub fn g()"), msg=source)
}

///|
/// A project whose exposed `Api` has `f : Int -> Int`, an `if` with `branches` branches.
fn if_chain_files(branches : Int32) -> Map[String, String] {
  let source = StringBuilder()
  source.write_string(
    "module My.Pkg.Api exposing (f)\n\n\nf : Int -> Int\nf n =\n    if n == 0 then\n        0\n\n",
  )
  for i = 1; i < branches - 1; i = i + 1 {
    source.write_string("    else if n == \{i} then\n        \{i}\n\n")
  }
  source.write_string("    else\n        -1\n")
  Map::from_array([
    (
      "morphir.json", "{\"name\":\"My.Pkg\",\"sourceDirectory\":\"src\",\"exposedModules\":[\"Api\"]}",
    ),
    ("src/My/Pkg/Api.elm", source.to_string()),
  ])
}

///|
test "review I2: the unit limits are the identity limits, which an if with 54 branches exceeds" {
  let language = @adapter.provider().languages[0]
  assert_eq(language.profiles[0].capabilities.limits, {
    "unitBytes": 16 * 1024 * 1024,
    "unitDepth": 128,
    "unitValues": 100000,
  })
  for backend in ["checkpoint", "elm"] {
    let report = elm_report(if_chain_files(53), backend~)
    if !report.successful() {
      fail(backend + ": " + messages(report))
    }
  }
  // Pinned: the depth limit (morphir-ukvn.5.22.3.24). Deeper trees overflow the stack on js and wasm.
  let report = elm_report(if_chain_files(54), backend="checkpoint")
  assert_eq(
    messages(report),
    "src [frontend] data.tree_limit: Depth exceeds the limit of 128",
  )
}

///|
test "review I2: the MoonBit metadata budget stops an if with 45 branches" {
  let report = elm_report(if_chain_files(40), backend="moonbit")
  if !report.successful() {
    fail(messages(report))
  }
  // Pinned: symbols.10n grows with the square of the depth (morphir-ukvn.5.22.3.27).
  assert_eq(
    messages(elm_report(if_chain_files(45), backend="moonbit")),
    "src [backend] moonbit.byte_limit at my/pkg: Generated artifacts exceed the byte budget",
  )
}

///|
test "the Elm provider is listed as a whole-project language" {
  let engine = @engine.Engine::new()..register_source_provider(
    @adapter.provider(),
  )
  let elm = engine.languages().filter(o => o.language.to_string() == "elm")
  assert_eq(elm.length(), 1)
  assert_eq(elm[0].provider.to_string(), "finos/morphir-elm")
  assert_eq(elm[0].profiles.map(p => (p.id.to_string(), p.compile)), [
    ("library", @engine.WholeProject),
    ("library-origins", @engine.WholeProject),
  ])
  assert_eq(elm[0].profiles[0].capabilities.unwrap().max_documents, None)
}

///|
test "a morphir.json project writes its Morphir IR checkpoint as JSON" {
  let report = elm_report(elm_files())
  if !report.successful() {
    fail(messages(report))
  }
  guard report.artifacts.search_by(a => {
      a.path.has_suffix(".morphir/out/compile.dest/my/pkg.json")
    })
    is Some(i) &&
    report.artifacts[i].content is Text(text) else {
    fail(
      "no my/pkg.json checkpoint: " +
      report.artifacts.map(a => a.path).join(", "),
    )
  }
  ignore(@json.parse(text))
}

///|
fn field(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard value.kind() is @ion.Struct(fields) else { fail("Expected a record") }
  for f in fields {
    if f.name().text() == Some(name) {
      return f.value()
    }
  }
  fail("No field " + name)
}

///|
fn text(value : @ion.IonValue, name : String) -> String? raise {
  match field(value, name).kind() {
    @ion.String(s) => Some(s)
    _ => None
  }
}

///|
fn number(value : @ion.IonValue, name : String) -> String? raise {
  match field(value, name).kind() {
    @ion.Int(n) => Some(n.to_string())
    _ => None
  }
}

///|
test "an Elm checkpoint unit carries declaration origins and provenance" {
  let report = elm_report(
    elm_files(),
    backend="checkpoint",
    format="ion-binary",
    profile="library-origins",
  )
  if !report.successful() {
    fail(messages(report))
  }
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "my/pkg",
    content: report.artifacts[0].content,
  })
  let blank = field(unit.metadata[0].data, "declaration")
  guard field(unit.metadata[0].data, "parameters").kind()
    is @ion.List(parameters) else {
    fail("parameters")
  }
  let origin = unit.provenance[0]
  @expect.expect_all(s => {
    s
    .expect(unit.metadata.map(m => m.node_id), label="node ids")
    .to_contain_exactly([
      "value:my/pkg:api#blank", "value:my/pkg:api#total", "value:my/pkg:util#one",
    ])
    s.expect(text(blank, "name"), label="name").to_equal(Some("blank"))
    // Workspace-relative, as the engine reports MoonBit sources, not source-directory-relative.
    s
    .expect(text(blank, "path"), label="path")
    .to_equal(Some("src/My/Pkg/Api.elm"))
    s
    .expect(text(blank, "coordinate_profile"), label="coordinate_profile")
    .to_equal(Some("elm-syntax-position-v1"))
    s
    .expect(number(blank, "start_line"), label="start_line")
    .to_equal(Some("8"))
    s
    .expect(number(blank, "start_column"), label="start_column")
    .to_equal(Some("1"))
    s.expect(parameters, label="parameters").to_have_length(1)
    s
    .expect(text(parameters[0], "name"), label="parameter name")
    .to_equal(Some("a"))
    s.expect(unit.provenance, label="provenance").to_have_length(1)
    s
    .expect(
      origin.annotations().map(a => a.text()),
      label="provenance annotation",
    )
    .to_equal([Some("morphir_elm_frontend")])
    s.expect(text(origin, "language"), label="language").to_equal(Some("elm"))
    s
    .expect(text(origin, "profile"), label="profile")
    .to_equal(Some("library-origins"))
    s
    .expect(text(origin, "parser_version"), label="parser_version")
    .to_equal(Some("0.8.0"))
    s.expect(text(origin, "unit_id"), label="unit_id").to_equal(Some("my/pkg"))
  })
}

///|
test "an Elm project through the scheme backend comments each define with its Elm name and file" {
  let report = elm_report(
    elm_files(),
    backend="scheme",
    profile="library-origins",
  )
  if !report.successful() {
    fail(messages(report))
  }
  guard report.artifacts[0].content is @data.Text(source) else { fail("text") }
  guard report.artifacts[1].content is @data.Binary(bytes) else {
    fail("bytes")
  }
  guard field(@ion_binary.read_binary_value(bytes[:]), "metadata").kind()
    is @ion.List(entries) else {
    fail("metadata")
  }
  @expect.expect_all(s => {
    s.expect(report.warnings.length(), label="warnings").to_equal(0)
    s
    .expect(report.artifacts.map(a => a.format), label="formats")
    .to_contain_exactly(["scheme", "ion-binary"])
    s
    .expect(report.artifacts[0].path, label="scm path")
    .to_end_with("/my/pkg.scm")
    s
    .expect(report.artifacts[1].path, label="sidecar path")
    .to_end_with("/my/pkg.symbols.10n")
    // Paths are workspace-relative, as the engine reports MoonBit sources.
    s
    .expect(source, label="blank comment")
    .to_contain(";; blank (src/My/Pkg/Api.elm:8:1)\n(define r:my/pkg:api#blank")
    s
    .expect(source, label="total comment")
    .to_contain(";; total (src/My/Pkg/Api.elm:13:1)\n")
    s
    .expect(source, label="one comment")
    .to_contain(";; one (src/My/Pkg/Util.elm:5:1)\n")
    s.expect(entries, label="sidecar metadata").to_have_length(3)
  })
}

///|
test "the default Elm profile carries no origins, so a Morphir JSON checkpoint still works" {
  let plain = elm_report(elm_files(), backend="scheme")
  if !plain.successful() {
    fail(messages(plain))
  }
  guard plain.artifacts[0].content is @data.Text(source) else { fail("text") }
  guard plain.artifacts[1].content is @data.Binary(bytes) else { fail("bytes") }
  guard field(@ion_binary.read_binary_value(bytes[:]), "metadata").kind()
    is @ion.List(entries) else {
    fail("metadata")
  }
  let json = elm_report(
    elm_files(),
    backend="checkpoint",
    format="morphir-json",
  )
  let engine = @engine.Engine::new()..register_source_provider(
    @adapter.provider(),
  )
  let elm = engine.languages().filter(o => o.language.to_string() == "elm")
  @expect.expect_all(s => {
    s.expect(source, label="no comments").not().to_contain(";; ")
    s.expect(entries, label="no metadata").to_be_empty()
    s
    .expect(json.diagnostics.length(), label="json checkpoint diagnostics")
    .to_equal(0)
    s
    .expect(elm[0].profiles.map(p => p.id.to_string()), label="profiles")
    .to_contain_exactly(["library", "library-origins"])
    s
    .expect(elm[0].default_profile.map(p => p.to_string()), label="default")
    .to_equal(Some("library"))
  })
}

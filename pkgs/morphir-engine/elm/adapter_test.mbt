///|
let api_elm : String = "module My.Pkg.Api exposing (blank, total)\n\nimport My.Pkg.Sig exposing (Amount)\nimport My.Pkg.Util as U\n\n\nblank : Amount -> Bool\nblank a =\n    a == \"\"\n\n\ntotal : Int\ntotal =\n    U.one + 1\n"

///|
let util_elm : String = "module My.Pkg.Util exposing (one)\n\n\none : Int\none =\n    1\n"

///|
let sig_elm : String = "module My.Pkg.Sig exposing (Amount)\n\n\ntype alias Amount =\n    String\n"

///|
fn elm_files(
  backend : String,
  exposed? : String = "\nexposed_modules=['Api']",
  util? : String = util_elm,
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='My.Pkg'" +
      exposed +
      "\n[frontend]\nlanguage='elm'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
    ),
    ("src/My/Pkg/Api.elm", api_elm),
    ("src/My/Pkg/Util.elm", util),
    ("src/My/Pkg/Sig.elm", sig_elm),
    ("src/notes.md", "# Not Elm"),
  ])
}

///|
fn elm_report(files : Map[String, String]) -> @engine.ContentReport raise {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let host = @engine.Host::memory(files)
  let plan = engine.plan(
    host,
    @workspace.discover({ files, directories: ["", "src"], }),
    @engine.Request::new(),
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
  assert_eq(provider.id, "finos/morphir-elm")
  let language = provider.languages[0]
  assert_eq(
    (language.id, language.extensions, language.default_profile),
    ("elm", [".elm"], "library"),
  )
  assert_true(language.profiles[0].compile is @engine.PerProject(_))
  // The Elm provider has no document limit; the output budget bounds the unit.
  assert_eq(language.profiles[0].capabilities.max_documents, None)
}

///|
test "an Elm project compiles to one checkpoint unit with the modules it names" {
  let report = elm_report(elm_files("checkpoint"))
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
      "checkpoint",
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
  let report = elm_report(elm_files("checkpoint", exposed=""))
  assert_eq(report.diagnostics.map(d => d.path), ["src"])
  assert_true(report.diagnostics[0].message.has_prefix("elm.exposed_module: "))
}

///|
test "review focus 4: an exposed module with the package prefix is a missing module" {
  let report = elm_report(
    elm_files("checkpoint", exposed="\nexposed_modules=['My.Pkg.Api']"),
  )
  assert_eq(report.diagnostics.map(d => d.path), ["src/My/Pkg/My/Pkg/Api.elm"])
  assert_true(report.diagnostics[0].message.has_prefix("elm.exposed_module: "))
}

///|
test "Elm generates Elm through the engine, with the signature-only module" {
  let report = elm_report(elm_files("elm"))
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
  let report = elm_report(elm_files("moonbit"))
  if !report.successful() {
    fail(messages(report))
  }
  assert_eq(report.projects[0].build_contract, "moonbit-library-v1")
}

///|
/// The files of review I1: the exposed `Api` names `Sig.Amount`, so `Sig` is Public. `Sig.g` names `Deep.Box`, and
/// nothing exposed names `Deep`, so `Deep` is Private.
fn private_module_files(backend : String) -> Map[String, String] {
  let files = elm_files(backend)
  files["src/My/Pkg/Sig.elm"] = "module My.Pkg.Sig exposing (Amount, g)\n\nimport My.Pkg.Deep exposing (Box(..))\n\n\ntype alias Amount =\n    String\n\n\ng : Box -> Int\ng (Box n) =\n    n\n"
  files["src/My/Pkg/Deep.elm"] = "module My.Pkg.Deep exposing (Box(..))\n\n\ntype Box\n    = Box Int\n"
  files
}

///|
test "review I1: a public signature of a Public module names a type of a Private module" {
  let elm = elm_report(private_module_files("elm"))
  if !elm.successful() {
    fail(messages(elm))
  }
  let report = elm_report(private_module_files("moonbit"))
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
fn if_chain_files(backend : String, branches : Int) -> Map[String, String] {
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
      "morphir.toml",
      "[project]\nname='My.Pkg'\nexposed_modules=['Api']\n[frontend]\nlanguage='elm'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'",
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
    let report = elm_report(if_chain_files(backend, 53))
    if !report.successful() {
      fail(backend + ": " + messages(report))
    }
  }
  // Pinned: the depth limit (morphir-ukvn.5.22.3.24). Deeper trees overflow the stack on js and wasm.
  let report = elm_report(if_chain_files("checkpoint", 54))
  assert_eq(
    messages(report),
    "src [frontend] data.tree_limit: Depth exceeds the limit of 128",
  )
}

///|
test "review I2: the MoonBit metadata budget stops an if with 45 branches" {
  let report = elm_report(if_chain_files("moonbit", 40))
  if !report.successful() {
    fail(messages(report))
  }
  // Pinned: symbols.10n grows with the square of the depth (morphir-ukvn.5.22.3.27).
  assert_eq(
    messages(elm_report(if_chain_files("moonbit", 45))),
    "src [backend] moonbit.byte_limit at my/pkg: Generated artifacts exceed the byte budget",
  )
}

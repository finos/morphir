///|
fn folder(files : Array[(String, String)]) -> Json {
  @pipeline.execute({
    "operation": "import-folder",
    "files": Json::array(
      files.map(f => {
        ({ "path": Json::string(f.0), "content": Json::string(f.1) } : Json)
      }),
    ),
  })
}

///|
test "workspace folder import preserves binary files and exact text" {
  let reply = @pipeline.execute({
    "operation": "import-folder",
    "files": [
      { "path": "p/morphir.toml", "content": "[workspace]\nmembers=[]\n" },
      { "path": "p/notes.md", "content": "\uFEFFhello\r\n" },
      {
        "path": "p/models/original.ionb",
        "content": { "encoding": "base64", "content": "AP+A" },
      },
    ],
  })
  @expect.expect(reply).to_contain_json({
    "success": true,
    "workspace": {
      "files": {
        "notes.md": "\uFEFFhello\r\n",
        "models/original.ionb": { "encoding": "base64", "content": "AP+A" },
      },
    },
  })
}

///|
test "folder binary encoding must be closed and canonical" {
  let invalid : Array[Json] = [
    { "encoding": "base64", "content": "AP+B=" },
    { "encoding": "base64", "content": "AP+A", "extra": true },
    { "encoding": "hex", "content": "00ff80" },
  ]
  for content in invalid {
    let reply = @pipeline.execute({
      "operation": "import-folder",
      "files": [
        { "path": "p/morphir.toml", "content": "[workspace]\nmembers=[]\n" },
        { "path": "p/models/raw", "content": content },
      ],
    })
    @expect.expect(reply).to_contain_json({
      "success": false,
      "code": "workbench.folder_configuration",
    })
  }
}

///|
test "a morphir.toml monorepo folder keeps real paths and discovers every project" {
  let reply = folder([
    (
      "monorepo/morphir.toml", "[workspace]\nmembers=['packages/*']\n[frontend]\nlanguage='scheme'\n",
    ),
    ("monorepo/packages/core/morphir.toml", "[project]\nname='Core'\n"),
    ("monorepo/packages/core/src/main.scm", "42"),
    (
      "monorepo/packages/utils/morphir.toml", "[project]\nname='Utils'\n[frontend]\nlanguage='moonbit'\n",
    ),
    ("monorepo/packages/utils/lib/main.mbt", "pub fn value() -> Int { 42 }"),
    ("monorepo/notes.md", "Keep this too"),
  ])
  @expect.expect(reply).to_contain_json({
    "success": true,
    "workspace": {
      "files": {
        "notes.md": "Keep this too",
        "packages/core/src/main.scm": "42",
      },
    },
    "discovery": { "projects": [{ "name": "Core" }, { "name": "Utils" }] },
  })
}

///|
/// Whether the reply's project loads through the editor's request loader.
fn loads(reply : Json) -> Bool {
  match reply {
    Object(r) =>
      match r.get("project") {
        Some(project) =>
          try {
            ignore(@project.Project::from_request(project))
            true
          } catch {
            _ => false
          }
        None => false
      }
    _ => false
  }
}

///|
let manifest : String = "{\"name\":\"Shop.Orders\",\"sourceDirectory\":\"elm-src\",\"exposedModules\":[\"Api\"],\"dependencies\":[\"x\"]}"

///|
test "a morphir.json folder becomes an Elm project under src/" {
  let reply = folder([
    ("shop/morphir.json", manifest),
    (
      "shop/elm-src/Shop/Orders/Api.elm", "module Shop.Orders.Api exposing (..)\n",
    ),
    ("shop/elm-src/Shop/Orders/notes.txt", "skip"),
    ("shop/tests/Spec.elm", "skip"),
  ])
  @expect.expect_all(s => {
    let r = s.expect(reply, label="reply")
    r.to_contain_json({
      "success": true,
      "project": {
        "name": "Shop.Orders",
        "languageId": "elm",
        "exposedModules": ["Api"],
        "files": [{ "path": "src/Shop/Orders/Api.elm" }],
      },
      "skipped": 2,
    })
    s.expect(loads(reply), label="loads as a project").to_be_true()
    s
    .expect(reply.stringify(), label="warning")
    .to_contain("Ignoring morphir.json dependencies")
  })
}

///|
test "a folder without morphir.json, without sources, or too large is refused" {
  let big = Array::makei(2001, i => ("p/src/M\{i}.elm", ""))
  big.push(("p/morphir.json", manifest))
  @expect.expect_all(s => {
    for
      case in [
        ([("p/src/A.elm", "")], "workbench.folder_without_morphir_json"),
        (
          [("p/morphir.json", manifest), ("p/src/A.elm", "")],
          "workbench.folder_without_sources",
        ),
        (
          [
            (
              "p/morphir.json", "{\"name\":\"A\",\"exposedModules\":[\"Bad Name\"]}",
            ),
            ("p/src/A.elm", ""),
          ],
          "workbench.folder_configuration",
        ),
        (
          [("p/morphir.json", "{\"name\":\"A\"}")],
          "workbench.folder_configuration",
        ),
        (
          [
            ("p/morphir.json", "{\"name\":\"A\\\"B\",\"exposedModules\":[]}"),
            ("p/src/A.elm", ""),
          ],
          "workbench.folder_configuration",
        ),
        (big, "workbench.folder_too_large"),
      ] {
      let (files, code) = case
      let reply = folder(files)
      s.expect(reply.stringify(), label=code).to_contain("\"success\":false")
      s
      .expect(reply, label=code)
      .to_contain_json({ "code": code, "stage": "import" })
    }
  })
}

///|
/// Property: every kept file is the re-rooted copy of a source file with the same content, and nothing outside
/// the source directory is kept.
test "import keeps exactly the Elm files of the source directory" {
  @expect.for_all(
    (shape : Array[(UInt32, Bool)]) => {
      let files = [("p/morphir.json", manifest)]
      for i, item in shape {
        let (n, inside) = item
        let dir = if inside { "p/elm-src/Shop/Orders/" } else { "p/other/" }
        files.push((dir + "M\{n % 20}x\{i}.elm", "-- \{i}"))
      }
      guard shape.iter().any(item => item.1) else { return }
      let reply = folder(files)
      let kept : Array[(String, String)] = match reply {
        Object(r) =>
          match r.get("project") {
            Some(Object(p)) =>
              match p.get("files") {
                Some(Array(fs)) =>
                  fs.filter_map(f => {
                    match f {
                      Object(o) =>
                        match (o.get("path"), o.get("content")) {
                          (Some(String(path)), Some(String(content))) =>
                            Some((path, content))
                          _ => None
                        }
                      _ => None
                    }
                  })
                _ => []
              }
            _ => []
          }
        _ => []
      }
      let expected = files
        .filter(f => f.0.has_prefix("p/elm-src/"))
        .map(f => {
          ("src/" + f.0.unsafe_substring(start=10, end=f.0.length()), f.1)
        })
      @expect.expect(kept, label="kept").to_equal_ignoring_order(expected)
      @expect.expect(loads(reply), label="loads").to_be_true()
    },
    count=40,
  )
}

///|
test "a source directory is normalised and an invalid path is skipped with a warning" {
  let dotted = "{\"name\":\"Shop.Orders\",\"sourceDirectory\":\"./elm-src/\",\"exposedModules\":[]}"
  let reply = folder([
    ("p/morphir.json", dotted),
    ("p/elm-src/A.elm", "-- a"),
    ("p/elm-src/../x.elm", "-- x"),
  ])
  @expect.expect_all(s => {
    s
    .expect(reply, label="reply")
    .to_contain_json({
      "success": true,
      "project": { "files": [{ "path": "src/A.elm" }] },
      "skipped": 1,
    })
    s
    .expect(reply.stringify(), label="warning")
    .to_contain("not a valid source path")
    s.expect(loads(reply), label="loads").to_be_true()
  })
}

///|
fn refused(f : () -> @project.Project raise @project.ProjectError) -> Bool {
  try {
    ignore(f())
    false
  } catch {
    @project.ProjectError(_, _) => true
  }
}

///|
test "a project round-trips through the storage format" {
  let project = shop().add_file(elm_rules(), "src/Shop/Orders/Util.elm")
  @expect.expect_all(s => {
    s
    .expect(@project.Project::from_json(project.to_json()), label="round trip")
    .to_equal(project)
    s
    .expect(project.to_json(), label="shape")
    .to_contain_json({
      "version": 1,
      "name": "Shop.Orders",
      "languageId": "elm",
      "exposedModules": ["Api"],
      "active": "src/Shop/Orders/Util.elm",
    })
  })
}

///|
test "the worker request has the Plan B project shape" {
  @expect.expect(shop().to_request(), label="request").to_contain_json({
    "name": "Shop.Orders",
    "languageId": "elm",
    "exposedModules": ["Api"],
    "files": [
      {
        "path": "src/Shop/Orders/Api.elm",
        "content": "module Shop.Orders.Api exposing (..)\n",
      },
    ],
  })
}

///|
test "stored text that is not a valid project is refused" {
  let bad : Array[Json] = [
    {
      "version": 2,
      "name": "A",
      "languageId": "elm",
      "files": [],
      "active": "src/A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [],
      "active": "src/A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [{ "path": "../A.elm", "content": "" }],
      "active": "../A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [{ "path": "src/A.elm", "content": "" }],
      "active": "src/B.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [
        { "path": "src/A.elm", "content": "" },
        { "path": "src/A.elm", "content": "" },
      ],
      "active": "src/A.elm",
    },
    Json::string("not an object"),
  ]
  @expect.expect_all(s => {
    for json in bad {
      s
      .expect(
        refused(() => @project.Project::from_json(json)),
        label=json.stringify(),
      )
      .to_be_true()
    }
  })
}

///|
test "a sample asset and its index parse" {
  let sample = @project.Sample::from_json({
    "version": 1,
    "id": "examples-tutorial",
    "title": "Rentals tutorial",
    "languageId": "elm",
    "notice": "From finos/morphir-examples, Apache-2.0.",
    "project": shop().to_json(),
  })
  @expect.expect_all(s => {
    s.expect(sample.id, label="id").to_equal("examples-tutorial")
    s.expect(sample.project, label="project").to_equal(shop())
    s
    .expect(
      @project.sample_index({
        "version": 1,
        "samples": [{ "id": "a", "title": "A" }],
      }),
      label="index",
    )
    .to_equal([("a", "A")])
  })
}

///|
test "problem counts come from frontendDiagnostics" {
  let counts = @project.problem_counts({
    "success": false,
    "frontendDiagnostics": [
      { "path": "src/A.elm", "problems": [{ "code": "x" }, { "code": "y" }] },
      { "path": "src/B.elm", "problems": [{ "code": "z" }] },
    ],
  })
  @expect.expect(counts, label="counts").to_equal({
    "src/A.elm": 2,
    "src/B.elm": 1,
  })
}

///|
/// Property: any project built from generated file names round-trips through storage and through the request
/// format (where the request keeps the files, the name and the exposed modules).
test "projects round-trip through storage and requests" {
  @expect.for_all(
    (names : Array[UInt32]) => {
      let mut project = shop()
      for n in names {
        project = project.add_file(
          elm_rules(),
          "src/Shop/Orders/M\{n % 50}.elm",
        ) catch {
          _ => project
        }
      }
      let back = @project.Project::from_request(project.to_request())
      @expect.expect_all(s => {
        s
        .expect(@project.Project::from_json(project.to_json()), label="storage")
        .to_equal(project)
        s.expect(back.files, label="request files").to_equal(project.files)
        s
        .expect(back.exposed, label="request exposed")
        .to_equal(project.exposed)
        s.expect(back.name, label="request name").to_equal(project.name)
      })
    },
    count=50,
  )
}

///|
fn valid_json() -> Json {
  shop().add_file(elm_rules(), "src/Shop/Orders/Util.elm").to_json() catch {
    _ => abort("valid project")
  }
}

///|
fn with_field(json : Json, key : String, value : Json?) -> Json {
  match json {
    Object(fields) => {
      let copy : Map[String, Json] = Map(fields.to_array())
      match value {
        Some(v) => copy[key] = v
        None => copy.remove(key)
      }
      Json::object(copy)
    }
    other => other
  }
}

///|
fn with_files(json : Json, key : String, value : Json?) -> Json {
  match json {
    Object(fields) =>
      match fields.get("files") {
        Some(Array(items)) if items.length() > 0 => {
          let files = items.copy()
          files[0] = with_field(files[0], key, value)
          with_field(json, "files", Some(Json::array(files)))
        }
        _ => json
      }
    other => other
  }
}

///|
fn loaded(json : Json) -> Result[@project.Project, String] {
  Ok(@project.Project::from_json(json)) catch {
    @project.ProjectError(code, _) => Err(code)
  }
}

///|
fn load_code(json : Json) -> String {
  try {
    ignore(@project.Project::from_json(json))
    ""
  } catch {
    @project.ProjectError(code, _) => code
  }
}

///|
test "each malformed field is refused with workbench.invalid_project" {
  let cases : Array[(String, Json)] = [
    ("missing name", with_field(valid_json(), "name", None)),
    ("unsafe name", with_field(valid_json(), "name", Some("a\"b"))),
    (
      "bad languageId",
      with_field(valid_json(), "languageId", Some("Not Valid")),
    ),
    ("non-number version", with_field(valid_json(), "version", Some("1"))),
    ("non-text content", with_files(valid_json(), "content", Some(5))),
    ("missing content", with_files(valid_json(), "content", None)),
    (
      "non-array exposedModules",
      with_field(valid_json(), "exposedModules", Some("Api")),
    ),
    (
      "non-text exposedModules",
      with_field(valid_json(), "exposedModules", Some([1])),
    ),
    (
      "bad frontendProvider",
      with_field(valid_json(), "frontendProvider", Some("")),
    ),
    (
      "non-text frontendProvider",
      with_field(valid_json(), "frontendProvider", Some(1)),
    ),
    (
      "bad frontendProfile",
      with_field(valid_json(), "frontendProfile", Some("Bad Id")),
    ),
    ("item not an object", with_field(valid_json(), "files", Some(["x"]))),
    ("files not an array", with_field(valid_json(), "files", Some("x"))),
    ("missing active", with_field(valid_json(), "active", None)),
  ]
  @expect.expect_all(s => {
    for c in cases {
      s.expect(load_code(c.1), label=c.0).to_equal("workbench.invalid_project")
    }
  })
}

///|
test "stored exposure keeps only modules that files have, once" {
  let loaded = @project.Project::from_json(
    with_field(valid_json(), "exposedModules", Some(["Api", "Api", "Ghost"])),
  )
  @expect.expect(loaded.exposed.map(m => m.to_string()), label="exposed").to_equal([
      "Api",
    ],
  )
}

///|
fn replacement(kind : UInt32, text : String, n : Int32) -> Json? {
  match kind % 7 {
    0 => None
    1 => Some(Json::null())
    2 => Some(Json::number(n.to_double()))
    3 => Some(Json::boolean(n % 2 == 0))
    4 => Some(Json::string(text))
    5 => Some(Json::array([Json::string(text), Json::number(n.to_double())]))
    _ =>
      Some(
        Json::object({ "path": Json::string(text), "content": Json::null() }),
      )
  }
}

///|
/// Property: starting from a valid stored project, dropping or replacing any one field with any JSON value either
/// loads a project that keeps the invariants or raises a ProjectError; it never aborts.
test "a mutated stored project loads consistently or is refused" {
  @expect.for_all(
    (input : (UInt32, UInt32, String, Int32)) => {
      let (field, kind, text, n) = input
      let value = replacement(kind, text, n)
      let json = match field % 10 {
        0 => with_field(valid_json(), "version", value)
        1 => with_field(valid_json(), "name", value)
        2 => with_field(valid_json(), "languageId", value)
        3 => with_field(valid_json(), "frontendProvider", value)
        4 => with_field(valid_json(), "frontendProfile", value)
        5 => with_field(valid_json(), "exposedModules", value)
        6 => with_field(valid_json(), "files", value)
        7 => with_field(valid_json(), "active", value)
        8 => with_files(valid_json(), "path", value)
        _ => with_files(valid_json(), "content", value)
      }
      match loaded(json) {
        Ok(project) => {
          let paths = project.files.map(f => f.path.to_string())
          let modules = project.modules().map(m => m.0)
          @expect.expect_all(s => {
            s.expect(paths, label="files").not().to_be_empty()
            s.expect(paths, label="unique").to_have_no_duplicates()
            s
            .expect(paths, label="active")
            .to_contain_element(project.active.to_string())
            s
            .expect(project.exposed, label="exposed")
            .to_all_satisfy(e => modules.contains(e))
          })
        }
        Err(code) =>
          @expect.expect(code, label="code").to_equal(
            "workbench.invalid_project",
          )
      }
    },
    count=300,
  )
}

///|
/// The asset `assets/samples/elm/records.json`, as scripts/workbench-samples.mbtx writes it. The test pins the format.
let records_asset : String =
  #|{
  #|  "version": 1,
  #|  "id": "records",
  #|  "title": "Records (parity corpus)",
  #|  "languageId": "elm",
  #|  "notice": "From this repository's Elm parity corpus. Apache-2.0.",
  #|  "project": {
  #|    "version": 1,
  #|    "name": "Parity.Records",
  #|    "languageId": "elm",
  #|    "exposedModules": [
  #|      "Points"
  #|    ],
  #|    "files": [
  #|      {
  #|        "path": "src/Parity/Records/Points.elm",
  #|        "content": "module Parity.Records.Points exposing (Point, origin, make, partial, getX, xs, moveArg, moveTop, readX)\n\n{-| Record literals, alias constructors, field access and record updates. -}\n\n\ntype alias Point =\n    { x : Int, y : Int }\n\norigin : Point\norigin =\n    { y = 0, x = 0 }\n\nmake : Point\nmake =\n    Point 1 2\n\npartial : Int -> Point\npartial =\n    Point 1\n\ngetX : Point -> Int\ngetX p =\n    p.x\n\nxs : List Point -> List Int\nxs points =\n    List.map .x points\n\nmoveArg : Point -> Point\nmoveArg p =\n    { p | x = 1 }\n\nmoveTop : Point\nmoveTop =\n    { origin | x = 1, y = 2 }\n\nreadX : { a | x : Int } -> Int\nreadX r =\n    r.x\n"
  #|      }
  #|    ],
  #|    "active": "src/Parity/Records/Points.elm"
  #|  }
  #|}

///|
test "the generated records sample parses" {
  let json = @json.parse(records_asset) catch { _ => abort("records asset") }
  let sample = @project.Sample::from_json(json) catch {
    _ => abort("records sample")
  }
  @expect.expect_all(s => {
    s.expect(sample.id, label="id").to_equal("records")
    s.expect(sample.notice, label="notice").to_contain("Apache-2.0")
    s
    .expect(sample.project.active.to_string(), label="active")
    .to_equal("src/Parity/Records/Points.elm")
    s
    .expect(sample.project.files.map(f => f.path.to_string()), label="files")
    .to_equal(["src/Parity/Records/Points.elm"])
    s
    .expect(sample.project.exposed.map(m => m.to_string()), label="exposed")
    .to_equal(["Points"])
  })
}

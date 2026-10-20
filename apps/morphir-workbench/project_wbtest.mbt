///|
fn offers() -> Array[@engine.LanguageOffer] {
  (workbench_engine() catch { _ => abort("engine") }).languages()
}

///|
/// The message of the error a request raises; `to_raise(containing=)` does not see it for these error types.
fn failure_text(request : Json) -> String {
  try {
    ignore(project_request(request, offers()))
    "<no error>"
  } catch {
    @config.Invalid(message) => message
    @wire.Invalid(code, message) => code + ": " + message
    other => other.to_string()
  }
}

///|
fn paths(project : ProjectRequest) -> Array[String] {
  project.files.map(f => f.path.to_string())
}

///|
test "the Elm module header gives the path, package and exposed module" {
  let source = "-- comment\n{- block {- nested -} -}\nmodule Workbench.Pricing.Main exposing (..)\n\nanswer = 42\n"
  let project = project_request(
    { "languageId": "elm", "source": source },
    offers(),
  )
  @expect.expect_all(s => {
    s
    .expect(elm_module_name(source), label="header")
    .to_equal(Some("Workbench.Pricing.Main"))
    s
    .expect(
      elm_module_name("port module App.Ports exposing (..)"),
      label="port header",
    )
    .to_equal(Some("App.Ports"))
    s.expect(elm_module_name("answer = 42"), label="no header").to_be_none()
    s
    .expect(project.name.to_string(), label="package")
    .to_equal("Workbench.Pricing")
    s
    .expect(project.exposed.map(m => m.to_string()), label="exposed")
    .to_equal(["Main"])
    s
    .expect(paths(project), label="files")
    .to_equal(["src/Workbench/Pricing/Main.elm"])
  })
}

///|
test "an Elm source without a usable module header is refused with a fix" {
  @expect.expect_all(s => {
    for source in ["answer = 42", "module Main exposing (..)\nanswer = 42"] {
      s
      .expect(
        failure_text({ "languageId": "elm", "source": source }),
        label=source,
      )
      .to_contain("Package.Module")
    }
  })
}

///|
test "the source shorthand of other languages is one file in src" {
  let scheme = project_request({ "source": "(+ 1 2)" }, offers())
  let moonbit = project_request(
    {
      "languageId": "moonbit",
      "source": "pub fn t() -> Bool { true }",
      "frontendProfile": "moonbit-model-stable-v1",
    },
    offers(),
  )
  @expect.expect_all(s => {
    s
    .expect(scheme.language.to_string(), label="default language")
    .to_equal("scheme")
    s.expect(scheme.name.to_string(), label="scheme package").to_equal("user")
    s.expect(paths(scheme), label="scheme files").to_equal(["src/main.scm"])
    s.expect(paths(moonbit), label="moonbit files").to_equal(["src/main.mbt"])
    s
    .expect(moonbit.profile.map(p => p.to_string()), label="moonbit profile")
    .to_equal(Some("moonbit-model-stable-v1"))
  })
}

///|
test "a project request keeps its files and writes a morphir.toml" {
  let project = project_request(
    {
      "project": {
        "name": "Shop.Orders",
        "languageId": "elm",
        "exposedModules": ["Api"],
        "files": [
          {
            "path": "src/Shop/Orders/Api.elm",
            "content": "module Shop.Orders.Api exposing (..)\n",
          },
          {
            "path": "src/Shop/Orders/Util.elm",
            "content": "module Shop.Orders.Util exposing (..)\n",
          },
        ],
      },
    },
    offers(),
  )
  let tree = project_tree(project)
  @expect.expect_all(s => {
    s
    .expect(tree.directories, label="directories")
    .to_contain_all(["", "src", "src/Shop", "src/Shop/Orders"])
    s
    .expect(tree.files, label="files")
    .value_at("morphir.toml")
    .all(it => {
      it.to_contain("name = \"Shop.Orders\"")
      it.to_contain("exposed_modules = [\"Api\"]")
      it.to_contain("language = \"elm\"")
    })
  })
}

///|
test "a project with morphir.json keeps it and gets no morphir.toml" {
  let project = project_request(
    {
      "project": {
        "name": "Shop",
        "languageId": "elm",
        "files": [
          {
            "path": "morphir.json",
            "content": "{\"name\":\"Shop\",\"sourceDirectory\":\"src\",\"exposedModules\":[\"Api\"]}",
          },
          {
            "path": "src/Shop/Api.elm",
            "content": "module Shop.Api exposing (..)\n",
          },
        ],
      },
    },
    offers(),
  )
  @expect.expect(project_tree(project).files, label="files")
  .not()
  .to_contain_key("morphir.toml")
}

///|
test "hostile names and paths are refused before any TOML is written" {
  let bad : Array[(Json, String)] = [
    (
      { "project": { "name": "a\"b", "languageId": "elm", "files": [] } },
      "workbench.invalid_package",
    ),
    (
      {
        "project": {
          "name": "Shop",
          "languageId": "elm",
          "files": [{ "path": "../escape.elm", "content": "" }],
        },
      },
      "invalid_source_path",
    ),
    (
      {
        "project": {
          "name": "Shop",
          "languageId": "elm",
          "files": [{ "path": "/abs.elm", "content": "" }],
        },
      },
      "invalid_source_path",
    ),
    (
      {
        "project": {
          "name": "Shop",
          "languageId": "elm",
          "files": [{ "path": "c:\\x.elm", "content": "" }],
        },
      },
      "invalid_source_path",
    ),
    ({ "languageId": "cobol", "source": "x" }, "unavailable"),
  ]
  @expect.expect_all(s => {
    for case in bad {
      let (request, reason) = case
      s
      .expect(failure_text(request), label=request.stringify())
      .to_contain(reason)
    }
    s
    .expect(toml_string("a\"b\\c"), label="escaped")
    .to_equal("\"a\\\"b\\\\c\"")
  })
}

///|
/// Property: any text survives a TOML round trip through `toml_string`, so a value can never add a key.
test "toml_string round-trips any text" {
  @expect.for_all((chars : Array[Char]) => {
    let text = String::from_array(chars)
    let document = @config.parse(
      "[t]\nk = " + toml_string(text) + "\nafter = \"x\"\n",
    )
    @expect.expect(document.text("t.k", "<missing>"), label="value").to_equal(
      text,
    )
    @expect.expect(document.text("t.after", "<missing>"), label="next key").to_equal(
      "x",
    )
  })
}

///|
/// Property: a package name that `project_request` accepts gives a morphir.toml whose project name is that name.
test "an accepted package name round-trips through the generated morphir.toml" {
  @expect.for_all((chars : Array[Char]) => {
    let name = String::from_array(chars)
    let request : Json = {
      "project": { "name": name, "languageId": "elm", "files": [] },
    }
    let project = project_request(request, offers()) catch { _ => return }
    @expect.expect(
      @config.parse(manifest(project)).text("project.name", "<missing>"),
    ).to_equal(name)
  })
}

///|
/// Property: any dotted module name of two or more segments is read back from its header, after any line or
/// block comment.
test "the module header is found after any comment" {
  @expect.for_all((input : (Array[UInt32], Array[Char])) => {
    let (numbers, comment_chars) = input
    guard numbers.length() >= 2 else { return }
    let name = numbers.map(n => "M" + n.to_string()).join(".")
    let comment = String::from_array(
      comment_chars.filter(c => c != '\n' && c != '-' && c != '{' && c != '}'),
    )
    for
      source in [
        "module " + name + " exposing (..)\n",
        "-- " + comment + "\nmodule " + name + " exposing (..)\n",
        "{- " + comment + " -}\nmodule " + name + " exposing (..)\n",
      ] {
      @expect.expect(elm_module_name(source), label=source).to_equal(Some(name))
    }
  })
}

///|
/// Property: the project tree lists `""` and every parent directory of every file, once each.
test "the project tree lists each parent directory once" {
  @expect.for_all((shape : Array[Array[UInt32]]) => {
    let files : Array[Json] = shape
      .filter(segments => !segments.is_empty())
      .map(segments => {
        let path = "src/" +
          segments.map(n => "d" + (n % 3).to_string()).join("/") +
          ".elm"
        ({ "path": path, "content": "" } : Json)
      })
    let project = project_request(
      {
        "project": {
          "name": "Shop",
          "languageId": "elm",
          "files": Json::array(files),
        },
      },
      offers(),
    )
    let tree = project_tree(project)
    @expect.expect(tree.directories, label="directories").all(it => {
      it.to_have_no_duplicates()
      it.to_start_with_elements([""])
    })
    for path, _ in tree.files {
      let parts = path.split("/").map(StringView::to_owned).collect()
      for i in 1..<parts.length() {
        @expect.expect(tree.directories, label=path).to_contain_element(
          parts[:i].to_owned().join("/"),
        )
      }
    }
  })
}

///|
fn provider_offering(
  id : String,
  extension : String,
) -> @engine.SourceProvider raise {
  {
    id: @ids.ProviderId::parse(id),
    languages: [
      {
        id: @ids.LanguageId::parse("rich"),
        extensions: [@ids.FileExtension::parse(extension)],
        default_profile: @ids.ProfileId::parse("basic"),
        profiles: [
          {
            id: @ids.ProfileId::parse("basic"),
            capabilities: {
              summary: "Rich test",
              supported: [],
              excluded: [],
              max_documents: None,
              incremental: false,
              limits: Map([]),
            },
            evidence: @engine.Declared,
            dependencies: Map([]),
            compile: @engine.PerFile(fn(_, id, _) raise {
              @data.IRUnit::new(id, @fixtures.library())
            }),
            unit_limits: @data.Limits::default(),
          },
        ],
      },
    ],
  }
}

///|
test "the source shorthand takes the extension of the requested provider" {
  let engine = @engine.Engine::new()
  engine.register_source_provider(provider_offering("a/first", ".one"))
  engine.register_source_provider(provider_offering("b/second", ".two"))
  let offers = engine.languages()
  let named = project_request(
    { "languageId": "rich", "source": "x", "frontendProvider": "b/second" },
    offers,
  )
  let unnamed = project_request({ "languageId": "rich", "source": "x" }, offers)
  @expect.expect_all(s => {
    s.expect(paths(named), label="named provider").to_equal(["src/main.two"])
    s.expect(paths(unnamed), label="no provider").to_equal(["src/main.one"])
  })
}

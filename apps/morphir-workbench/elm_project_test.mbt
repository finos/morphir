///|
let elm_main : String =
  #|module Shop.Orders.Api exposing (total)
  #|
  #|import Shop.Orders.Util exposing (double)
  #|
  #|total : Int -> Int
  #|total n =
  #|    double n + 1

///|
let elm_util : String =
  #|module Shop.Orders.Util exposing (double)
  #|
  #|double : Int -> Int
  #|double n =
  #|    n * 2

///|
fn elm_project(target : String, util~ : String = elm_util) -> Json {
  @pipeline.execute({
    "operation": "compile",
    "target": target,
    "project": {
      "name": "Shop.Orders",
      "languageId": "elm",
      "exposedModules": ["Api"],
      "files": [
        { "path": "src/Shop/Orders/Api.elm", "content": elm_main },
        { "path": "src/Shop/Orders/Util.elm", "content": util },
      ],
    },
  })
}

///|
test "an Elm project of two files compiles to IR and generates Elm, MoonBit and Scheme" {
  @expect.expect_all(s => {
    for target in ["", "elm", "moonbit", "scheme"] {
      let reply = s.expect(elm_project(target), label="target " + target)
      reply.to_contain_json({ "success": true, "package": "shop/orders" })
      reply
      .get("generationDiagnostics", r => json_member(r, "generationDiagnostics"))
      .to_equal(Json::null())
    }
    let elm = s.expect(elm_project("elm"), label="elm")
    elm
    .get("paths", r => texts(json_member(r, "artifacts")))
    .to_contain_element("elm.json")
    elm
    .at("generated")
    .get("text", g => if g is String(text) { text } else { "" })
    .to_contain("total")
    s
    .expect(elm_project("moonbit"), label="moonbit")
    .get("paths", r => texts(json_member(r, "artifacts")))
    .not()
    .to_be_empty()
    s
    .expect(elm_project("scheme"), label="scheme")
    .get("generated", r => json_member(r, "generated").stringify())
    .to_contain("total")
  })
}

///|
test "a one-module Elm source compiles in the single editor" {
  let reply = @pipeline.execute({
    "operation": "compile",
    "languageId": "elm",
    "target": "elm",
    "source": "module Workbench.Main exposing (answer)\n\nanswer : Int\nanswer =\n    42\n",
  })
  @expect.expect(reply, label="reply").to_contain_json({
    "success": true,
    "sourceProvider": "finos/morphir-elm",
    "sourceProfile": "library",
  })
}

///|
test "an Elm value evaluates from the compiled IR" {
  let compiled = elm_project("")
  let entry = @wire.array(@wire.field(compiled, "nodes")).filter(n => {
    @wire.string(@wire.field(n, "label")).contains("total")
  })
  @expect.expect(entry, label="total node").to_have_length(1)
  let reply = @pipeline.execute({
    "operation": "evaluate",
    "source": @wire.field(compiled, "irSource"),
    "entry": @wire.field(entry[0], "id"),
    "arguments": ["20"],
  })
  @expect.expect_all(s => {
    let r = s.expect(reply, label="evaluation")
    r.at("success").to_equal(true)
    r.at("value").to_equal("41")
  })
}

///|
test "an error in the second file carries that file and its one-based range" {
  let reply = elm_project(
    "",
    util="module Shop.Orders.Util exposing (double)\n\ndouble n =\n    n * \n",
  )
  @expect.expect_all(s => {
    let r = s.expect(reply, label="reply")
    r.at("success").to_equal(false)
    r.at("frontendDiagnostic.path").to_equal("src/Shop/Orders/Util.elm")
    r
    .at("frontendDiagnostics")
    .get("files", j => if j is Array(files) { files.length() } else { 0 })
    .to_equal(1)
    r.at("frontendDiagnostics[0].path").to_equal("src/Shop/Orders/Util.elm")
    r
    .at("frontendDiagnostics[0].problems[0].coordinateProfile")
    .to_equal("elm-source-position-v1")
    r.at("frontendDiagnostics[0].problems[0].source.startLine").to_equal(4)
    r.at("frontendDiagnostics[0].problems[0].source.startColumn").to_equal(8)
    r.at("frontendDiagnostics[0].problems[0].source.endLine").to_equal(4)
    r.at("frontendDiagnostics[0].problems[0].source.endColumn").to_equal(8)
  })
}

///|
fn json_member(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn texts(value : Json) -> Array[String] {
  match value {
    Array(items) =>
      items.filter_map(item => {
        match item {
          String(text) => Some(text)
          Object(fields) =>
            match fields.get("path") {
              Some(String(path)) => Some(path)
              _ => None
            }
          _ => None
        }
      })
    _ => []
  }
}

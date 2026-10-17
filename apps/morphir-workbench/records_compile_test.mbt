///|
/// The Records parity sample: `readX` takes an extensible record, which typed evaluation cannot take.
let records_points : String =
  #|module Parity.Records.Points exposing (Point, origin, make, partial, getX, xs, moveArg, moveTop, readX)
  #|
  #|{-| Record literals, alias constructors, field access and record updates. -}
  #|
  #|
  #|type alias Point =
  #|    { x : Int, y : Int }
  #|
  #|origin : Point
  #|origin =
  #|    { y = 0, x = 0 }
  #|
  #|make : Point
  #|make =
  #|    Point 1 2
  #|
  #|partial : Int -> Point
  #|partial =
  #|    Point 1
  #|
  #|getX : Point -> Int
  #|getX p =
  #|    p.x
  #|
  #|xs : List Point -> List Int
  #|xs points =
  #|    List.map .x points
  #|
  #|moveArg : Point -> Point
  #|moveArg p =
  #|    { p | x = 1 }
  #|
  #|moveTop : Point
  #|moveTop =
  #|    { origin | x = 1, y = 2 }
  #|
  #|readX : { a | x : Int } -> Int
  #|readX r =
  #|    r.x

///|
fn compile_records(target : String) -> Json {
  @pipeline.execute({
    "operation": "compile",
    "target": target,
    "project": {
      "name": "Parity.Records",
      "languageId": "elm",
      "exposedModules": ["Points"],
      "files": [
        { "path": "src/Parity/Records/Points.elm", "content": records_points },
      ],
    },
  })
}

///|
test "a module typed evaluation cannot take still compiles, and keeps the reason" {
  @expect.expect_all(s => {
    for target in ["", "elm", "moonbit", "scheme"] {
      let reply = compile_records(target)
      s
      .expect(reply, label="target " + target)
      .to_contain_json({ "success": true })
      s
      .expect(
        json_member(reply, "sourceEntries"),
        label="no typed entries " + target,
      )
      .to_equal(Json::array([]))
      s
      .expect(
        json_member(json_member(reply, "typedEvaluations"), "reason"),
        label="reason " + target,
      )
      .to_satisfy(reason => reason is String(text) && text != "")
    }
  })
}

///|
fn failed_with_code(reply : Json) -> Bool {
  match
    (
      json_member(reply, "success"),
      json_member(reply, "message"),
      json_member(reply, "code"),
    ) {
    (True, _, _) => true
    (False, String(message), String(code)) => message != "" && code != ""
    _ => false
  }
}

///|
/// Property: whatever the source, a compile reply succeeds, or fails with a message and a code.
test "a failed compile always has a message and a code" {
  @expect.for_all(
    (source : String) => {
      for language in ["elm", "scheme"] {
        let reply = @pipeline.execute({
          "operation": "compile",
          "target": "elm",
          "project": {
            "name": "Shop.Orders",
            "languageId": language,
            "exposedModules": [],
            "files": [
              {
                "path": if language == "elm" {
                  "src/Shop/Orders/Api.elm"
                } else {
                  "src/main.scm"
                },
                "content": source,
              },
            ],
          },
        })
        @expect.expect(
          failed_with_code(reply),
          label=language + ": " + reply.stringify(),
        ).to_be_true()
      }
    },
    count=60,
  )
}

///|
test "a refused request names its code and stage, never a bare key" {
  let missing = @pipeline.execute({ "operation": "compile" })
  let model = @pipeline.execute({ "operation": "inspect", "source": "{}" })
  @expect.expect_all(s => {
    s
    .expect(missing, label="request")
    .to_contain_json({ "success": false, "stage": "request" })
    s.expect(failed_with_code(missing), label="request code").to_be_true()
    s
    .expect(model, label="model")
    .to_contain_json({
      "success": false,
      "code": "workbench.invalid_model",
      "stage": "model",
    })
    s
    .expect(json_member(model, "message"), label="not a bare key")
    .to_satisfy(message => message is String(text) && text.contains(" "))
  })
}

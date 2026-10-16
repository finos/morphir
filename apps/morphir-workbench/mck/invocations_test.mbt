///|
fn invocation_request(
  suite : Json,
  manifest : Json,
  format~ : String = "json",
) -> Json {
  {
    "id": 11,
    "op": "validate-invocations",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.3",
    "format": format,
    "input": { "suite": suite, "manifest": manifest },
  }
}

///|
fn public_manifest(inputs : Json, output~ : Json = { "type": "unit" }) -> Json {
  {
    "entries": [{ "name": "entry", "inputs": inputs, "output": output }],
    "definitions": [],
  }
}

///|
fn invocation_suite(arguments : Json, entry~ : String = "entry") -> Json {
  {
    "profile": "morphir-invocations-v1",
    "calls": [{ "id": "c", "entry": entry, "arguments": arguments }],
  }
}

///|
fn invocation_invalid(code : String) -> Json {
  { "id": 11, "status": "invalid", "code": code }
}

///|
test "draft3 negotiates all admission operations with exact older drafts retained" {
  let capabilities = @mck.handle({
    "id": 11,
    "op": "capabilities",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.3",
  })
  assert_eq(capabilities, {
    "id": 11,
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.3",
    "binding": "morphir-moonbit",
    "language": "moonbit",
    "operations": ["decode-value", "validate-value", "validate-invocations"],
    "formats": ["json", "ion-text"],
  })
  for version in ["0.1.0-draft.1", "0.1.0-draft.2", "0.1.0-draft.6"] {
    let request = invocation_request(invocation_suite([]), public_manifest([]))
    if request is Object(fields) {
      fields["contractVersion"] = Json::string(version)
    }
    assert_eq(
      @mck.handle(request),
      invocation_invalid("workbench.invalid_request"),
    )
  }
}

///|
test "JSON and Ion invocation suites use the shipped exact codec" {
  let canonical = invocation_suite([
    { "type": "int", "value": "9007199254740993" },
  ])
  let manifest = public_manifest([{ "type": "int" }], output={ "type": "int" })
  for
    (format, source) in [
      (
        "json",
        invocation_suite([{ "type": "int", "value": "0009007199254740993" }]),
      ),
      (
        "ion-text",
        Json::string(
          "{profile:\"morphir-invocations-v1\",calls:[{id:\"c\",entry:\"entry\",arguments:[9007199254740993]}]}",
        ),
      ),
    ] {
    assert_eq(@mck.handle(invocation_request(source, manifest, format~)), {
      "id": 11,
      "status": "ok",
      "value": canonical,
    })
  }
}

///|
test "public membership arity and model errors have shared stable rejections" {
  let manifest = public_manifest([{ "type": "unit" }])
  for
    (suite, code) in [
      (
        invocation_suite([{ "type": "unit" }], entry="private"),
        "execution.entry_not_public_or_supported",
      ),
      (invocation_suite([]), "execution.wrong_arity"),
      (
        invocation_suite([{ "type": "bool", "value": false }]),
        "execution.wrong_type",
      ),
      (
        invocation_suite([
          { "type": "model-error", "code": "sdk.division_by_zero" },
        ]),
        "execution.model_error_argument",
      ),
    ] {
    assert_eq(
      @mck.handle(invocation_request(suite, manifest)),
      invocation_invalid(code),
    )
  }
}

///|
test "all manifest output and unused declarations close before suite decoding" {
  for
    (manifest, code) in [
      (
        public_manifest([], output={ "type": "function" }),
        "execution.boundary_function",
      ),
      (
        public_manifest([], output={ "type": "custom", "name": "missing" }),
        "execution.unresolved_custom_type",
      ),
      (
        {
          "entries": [
            { "name": "entry", "inputs": [], "output": { "type": "unit" } },
            {
              "name": "unused",
              "inputs": [
                {
                  "type": "maybe",
                  "item": { "type": "custom", "name": "missing" },
                },
              ],
              "output": { "type": "unit" },
            },
          ],
          "definitions": [],
        },
        "execution.unresolved_custom_type",
      ),
    ] {
    assert_eq(
      @mck.handle(invocation_request(Json::null(), manifest)),
      invocation_invalid(code),
    )
  }
}

///|
test "duplicate public names and malformed entry shapes are rejected" {
  let entry : Json = {
    "name": "entry",
    "inputs": [],
    "output": { "type": "unit" },
  }
  let manifests : Array[Json] = [
    { "entries": [entry, entry], "definitions": [] },
    { "entries": [{ "name": "entry", "inputs": [] }], "definitions": [] },
    { "entries": [], "definitions": [], "visibility": "public" },
  ]
  for manifest in manifests {
    assert_eq(
      @mck.handle(invocation_request(invocation_suite([]), manifest)),
      invocation_invalid("workbench.invalid_manifest"),
    )
  }
}

///|
test "invocation extensions preserve opaque JSON bytes and specified Ion null projection" {
  let canonical : Json = {
    "profile": "morphir-invocations-v1",
    "calls": [{ "id": "c", "entry": "entry", "arguments": [] }],
    "extensions": { "format": "ion-binary", "bytes": [224, 1, 0, 234, 15] },
  }
  for
    (format, suite) in [
      ("json", canonical),
      (
        "ion-text",
        Json::string(
          "{profile:\"morphir-invocations-v1\",calls:[{id:\"c\",entry:\"entry\",arguments:[]}],extensions:null}",
        ),
      ),
    ] {
    assert_eq(
      @mck.handle(invocation_request(suite, public_manifest([]), format~)),
      { "id": 11, "status": "ok", "value": canonical },
    )
  }
}

///|
test "compact invocation input byte limit includes escaped Ion text" {
  let source = "{profile:\"morphir-invocations-v1\",calls:[{id:\"c\",entry:\"entry\",arguments:[]}]}"
  let manifest = public_manifest([])
  let seed = invocation_request(
    Json::string(source),
    manifest,
    format="ion-text",
  )
  guard seed is Object(fields) else { fail("request is an object") }
  let size = fields["input"].stringify().length()
  let exact = Json::string(" ".repeat(1024 * 1024 - size) + source)
  assert_eq(
    @mck.handle(invocation_request(exact, manifest, format="ion-text")),
    { "id": 11, "status": "ok", "value": invocation_suite([]) },
  )
  assert_eq(
    @mck.handle(
      invocation_request(
        Json::string(" ".repeat(1024 * 1024 - size + 1) + source),
        manifest,
        format="ion-text",
      ),
    ),
    invocation_invalid("workbench.input_limit"),
  )
  assert_eq(
    @mck.handle(
      invocation_request(
        Json::string("\"".repeat(600000)),
        manifest,
        format="ion-text",
      ),
    ),
    invocation_invalid("workbench.input_limit"),
  )
}

///|
test "raw invocation requests reject duplicates inside suite and manifest" {
  for
    source in [
      "{\"id\":11,\"op\":\"validate-invocations\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.3\",\"format\":\"json\",\"input\":{\"suite\":{\"profile\":\"morphir-invocations-v1\",\"calls\":[],\"calls\":[]},\"manifest\":{\"entries\":[],\"definitions\":[]}}}",
      "{\"id\":11,\"op\":\"validate-invocations\",\"suite\":\"workbench\",\"contractVersion\":\"0.1.0-draft.3\",\"format\":\"json\",\"input\":{\"suite\":{},\"manifest\":{\"entries\":[],\"definitions\":[],\"definitions\":[]}}}",
    ] {
    assert_eq(
      @mck.handle_line(source),
      Some(invocation_invalid("workbench.invalid_request")),
    )
  }
}

///|
fn tuple(
  operation~ : String = "morphir.frontend.compileModel",
  json~ : Bool = false,
) -> Json {
  {
    "operation": operation,
    "profile": if json {
      "morphir-ir"
    } else {
      "morphir-model"
    },
    "codec": if json {
      "morphir-json"
    } else {
      "ion-binary"
    },
    "envelopeVersion": "0.1.0-draft.1",
    "irVersion": "4.0.0",
  }
}

///|
fn request(
  text~ : String = "pub fn isReady(flag_value : Bool) -> Bool { flag_value }\npub fn callReady(flag : Bool) -> Bool { isReady(flag) }",
) -> Json {
  {
    "languageId": "moonbit",
    "sources": {
      "root": "file:///example/src",
      "documents": [
        {
          "uri": "file:///example/src/main.mbt",
          "languageId": "moonbit",
          "version": 3,
          "text": text,
        },
      ],
    },
    "package": { "name": "example" },
    "options": { "typesOnly": false, "irVersion": "4.0.0" },
    "contextDigest": "a".repeat(64),
    "output": tuple(),
  }
}

///|
fn call(session : @mep.Session, operation : String, params : Json) -> Json {
  session
  .handle({ "jsonrpc": "2.0", "id": 1, "method": operation, "params": params })
  .unwrap()
}

///|
fn session() -> @mep.Session raise {
  let session = @mep.Session::new(frontend=Some(@adapter.provider()))
  let initialized = call(session, "morphir.initialize", {
    "protocolVersions": ["0.2.0-draft.1"],
    "host": { "name": "test", "version": "1" },
    "modelTransport": {
      "tuples": [
        tuple(),
        tuple(json=true),
        tuple(operation="morphir.backend.generateModel"),
      ],
      "limits": {
        "maxEncodedBytes": 5592408,
        "maxDecodedBytes": 4194304,
        "maxDepth": 128,
        "maxNodes": 100000,
      },
      "guarantees": [],
    },
  })
  assert_true(@wire.optional(initialized, "result") is Some(_))
  session
}

///|
test "application exposes only qualified rich frontend capabilities and retains real source naming" {
  let session = session()
  let advertised = @wire.field(
    call(session, "morphir.extension.capabilities", {}),
    "result",
  )
  let capabilities = @wire.field(advertised, "frontend")
  assert_eq(@wire.field(capabilities, "compile"), Json(false))
  assert_true(!capabilities.stringify().contains("multiDocument"))
  assert_true(
    @wire.field(advertised, "moonbitFrontendProfiles")
    .stringify()
    .contains("moonbit-model-stable-v1"),
  )
  let response = call(session, "morphir.frontend.compileModel", request())
  let result = @wire.field(response, "result")
  assert_eq(
    @wire.field(result, "success"),
    Json(true),
    msg=response.stringify(),
  )
  let model = @wire.field(result, "model")
  let bytes = @base64.decode(
    @wire.string(@wire.field(@wire.field(model, "payload"), "content")),
  )
  let ion = @binary.read_binary_value(bytes[:])
  assert_eq(ion.annotations()[0].text(), Some("morphir_model"))
  let text = @text.write_ion(ion)
  assert_true(text.contains("file:///example/src/main.mbt"))
  assert_true(text.contains("isReady"))
  assert_true(text.contains("contextDigest"))
  assert_true(text.contains("urn:finos:morphir-moonbit:node-metadata:v1"))
  let generated = call(session, "morphir.backend.generateModel", {
    "model": model,
    "input": tuple(operation="morphir.backend.generateModel"),
    "target": "moonbit",
    "contextDigest": "a".repeat(64),
  })
  assert_eq(
    @wire.field(@wire.field(generated, "result"), "success"),
    Json(true),
    msg=generated.stringify(),
  )
  assert_true(generated.stringify().contains("pub fn isReady"))
  assert_true(generated.stringify().contains("pub fn callReady"))
}

///|
test "real source refuses lossy JSON rather than discarding origins and remains usable" {
  let session = session()
  let params = request()
  @wire.object(params)["output"] = tuple(json=true)
  let response = @wire.field(
    call(session, "morphir.frontend.compileModel", params),
    "result",
  )
  assert_eq(@wire.field(response, "success"), Json(false))
  assert_eq(@wire.optional(response, "model"), None)
  assert_true(response.stringify().contains("data.lossy_conversion"))
  assert_eq(
    @wire.field(
      @wire.field(
        call(session, "morphir.frontend.compileModel", request()),
        "result",
      ),
      "success",
    ),
    Json(true),
  )
}

///|
test "unsupported source profiles options roots and visibility fail without a model" {
  let session = session()
  for
    fault in [
      "profile", "typesOnly", "option", "root", "visibility", "import", "syntax",
      "unsupported-type",
    ] {
    let params = request()
    let options = @wire.object(@wire.field(params, "options"))
    match fault {
      "profile" => options["profile"] = Json("not-qualified")
      "typesOnly" => options["typesOnly"] = Json(true)
      "option" => options["sourceRoot"] = Json("legacy")
      "root" =>
        @wire.object(@wire.field(params, "sources"))["root"] = Json(
          "file:///other",
        )
      "visibility" =>
        @wire.object(@wire.field(params, "package"))["exposedModules"] = Json::array([],
        )
      _ => {
        let document = @wire.array(
            @wire.field(@wire.field(params, "sources"), "documents"),
          )[0]
        @wire.object(document)["text"] = Json(
          if fault == "import" {
            "import { \"other/pkg\" }\npub fn ready() -> Bool { true }"
          } else if fault == "unsupported-type" {
            "pub fn number(value : Array[Int32]) -> Int32 { 1 }"
          } else {
            "pub fn {"
          },
        )
      }
    }
    let response = @wire.field(
      call(session, "morphir.frontend.compileModel", params),
      "result",
    )
    assert_eq(@wire.field(response, "success"), Json(false), msg=fault)
    assert_eq(@wire.optional(response, "model"), None, msg=fault)
  }
}

///|
test "malformed source diagnostics preserve document location" {
  let response = @wire.field(
    call(
      session(),
      "morphir.frontend.compileModel",
      request(text="pub fn ready() -> Bool { missing }"),
    ),
    "result",
  )
  let diagnostic = @wire.array(@wire.field(response, "diagnostics"))[0]
  let location = @wire.field(diagnostic, "location")
  assert_eq(@wire.field(location, "uri"), Json("file:///example/src/main.mbt"))
  assert_eq(
    @wire.field(@wire.field(@wire.field(location, "range"), "start"), "line"),
    Json(0),
  )
}

///|
test "canonical root and document identity combinations are explicit" {
  let session = session()
  for variant in ["relative", "absolutePath", "uri", "relativeWithRoot"] {
    let params = request()
    let sources = @wire.field(params, "sources")
    let document = @wire.array(@wire.field(sources, "documents"))[0]
    match variant {
      "relative" => {
        ignore(@wire.object(sources).remove("root"))
        @wire.object(document)["uri"] = Json("domain/main.mbt")
      }
      "absolutePath" => {
        @wire.object(sources)["root"] = Json("/example/src")
        @wire.object(document)["uri"] = Json("/example/src/main.mbt")
      }
      "relativeWithRoot" => @wire.object(document)["uri"] = Json("main.mbt")
      _ => ()
    }
    let response = @wire.field(
      call(session, "morphir.frontend.compileModel", params),
      "result",
    )
    assert_eq(@wire.field(response, "success"), Json(true), msg=variant)
    assert_eq(
      @wire.field(response, "modules"),
      Json(if variant == "relative" { ["domain/main"] } else { ["main"] }),
    )
  }
  for variant in ["relativeRoot", "traversal", "encoded", "absoluteWithoutRoot"] {
    let params = request()
    let sources = @wire.field(params, "sources")
    let document = @wire.array(@wire.field(sources, "documents"))[0]
    match variant {
      "relativeRoot" => @wire.object(sources)["root"] = Json("src")
      "traversal" =>
        @wire.object(document)["uri"] = Json("file:///example/src/../main.mbt")
      "encoded" =>
        @wire.object(document)["uri"] = Json(
          "file:///example/src/%2e%2e/main.mbt",
        )
      _ => ignore(@wire.object(sources).remove("root"))
    }
    let response = call(session, "morphir.frontend.compileModel", params)
    if variant == "relativeRoot" {
      assert_true(response.stringify().contains("invalid_source_root"))
    } else {
      let result = @wire.field(response, "result")
      assert_eq(@wire.field(result, "success"), Json(false), msg=variant)
      assert_eq(@wire.optional(result, "model"), None)
    }
  }
}

///|
test "successful naming warnings retain primary and related UTF16 source ranges" {
  let prefix = "// 😀\npub fn "
  let response = @wire.field(
    call(
      session(),
      "morphir.frontend.compileModel",
      request(
        text="pub fn is_ready() -> Bool { true }\n" +
          prefix +
          "isReady() -> Bool { false }",
      ),
    ),
    "result",
  )
  assert_eq(@wire.field(response, "success"), Json(true))
  let warnings = @wire.array(@wire.field(response, "diagnostics"))
  assert_eq(warnings.length(), 1)
  let warning = warnings[0]
  assert_eq(@wire.field(warning, "severity"), Json("warning"))
  assert_eq(
    @wire.field(warning, "code"),
    Json("moonbit_frontend.name_normalization_collision"),
  )
  let location = @wire.field(warning, "location")
  assert_eq(@wire.field(location, "uri"), Json("file:///example/src/main.mbt"))
  let range = @wire.field(location, "range")
  assert_eq(@wire.field(range, "start"), { "line": 2, "character": 7 })
  assert_eq(@wire.field(range, "end"), { "line": 2, "character": 14 })
  let related = @wire.array(@wire.field(warning, "related"))
  assert_eq(related.length(), 1)
  let other = @wire.field(related[0], "location")
  assert_eq(@wire.field(other, "uri"), Json("file:///example/src/main.mbt"))
  assert_eq(@wire.field(@wire.field(other, "range"), "start"), {
    "line": 0,
    "character": 7,
  })
  assert_eq(@wire.field(@wire.field(other, "range"), "end"), {
    "line": 0,
    "character": 15,
  })
  assert_true(
    @wire.string(@wire.field(related[0], "message")).contains("is_ready"),
  )
  assert_true(@wire.string(@wire.field(warning, "message")).contains("Fix:"))
}

///|
test "typed library composes numeric and String functions over rich source transport" {
  let response = @wire.field(
    call(
      session(),
      "morphir.frontend.compileModel",
      request(
        text="pub fn number() -> Int32 { 2147483647 + 1 }\npub fn shorter(a : String, b : String) -> Bool { a < b }",
      ),
    ),
    "result",
  )
  assert_eq(
    @wire.field(response, "success"),
    Json(true),
    msg=response.stringify(),
  )
  assert_true(@wire.optional(response, "model") is Some(_))
}

///|
test "MEP defaults to stable and numeric capabilities require experimental opt-in" {
  let session = session()
  let params = request(text="pub fn round(v : Float) -> Float { v + 1.0F }")
  let stable = @wire.field(
    call(session, "morphir.frontend.compileModel", params),
    "result",
  )
  assert_eq(@wire.field(stable, "success"), Json(false))
  assert_eq(@wire.optional(stable, "model"), None)
  assert_true(
    stable.stringify().contains("moonbit_frontend.experimental_capability"),
  )
  @wire.object(@wire.field(params, "options"))["profile"] = Json(
    "moonbit-model-experimental-v1",
  )
  let experimental = @wire.field(
    call(session, "morphir.frontend.compileModel", params),
    "result",
  )
  assert_eq(
    @wire.field(experimental, "success"),
    Json(true),
    msg=experimental.stringify(),
  )
  let bytes = @base64.decode(
    @wire.string(
      @wire.field(
        @wire.field(@wire.field(experimental, "model"), "payload"),
        "content",
      ),
    ),
  )
  assert_true(
    @text.write_ion(@binary.read_binary_value(bytes[:])).contains(
      "moonbit-model-experimental-v1",
    ),
  )
}

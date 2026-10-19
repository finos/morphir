///|
fn compile_tuple(
  codec~ : String = "ion-binary",
  profile~ : String = "morphir-model",
) -> Json {
  let tuple = rich_tuple(codec~, profile~)
  if tuple is Object(fields) {
    fields["operation"] = Json::string("morphir.frontend.compileModel")
  }
  tuple
}

///|
fn compile_offer() -> Json {
  let offer = rich_offer()
  if offer is Object(fields) {
    fields["tuples"] = Json([
      compile_tuple(),
      compile_tuple(codec="morphir-json", profile="morphir-ir"),
      rich_tuple(),
      rich_tuple(codec="morphir-json", profile="morphir-ir"),
    ])
  }
  offer
}

///|
fn compile_params() -> Json {
  {
    "languageId": "moonbit",
    "sources": {
      "root": "/example/src",
      "documents": [
        {
          "uri": "/example/src/main.mbt",
          "languageId": "moonbit",
          "version": 1,
          "text": "pub fn ready() -> Bool { true }",
        },
      ],
    },
    "package": { "name": "example" },
    "options": { "typesOnly": false, "irVersion": "4.0.0" },
    "contextDigest": "a".repeat(64),
    "output": compile_tuple(),
  }
}

///|
fn plain_frontend() -> @mep.Frontend {
  {
    language_id: "moonbit",
    file_extensions: [".mbt"],
    profiles: [],
    compile: (input, _) => {
      @mep.Compiled(
        @generator.Input::new(input.uri, @metadata_fixtures.input()),
        ["main"],
        [],
      )
    },
  }
}

///|
fn compile_call(
  session : @mep.Session,
  params~ : Json = compile_params(),
) -> Json {
  call(session, "morphir.frontend.compileModel", params~)
}

///|
test "compile requires an injected frontend and an explicitly selected compile tuple" {
  let backend = @mep.Session::new()
  ignore(initialize_models(backend, offer=compile_offer()))
  assert_true(compile_call(backend).stringify().contains("-32013"))
  let legacy = @mep.Session::new(frontend=Some(plain_frontend()))
  initialize(legacy)
  assert_true(compile_call(legacy).stringify().contains("-32013"))
  let generation_only = @mep.Session::new(frontend=Some(plain_frontend()))
  ignore(initialize_models(generation_only))
  assert_eq(
    @wire.field(@wire.field(compile_call(generation_only), "error"), "code"),
    Json(-32013),
  )
  let session = @mep.Session::new(frontend=Some(plain_frontend()))
  let offer = compile_offer()
  ignore(initialize_models(session, offer~))
  @wire.object(offer)["tuples"] = Json::array([])
  @wire.object(@wire.field(offer, "limits"))["maxDecodedBytes"] = Json(1)
  assert_eq(
    @wire.field(@wire.field(compile_call(session), "result"), "success"),
    Json(true),
  )
  let wrong = compile_params()
  set_json(wrong, "output", rich_tuple())
  assert_true(
    compile_call(session, params=wrong)
    .stringify()
    .contains("unsupported_tuple"),
  )
  let generated = model_params(rich_bytes())
  set_json(generated, "input", compile_tuple())
  assert_true(
    call(session, "morphir.backend.generateModel", params=generated)
    .stringify()
    .contains("unsupported_tuple"),
  )
}

///|
test "narrow session refuses an unavailable model operation as a capability error" {
  let session = @mep.Session::new(frontend=Some(plain_frontend()))
  let offer = compile_offer()
  set_json(offer, "tuples", Json([compile_tuple()]))
  ignore(initialize_models(session, offer~))
  let refused = call(
    session,
    "morphir.backend.generateModel",
    params=model_params(rich_bytes()),
  )
  assert_eq(@wire.field(@wire.field(refused, "error"), "code"), Json(-32013))
  // The refused operation must not disturb the admitted compilation session.
  assert_eq(
    @wire.field(@wire.field(compile_call(session), "result"), "success"),
    Json(true),
  )
}

///|
test "plain compilation emits checked JSON and feeds the existing generator" {
  let session = @mep.Session::new(frontend=Some(plain_frontend()))
  ignore(initialize_models(session, offer=compile_offer()))
  let params = compile_params()
  let tuple = compile_tuple(codec="morphir-json", profile="morphir-ir")
  set_json(params, "output", tuple)
  let compiled = @wire.field(compile_call(session, params~), "result")
  assert_eq(@wire.field(compiled, "success"), Json(true))
  let model = @wire.field(compiled, "model")
  let bytes = @base64.decode(
    @wire.string(@wire.field(@wire.field(model, "payload"), "content")),
  )
  assert_eq(@ir_json.read(@utf8.decode(bytes[:])), @metadata_fixtures.input())
  let generated = call(session, "morphir.backend.generateModel", params={
    "model": model,
    "input": rich_tuple(codec="morphir-json", profile="morphir-ir"),
    "target": "moonbit",
    "contextDigest": "a".repeat(64),
  })
  assert_eq(
    @wire.field(@wire.field(generated, "result"), "success"),
    Json(true),
  )
}

///|
test "identity is stable and logical revision binds source version content context and options" {
  let session = @mep.Session::new(frontend=Some(plain_frontend()))
  ignore(initialize_models(session, offer=compile_offer()))
  let original = @wire.field(
    @wire.field(compile_call(session), "result"),
    "model",
  )
  for changed in ["version", "text", "contextDigest", "profile"] {
    let params = compile_params()
    match changed {
      "version" =>
        set_json(
          @wire.array(@wire.field(@wire.field(params, "sources"), "documents"))[0],
          "version",
          Json(2),
        )
      "text" =>
        set_json(
          @wire.array(@wire.field(@wire.field(params, "sources"), "documents"))[0],
          "text",
          Json("different"),
        )
      "contextDigest" => set_json(params, "contextDigest", Json("b".repeat(64)))
      _ =>
        set_json(
          @wire.field(params, "options"),
          "profile",
          Json("explicit-profile"),
        )
    }
    let model = @wire.field(
      @wire.field(compile_call(session, params~), "result"),
      "model",
    )
    assert_eq(@wire.field(original, "modelId"), @wire.field(model, "modelId"))
    assert_true(
      @wire.field(original, "revision") != @wire.field(model, "revision"),
    )
  }
  let reordered = compile_params()
  set_json(reordered, "options", { "irVersion": "4.0.0", "typesOnly": false })
  let model = @wire.field(
    @wire.field(compile_call(session, params=reordered), "result"),
    "model",
  )
  assert_eq(@wire.field(original, "revision"), @wire.field(model, "revision"))
  let json = compile_params()
  set_json(
    json,
    "output",
    compile_tuple(codec="morphir-json", profile="morphir-ir"),
  )
  let model = @wire.field(
    @wire.field(compile_call(session, params=json), "result"),
    "model",
  )
  assert_eq(@wire.field(original, "revision"), @wire.field(model, "revision"))
}

///|
test "compilation provenance preserves optional source values without option wrappers" {
  fn ion_field(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
    guard value.kind() is Struct(fields) else { fail("Expected struct") }
    for field in fields {
      if field.name().text() == Some(name) {
        return field.value()
      }
    }
    fail("Missing field: " + name)
  }
  let session = @mep.Session::new(frontend=Some(plain_frontend()))
  ignore(initialize_models(session, offer=compile_offer()))
  for present in [true, false] {
    let params = compile_params()
    if present {
      set_json(@wire.field(params, "package"), "exposedModules", Json(["main"]))
    } else {
      let sources = @wire.field(params, "sources")
      ignore(@wire.object(sources).remove("root"))
      set_json(
        @wire.array(@wire.field(sources, "documents"))[0],
        "uri",
        Json("main.mbt"),
      )
    }
    let model = @wire.field(
      @wire.field(compile_call(session, params~), "result"),
      "model",
    )
    let bytes = @base64.decode(
      @wire.string(@wire.field(@wire.field(model, "payload"), "content")),
    )
    let root = @ion_binary.read_binary_value(bytes[:])
    guard ion_field(root, "provenance").kind() is List(entries) else {
      fail("Expected provenance list")
    }
    let context = entries.filter(entry => {
        entry
        .annotations()
        .any(a => a.text() == Some("morphir_moonbit_compilation"))
      })[0]
    assert_eq(
      @ion_text.write_ion(ion_field(context, "sourceRoot")),
      if present {
        "\"/example/src\""
      } else {
        "null"
      },
    )
    assert_eq(
      @ion_text.write_ion(ion_field(context, "exposedModules")),
      if present {
        "[\"main\"]"
      } else {
        "null"
      },
    )
  }
}

///|
test "unsupported source sets context and dependencies are refused before compilation" {
  let calls = Ref(0)
  let frontend = {
    ..plain_frontend(),
    compile: (_, _) => {
      calls.val += 1
      @mep.CompilationFailed([])
    },
  }
  let session = @mep.Session::new(frontend=Some(frontend))
  ignore(initialize_models(session, offer=compile_offer()))
  for
    fault in [
      "empty", "multiple", "dependency", "language", "documentLanguage", "version",
      "context", "irVersion", "baseline", "topDocuments",
    ] {
    let params = compile_params()
    let sources = @wire.field(params, "sources")
    let document = @wire.array(@wire.field(sources, "documents"))[0]
    match fault {
      "empty" => set_json(sources, "documents", Json::array([]))
      "multiple" => set_json(sources, "documents", Json([document, document]))
      "dependency" =>
        set_json(params, "dependencies", Json([{ "packageName": "external" }]))
      "language" => set_json(params, "languageId", Json("elm"))
      "documentLanguage" => set_json(document, "languageId", Json("elm"))
      "version" => set_json(document, "version", Json(-1))
      "context" => set_json(params, "contextDigest", Json("invalid"))
      "irVersion" =>
        set_json(@wire.field(params, "options"), "irVersion", Json("4.1.0"))
      "baseline" => set_json(params, "baseline", {})
      _ => {
        @wire.object(params).remove("sources") |> ignore
        set_json(params, "documents", Json([document]))
      }
    }
    let response = compile_call(session, params~)
    assert_true(
      @wire.optional(response, "error") is Some(_),
      msg=fault + ": " + response.stringify(),
    )
    assert_eq(calls.val, 0)
  }
}

///|
test "failed cancelled lossy and over-budget compilation omit model and preserve session" {
  for
    fault in [
      "failed", "cancelled", "lossy", "budget", "identity", "package", "modules",
      "irVersion",
    ] {
    let frontend = {
      ..plain_frontend(),
      compile: (input, _) => {
        if fault == "failed" {
          return @mep.CompilationFailed([
            { "severity": "error", "message": "bad source" },
          ])
        }
        let generated = @generator.Input::new(
          if fault == "identity" {
            "wrong"
          } else {
            input.uri
          },
          if fault == "package" {
            @fixtures.library()
          } else if fault == "irVersion" {
            let value = @ir_json.to_json(@metadata_fixtures.input())
            set_json(value, "formatVersion", Json("4.0.1"))
            @ir_json.from_json(value)
          } else {
            @metadata_fixtures.input()
          },
        )
        @mep.Compiled(
          if fault == "lossy" {
            {
              ..generated,
              provenance: [@ion.IonValue::string("retained provenance")],
            }
          } else {
            generated
          },
          if fault == "modules" {
            ["other"]
          } else {
            ["main"]
          },
          [],
        )
      },
    }
    let session = @mep.Session::new(frontend=Some(frontend), cancelled=fn() {
      fault == "cancelled"
    })
    let offer = compile_offer()
    if fault == "budget" {
      set_json(@wire.field(offer, "limits"), "maxNodes", Json(1))
    }
    ignore(initialize_models(session, offer~))
    let params = compile_params()
    if fault == "lossy" {
      set_json(
        params,
        "output",
        compile_tuple(codec="morphir-json", profile="morphir-ir"),
      )
    }
    let response = @wire.field(compile_call(session, params~), "result")
    assert_eq(@wire.field(response, "success"), Json(false), msg=fault)
    assert_eq(@wire.optional(response, "model"), None, msg=fault)
    if fault == "package" || fault == "modules" {
      assert_true(response.stringify().contains("compilation_context_mismatch"))
    }
    if fault == "irVersion" {
      assert_true(response.stringify().contains("unsupported_ir_version"))
    }
    assert_eq(
      @wire.field(@wire.field(call(session, "morphir.ping"), "result"), "ok"),
      Json(true),
    )
  }
}

///|
test "cancellation observed after frontend completion prevents model publication" {
  let cancelled = Ref(false)
  let frontend = {
    ..plain_frontend(),
    compile: (input, _) => {
      cancelled.val = true
      @mep.Compiled(
        @generator.Input::new(input.uri, @metadata_fixtures.input()),
        ["main"],
        [],
      )
    },
  }
  let session = @mep.Session::new(frontend=Some(frontend), cancelled=fn() {
    cancelled.val
  })
  ignore(initialize_models(session, offer=compile_offer()))
  let response = @wire.field(compile_call(session), "result")
  assert_eq(@wire.field(response, "success"), Json(false))
  assert_eq(@wire.optional(response, "model"), None)
  assert_true(response.stringify().contains("cancelled"))
}

///|
test "compiled payload obeys exact encoded and decoded negotiated boundaries" {
  let reference = @mep.Session::new(frontend=Some(plain_frontend()))
  ignore(initialize_models(reference, offer=compile_offer()))
  let model = @wire.field(
    @wire.field(compile_call(reference), "result"),
    "model",
  )
  let payload = @wire.field(model, "payload")
  let encoded = @wire.string(@wire.field(payload, "content")).length()
  for limit in ["maxEncodedBytes", "maxDecodedBytes"] {
    for exact in [true, false] {
      let offer = compile_offer()
      let boundary = if limit == "maxEncodedBytes" {
        Json(encoded)
      } else {
        @wire.field(payload, "decodedByteLength")
      }
      let n = @strconv.parse_int(@wire.integer_text(boundary))
      set_json(
        @wire.field(offer, "limits"),
        limit,
        Json(if exact { n } else { n - 1 }),
      )
      let session = @mep.Session::new(frontend=Some(plain_frontend()))
      ignore(initialize_models(session, offer~))
      let response = @wire.field(compile_call(session), "result")
      assert_eq(@wire.field(response, "success"), Json(exact), msg=limit)
      assert_eq(@wire.optional(response, "model") is Some(_), exact)
    }
  }
}

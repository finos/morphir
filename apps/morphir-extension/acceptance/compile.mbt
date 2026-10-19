///|
priv struct ModelClient {
  input : @process.WriteToProcess
  output : @process.ReadFromProcess
  decoder : @mep.Decoder
  mut next_id : Int32
}

///|
async fn ModelClient::call(
  self : ModelClient,
  operation : String,
  params : Json,
) -> Json {
  self.next_id += 1
  let id = self.next_id
  let request : Json = {
    "jsonrpc": "2.0",
    "id": id,
    "method": operation,
    "params": params,
  }
  @async.with_timeout(10000, async fn() {
    self.input.write(@mep.encode_frame(request.stringify()))
    while self.output.read_some(max_len=65536) is Some(bytes) {
      let frames = self.decoder.feed(bytes)
      if !frames.is_empty() {
        assert_eq(frames.length(), 1)
        let response = @wire.parse_bounded(@utf8.decode(frames[0][:]))
        assert_eq(@wire.field(response, "id"), Json(id))
        return response
      }
    }
    fail("Guest closed before answering " + operation)
  })
}

///|
fn source_tuple(operation : String, json~ : Bool = false) -> Json {
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
fn source_request() -> Json {
  {
    "languageId": "moonbit",
    "sources": {
      "root": "file:///example/src",
      "documents": [
        {
          "uri": "file:///example/src/main.mbt",
          "languageId": "moonbit",
          "version": 7,
          "text": "fn identity(value : Bool) -> Bool { value }\npub fn isReady(flag_value : Bool) -> Bool { identity(flag_value) }\npub fn callReady(flag : Bool) -> Bool { isReady(flag) }",
        },
      ],
    },
    "package": { "name": "source/example", "exposedModules": ["main"] },
    "options": {
      "typesOnly": false,
      "irVersion": "4.0.0",
      "profile": "moonbit-model-bool-library-v1",
    },
    "contextDigest": "a".repeat(64),
    "output": source_tuple("morphir.frontend.compileModel"),
  }
}

///|
async fn compile_process_cases(
  guest : String,
  root : String,
  repository : String,
  evidence : String,
) -> Unit {
  let (model, artifacts) = @async.with_task_group(async fn(group) {
    let (stdin, writer) = @process.write_to_process()
    defer writer.close()
    let (reader, stdout) = @process.read_from_process()
    defer reader.close()
    let (errors, stderr) = @process.read_from_process()
    defer errors.close()
    let process = @process.spawn(
      group,
      guest,
      guest_arguments(),
      stdin~,
      stdout~,
      stderr~,
      cwd=root,
      extra_env=guest_environment(),
    )
    let client = {
      input: writer,
      output: reader,
      decoder: @mep.Decoder::new(),
      next_id: 0,
    }
    let compile_operation = "morphir.frontend.compileModel"
    let generate_operation = "morphir.backend.generateModel"
    let initialized = client.call("morphir.initialize", {
      "protocolVersions": ["0.2.0-draft.1"],
      "host": { "name": "native-acceptance", "version": "1" },
      "modelTransport": {
        "tuples": [
          source_tuple(compile_operation),
          source_tuple(generate_operation),
          source_tuple(compile_operation, json=true),
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
    assert_true(
      @wire.optional(initialized, "result") is Some(_),
      msg=initialized.stringify(),
    )
    let collision = source_request()
    @wire.object(
      @wire.array(@wire.field(@wire.field(collision, "sources"), "documents"))[0],
    )["text"] = Json(
      "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }",
    )
    let warned = @wire.field(
      client.call(compile_operation, collision),
      "result",
    )
    assert_eq(@wire.field(warned, "success"), Json(true))
    let warning = @wire.array(@wire.field(warned, "diagnostics"))[0]
    assert_eq(@wire.field(warning, "severity"), Json("warning"))
    let location = @wire.field(warning, "location")
    assert_eq(
      @wire.field(location, "uri"),
      Json("file:///example/src/main.mbt"),
    )
    assert_eq(
      @wire.field(@wire.field(@wire.field(location, "range"), "start"), "line"),
      Json(1),
    )
    let related = @wire.array(@wire.field(warning, "related"))
    assert_eq(related.length(), 1)
    assert_eq(
      @wire.field(@wire.field(related[0], "location"), "uri"),
      Json("file:///example/src/main.mbt"),
    )
    // Refusals leave the session available for a subsequent real compilation.
    let json = source_request()
    @wire.object(json)["output"] = source_tuple(compile_operation, json=true)
    let refused = @wire.field(client.call(compile_operation, json), "result")
    assert_eq(@wire.field(refused, "success"), Json(false))
    assert_eq(@wire.optional(refused, "model"), None)
    assert_true(refused.stringify().contains("data.lossy_conversion"))
    let malformed = source_request()
    @wire.object(
      @wire.array(@wire.field(@wire.field(malformed, "sources"), "documents"))[0],
    )["text"] = Json("pub fn {")
    let refused = @wire.field(
      client.call(compile_operation, malformed),
      "result",
    )
    assert_eq(@wire.field(refused, "success"), Json(false))
    assert_eq(@wire.optional(refused, "model"), None)
    let compiled = client.call(compile_operation, source_request())
    let result = @wire.field(compiled, "result")
    assert_eq(
      @wire.field(result, "success"),
      Json(true),
      msg=compiled.stringify(),
    )
    assert_eq(@wire.field(result, "modules"), Json(["main"]))
    let model = @wire.field(result, "model")
    let payload = @wire.field(model, "payload")
    let bytes = @base64.decode(@wire.string(@wire.field(payload, "content")))
    assert_eq(Json(bytes.length()), @wire.field(payload, "decodedByteLength"))
    assert_eq(
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      @wire.string(@wire.field(payload, "sha256")),
    )
    let ion = @binary.read_binary_value(bytes[:])
    assert_eq(ion.annotations()[0].text(), Some("morphir_model"))
    let text = @ion_text.write_ion(ion)
    for
      retained in [
        "src/main.mbt", "isReady", "callReady", "sourceVersion", "contextDigest",
        "urn:finos:morphir-moonbit:node-metadata:v1",
      ] {
      assert_true(text.contains(retained), msg=retained)
    }
    let generated = client.call(generate_operation, {
      "model": model,
      "input": source_tuple(generate_operation),
      "target": "moonbit",
      "contextDigest": "a".repeat(64),
    })
    let generated_result = @wire.field(generated, "result")
    assert_eq(
      @wire.field(generated_result, "success"),
      Json(true),
      msg=generated.stringify(),
    )
    let artifacts = @wire.array(@wire.field(generated_result, "artifacts"))
    assert_eq(
      @base64.decode(@wire.string(@wire.field(artifacts[0], "content"))),
      bytes,
    )
    ignore(client.call("morphir.shutdown", {}))
    writer.write(
      @mep.encode_frame("{\"jsonrpc\":\"2.0\",\"method\":\"morphir.exit\"}"),
    )
    writer.close()
    assert_eq(process.wait(), 0)
    assert_eq(errors.read_all().text(), "")
    assert_eq(reader.read_some(), None)
    client.decoder.finish()
    (model, artifacts)
  })
  // Guest code must not write files. This acceptance host publishes artifacts.
  assert_eq(@fs.readdir(root, include_hidden=true), [])
  @fs.mkdir(root + "/generated")
  for artifact in artifacts {
    let path = @wire.string(@wire.field(artifact, "path"))
    assert_true(!path.has_prefix("/") && !path.split("/").any(p => p == ".."))
    let parent = path.split("/").to_array()
    ignore(parent.pop())
    if !parent.is_empty() {
      @fs.mkdir(
        root + "/generated/" + parent.join("/"),
        recursive=true,
        allow_exist=true,
      )
    }
    let content = @wire.string(@wire.field(artifact, "content"))
    if @wire.field(artifact, "binary") == Json(true) {
      @fs.write_file(root + "/generated/" + path, @base64.decode(content))
    } else {
      @fs.write_file(root + "/generated/" + path, content)
    }
  }
  let manifest = @fs.read_file(root + "/generated/moon.mod").text()
  let name_line = manifest
    .split("\n")
    .filter(line => line.has_prefix("name = "))
    .to_array()[0]
  let module_name = @wire.string(@wire.parse_bounded(name_line[7:].to_owned()))
  let library = @fs.read_file(root + "/generated/library.mbt").text()
  assert_true(library.contains("pub fn isReady"))
  assert_true(library.contains("pub fn callReady"))
  @fs.mkdir(root + "/consumer")
  @fs.write_file(
    root + "/consumer/moon.mod",
    "name = \"mep/source-consumer\"\nversion = \"0.0.0\"\nimport { " +
    Json::string(module_name + "@0.0.0").stringify() +
    ", }\n",
  )
  @fs.write_file(
    root + "/consumer/moon.pkg",
    "pkgtype(kind: \"executable\")\nimport { " +
    Json::string(module_name).stringify() +
    " @generated, }\n",
  )
  @fs.write_file(
    root + "/consumer/main.mbt",
    "fn main raise {\n  assert_true(@generated.isReady()(true))\n  assert_true(!@generated.isReady()(false))\n  assert_true(@generated.callReady()(true))\n  assert_true(!@generated.callReady()(false))\n  println(\"Native source consumer passed\")\n}\n",
  )
  @fs.write_file(
    root + "/moon.work",
    "members = [" +
    [root + "/generated", root + "/consumer", repository + "/pkgs/morphir-sdk"]
    .map(p => Json::string(p).stringify())
    .join(",") +
    "]\n",
  )
  ignore(
    checked(
      "moon",
      ["build", "--target", "native", "generated", "consumer"],
      cwd=root,
    ),
  )
  let consumer_result = checked(
    "moon",
    ["run", "--target", "native", "consumer"],
    cwd=root,
  )
  assert_true(consumer_result.contains("Native source consumer passed"))
  // Preserve the complete reproduction, rather than only a few model sidecars.
  @fs.write_file(
    evidence + "/source-request.json",
    source_request().stringify(),
  )
  @fs.write_file(evidence + "/consumer-result.txt", consumer_result)
  for artifact in artifacts {
    let path = @wire.string(@wire.field(artifact, "path"))
    let parent = path.split("/").to_array()
    ignore(parent.pop())
    @fs.mkdir(
      evidence + "/generated/" + parent.join("/"),
      recursive=true,
      allow_exist=true,
    )
    @fs.write_file(
      evidence + "/generated/" + path,
      @fs.read_file(root + "/generated/" + path),
    )
  }
  @fs.mkdir(evidence + "/consumer", allow_exist=true)
  for name in ["moon.mod", "moon.pkg", "main.mbt"] {
    @fs.write_file(
      evidence + "/consumer/" + name,
      @fs.read_file(root + "/consumer/" + name),
    )
  }
  @fs.write_file(evidence + "/compiled-envelope.json", model.stringify())
  @fs.write_file(
    evidence + "/compiled-model.ionb",
    @base64.decode(
      @wire.string(@wire.field(@wire.field(model, "payload"), "content")),
    ),
  )
  @fs.write_file(
    evidence + "/compiled-symbols.ionb",
    @fs.read_file(root + "/generated/symbols.10n"),
  )
}

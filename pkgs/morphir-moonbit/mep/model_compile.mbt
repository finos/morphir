///|
/// An admitted single-document request. URIs are identities, never file reads.
pub(all) struct CompileInput {
  uri : String
  version : UInt64
  text : String
  root : String?
  package_name : String
  exposed_modules : Array[String]?
  options : Json
  context_digest : String
}

///|
/// The result sum prevents a failed compilation from carrying a model.
pub(all) enum Compilation {
  Compiled(@generator.Input, Array[String], Array[Json])
  CompilationFailed(Array[Json])
}

///|
/// Supplied by the application; the generator has no frontend dependency.
pub(all) struct Frontend {
  language_id : String
  file_extensions : Array[String]
  profiles : Array[Json]
  compile : (CompileInput, () -> Bool) -> Compilation raise
}

///|
fn compilation_failure(code : String, message : String) -> Json {
  {
    "success": false,
    "diagnostics": [{ "severity": "error", "code": code, "message": message }],
  }
}

///|
fn compile_input(params : Json, frontend : Frontend) -> CompileInput raise {
  @wire.fields(params, [
    "languageId", "sources", "package", "dependencies", "options", "contextDigest",
    "output",
  ])
  guard @wire.string(@wire.field(params, "languageId")) == frontend.language_id else {
    raise Refused("unsupported_language")
  }
  let sources = @wire.field(params, "sources")
  @wire.fields(sources, ["root", "documents"])
  let documents = @wire.array(@wire.field(sources, "documents"))
  guard documents.length() == 1 else {
    raise Refused("unsupported_source_count")
  }
  let document = documents[0]
  @wire.fields(document, ["uri", "languageId", "version", "text"])
  guard @wire.string(@wire.field(document, "languageId")) ==
    frontend.language_id else {
    raise Refused("unsupported_language")
  }
  guard @wire.optional(params, "dependencies")
    .map(@wire.array)
    .unwrap_or([])
    .is_empty() else {
    raise Refused("unsupported_dependencies")
  }
  let package_info = @wire.field(params, "package")
  @wire.fields(package_info, ["name", "exposedModules"])
  let options = @wire.field(params, "options")
  ignore(@wire.object(options))
  guard @wire.field(options, "irVersion") ==
    field(field(params, "output"), "irVersion") else {
    raise Refused("unsupported_ir_version")
  }
  let root = @wire.optional(sources, "root").map(model_text)
  if root is Some(root) {
    guard root.has_prefix("/") ||
      root.contains("://") ||
      (root.length() >= 3 && root[1] == ':' && root[2] == '/') else {
      raise Refused("invalid_source_root")
    }
  }
  {
    uri: model_text(@wire.field(document, "uri")),
    version: @strconv.parse_uint64(
      @wire.integer_text(@wire.field(document, "version")),
    ),
    text: @wire.string(@wire.field(document, "text")),
    root,
    package_name: model_text(@wire.field(package_info, "name")),
    exposed_modules: @wire.optional(package_info, "exposedModules").map(value => {
      @wire.array(value).map(model_text)
    }),
    options,
    context_digest: model_digest(@wire.field(params, "contextDigest")),
  }
}

///|
fn source_context(input : CompileInput, language : String) -> Json {
  {
    "languageId": language,
    "uri": input.uri,
    "version": input.version.to_string(),
    "text": input.text,
    "root": input.root,
    "packageName": input.package_name,
    "exposedModules": input.exposed_modules,
    "options": input.options,
    "contextDigest": input.context_digest,
  }
}

///|
// A logical revision must not depend on JSON object insertion order.
fn canonical_context(value : Json) -> String {
  match value {
    Object(fields) => {
      let names = fields.keys().to_array()
      names.sort()
      "{" +
      names
      .map(name => {
        Json::string(name).stringify() + ":" + canonical_context(fields[name])
      })
      .join(",") +
      "}"
    }
    Array(values) => "[" + values.map(canonical_context).join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn compile_rich_model(
  input : @generator.Input,
  source : CompileInput,
) -> @ion.IonValue raise {
  let carrier = @ion.IonValue::from_fields([
    @ion.Field::new("owner", @ion.IonValue::string(NODE_METADATA_OWNER)),
    @ion.Field::new(
      "data",
      @ion.IonValue::from_fields([
        @ion.Field::new("sourceUnitId", @ion.IonValue::string(input.unit_id)),
        @ion.Field::new(
          "sourceAnnotations",
          @ion.IonValue::list(
            input.annotations.map(a => @ion.IonValue::symbol_token(a)),
          ),
        ),
        @ion.Field::new(
          "nodes",
          @ion.IonValue::list(
            input.metadata.map(m => {
              @ion.IonValue::from_fields([
                @ion.Field::new("nodeId", @ion.IonValue::string(m.node_id)),
                @ion.Field::new("data", m.data),
              ])
            }),
          ),
        ),
      ]),
    ),
  ])
  let context : Json = {
    "sourceUri": source.uri,
    "sourceVersion": source.version.to_string(),
    "sourceRoot": source.root,
    "packageName": source.package_name,
    "exposedModules": source.exposed_modules,
    "options": source.options,
    "contextDigest": source.context_digest,
  }
  @ion.IonValue::from_fields([
    @ion.Field::new("ir", @ion_json.to_ion(@ir_json.to_json(input.ir))),
    @ion.Field::new("enrichments", @ion.IonValue::list([carrier])),
    @ion.Field::new(
      "provenance",
      @ion.IonValue::list(
        input.provenance +
        [
          @ion_json.to_ion(context).with_annotation(
            @ion.SymbolToken::new("morphir_moonbit_compilation"),
          ),
        ],
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_model"))
}

///|
fn compile_envelope(
  input : @generator.Input,
  source : CompileInput,
  language : String,
  tuple : Json,
  limits : ModelLimits,
  modules : Array[String],
) -> Json raise {
  guard input.unit_id == source.uri else {
    raise Refused("source_identity_mismatch")
  }
  guard input.ir.format_version.to_release_string() == "4.0.0" else {
    raise Refused("unsupported_ir_version")
  }
  let (package_name, actual_modules) = match input.ir.distribution {
    Library(name, _, definition) =>
      (
        name.to_canonical(),
        definition.modules.keys().map(n => n.to_canonical()).to_array(),
      )
    Specs(name, _, specification) =>
      (
        name.to_canonical(),
        specification.modules.keys().map(n => n.to_canonical()).to_array(),
      )
    Application(name, _, definition, _) =>
      (
        name.to_canonical(),
        definition.modules.keys().map(n => n.to_canonical()).to_array(),
      )
  }
  let selected_modules = modules.copy()
  selected_modules.sort()
  actual_modules.sort()
  guard package_name == source.package_name &&
    selected_modules == actual_modules else {
    raise Refused("compilation_context_mismatch")
  }
  let codec = @wire.string(@wire.field(tuple, "codec"))
  let bytes = if codec == "ion-binary" {
    @ion_binary.write_binary_value(compile_rich_model(input, source))
  } else {
    guard input.metadata.is_empty() &&
      input.provenance.is_empty() &&
      input.annotations.all(a => a.text() == Some("morphir_pipeline")) else {
      raise Refused("data.lossy_conversion")
    }
    @utf8.encode(@ir_json.write(input.ir))
  }
  guard bytes.length() <= limits.decoded &&
    (bytes.length().to_int64() + 2L) / 3L * 4L <= limits.encoded.to_int64() else {
    raise Refused("payload_limit")
  }
  let payload : Json = {
    "codec": codec,
    "layout": "single-document",
    "decodedByteLength": bytes.length(),
    "sha256": model_sha256(bytes),
    "content": @base64.encode(bytes[:]),
  }
  let budget = ModelBudget::new(limits)
  budget.reserve(payload)
  if codec == "ion-binary" {
    budget.inspect_binary(bytes)
    ignore(read_model_binary(bytes, limits))
  } else {
    ignore(budget.read_json(bytes))
  }
  {
    "envelopeVersion": MODEL_ENVELOPE,
    "modelId": "urn:finos:morphir-moonbit:model:" +
    model_sha256(
      @utf8.encode(Json([source.package_name, source.uri]).stringify()),
    ),
    "revision": "sha256:" +
    model_sha256(
      @utf8.encode(canonical_context(source_context(source, language))),
    ),
    "irVersion": "4.0.0",
    "profile": @wire.field(tuple, "profile"),
    "payload": payload,
  }
}

///|
fn Session::compile_model(self : Session, id : Json, params : Json) -> Json {
  guard self.frontend is Some(frontend) && self.models is Some(transport) else {
    return rpc_error(
      id, -32013, "Model compilation is unavailable in this session",
    )
  }
  let tuple = field(params, "output")
  guard transport.tuples.contains(tuple) &&
    field(tuple, "operation") == Json::string(COMPILE_MODEL) else {
    return rpc_error(id, -32602, "Model admission refused: unsupported_tuple")
  }
  let source = compile_input(params, frontend) catch {
    Refused(code) =>
      return rpc_error(id, -32602, "Compilation admission refused: " + code)
    _ =>
      return rpc_error(
        id, -32602, "Compilation admission refused: invalid_request",
      )
  }
  if (self.cancelled)() {
    return result(
      id,
      compilation_failure("moonbit_frontend.cancelled", "Frontend cancelled"),
    )
  }
  let compiled = (frontend.compile)(source, self.cancelled) catch {
    _ =>
      return result(
        id,
        compilation_failure("mep.frontend_failed", "Frontend failed"),
      )
  }
  if (self.cancelled)() {
    return result(
      id,
      compilation_failure("moonbit_frontend.cancelled", "Frontend cancelled"),
    )
  }
  let response = match compiled {
    CompilationFailed(diagnostics) =>
      result(id, { "success": false, "diagnostics": diagnostics })
    Compiled(input, modules, diagnostics) => {
      let model = compile_envelope(
        input,
        source,
        frontend.language_id,
        tuple,
        transport.limits,
        modules,
      ) catch {
        Refused(code) =>
          return result(
            id,
            compilation_failure(
              code,
              "Compiled model cannot be exported: " + code,
            ),
          )
        _ =>
          return result(
            id,
            compilation_failure(
              "mep.invalid_model", "Compiled model cannot be exported",
            ),
          )
      }
      result(id, {
        "success": true,
        "model": model,
        "diagnostics": diagnostics,
        "modules": modules,
      })
    }
  }
  if @utf8.encode(response.stringify()).length() > MAX_FRAME_BYTES {
    result(
      id,
      compilation_failure(
        "mep.response_limit", "Compiled model exceeds the MEP frame budget",
      ),
    )
  } else {
    response
  }
}

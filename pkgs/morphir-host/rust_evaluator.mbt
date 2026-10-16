///|
/// Conversion is local to this JSON provider. The engine retains Ion snapshots.
pub fn rust_classic_ir(unit : @data.IRUnit) -> @classic.IRFile raise {
  if !unit.metadata.is_empty() ||
    !unit.provenance.is_empty() ||
    unit.annotations.any(a => a.text() != Some("morphir_pipeline")) {
    raise @protocol.Invalid("conformance.rust_envelope_metadata")
  }
  let old = @migration.migrate(
    @versioned.V4(unit.distribution),
    @version.FormatVersion::baseline(3U),
  )
  guard old is V3(classic) else { abort("classic conversion") }
  if @migration.to_current(@versioned_json.read(@versioned_json.write(old))) !=
    unit.distribution {
    raise @protocol.Invalid("conformance.rust_lossy_ir_conversion")
  }
  classic
}

///|
/// The established intersection is deliberately narrower than the upstream
/// draft. All definitions are checked, since its preflight scans the whole model.
fn rust_supported_ir(file : @classic.IRFile) -> Unit raise {
  guard file.distribution is Library(_, _, definition) else {
    raise @protocol.Invalid("conformance.rust_unsupported_distribution")
  }
  for _, module_value in definition.modules {
    for _, value in module_value.value.values {
      match value.value.value.body {
        Literal(_, BoolLiteral(_)) | Variable(_, _) | Unit(_) => ()
        Literal(_, StringLiteral(s)) =>
          ignore(@sdk.Text::from_string(s).to_string())
        Literal(_, WholeNumberLiteral(n)) =>
          ignore(
            rust_wire_value(
              @protocol.Value::from_json({ "type": "int", "value": n }),
            ),
          )
        _ => raise @protocol.Invalid("conformance.rust_unsupported_expression")
      }
    }
  }
}

///|
fn rust_definition(
  file : @classic.IRFile,
  entry : String,
) -> @classic.ValueDefinition[Unit, @classic.Type[Unit]] raise {
  let name = @ir.FQName::parse(entry)
  guard file.distribution is Library(package_name, _, definition) &&
    package_name == name.package_name else {
    raise @protocol.Invalid("conformance.rust_entry")
  }
  guard definition.modules.get(name.module_name) is Some(module_definition) else {
    raise @protocol.Invalid("conformance.rust_entry")
  }
  guard module_definition.value.values.get(name.local_name) is Some(value) else {
    raise @protocol.Invalid("conformance.rust_entry")
  }
  value.value.value
}

///|
fn rust_wire_value(value : @protocol.Value) -> Json raise {
  match value {
    Integer(n) => {
      if n.to_string() != "0" &&
        (
          n.compare_int64(-9223372036854775808L) < 0 ||
          n.compare_int64(9223372036854775807L) > 0
        ) {
        raise @protocol.Invalid("conformance.rust_integer_range")
      }
      { "kind": "integer", "value": n.to_string() }
    }
    Boolean(b) => { "kind": "boolean", "value": b }
    Unit => { "kind": "unit" }
    Text(units) =>
      {
        "kind": "string",
        "value": @sdk.Text::from_units(units.map(n => n.to_uint16())).to_string(),
      }
    _ => raise @protocol.Invalid("conformance.rust_unsupported_value")
  }
}

///|
fn rust_supported_type(value : @protocol.ValueType) -> Bool {
  value is Int || value is Bool || value is Unit || value is Text
}

///|
fn rust_result(value : Json) -> @protocol.Value raise {
  match @wire.string(@wire.field(value, "kind")) {
    "integer" =>
      @protocol.Value::from_json({
        "type": "int",
        "value": @wire.string(@wire.field(value, "value")),
      })
    "boolean" =>
      @protocol.Value::from_json({
        "type": "bool",
        "value": @wire.field(value, "value"),
      })
    "unit" => @protocol.Unit
    "string" =>
      @protocol.Text(
        @sdk.Text::from_string(@wire.string(@wire.field(value, "value")))
        .to_units()
        .map(n => n.to_int()),
      )
    _ => raise @protocol.Invalid("conformance.rust_unsupported_result")
  }
}

///|
fn rust_binary_identity(
  program : String,
  helper : String,
  node : String,
) -> String raise {
  let result = @platform.process(
    node,
    [helper, "--identity", program],
    @platform.cwd(),
    "",
    5000,
  )
  if build_field(result, "exitCode") != Json::number(0.0) {
    raise @protocol.Invalid(
      "conformance.rust_identity_unavailable: " + build_text(result, "stderr"),
    )
  }
  @wire.string(
    @wire.field(@wire.parse(build_text(result, "stdout")), "binaryIdentity"),
  )
}

///|
pub fn rust_evaluator_lane(
  program : String,
  helper : String,
  pin : Json?,
  node~ : String = "node",
  required~ : Bool = false,
  timeout~ : Int32 = 5000,
  cancel_file~ : String = "",
) -> @conformance.EvaluatorLane raise {
  let unavailable : @conformance.EvaluatorLane = {
    name: "rust",
    required,
    evaluator: None,
    unsupported: fn(_, _) { None },
    evidence: { "protocol": "1.1.0-draft.1", "reason": "missing_binary_or_pin" },
  }
  if program == "" || pin is None {
    return unavailable
  }
  if !@platform.process_supported() ||
    @platform.kind(program) != 1 ||
    helper == "" ||
    @platform.kind(helper) != 1 {
    return {
      ..unavailable,
      evidence: {
        "protocol": "1.1.0-draft.1",
        "reason": "provider_unavailable",
      },
    }
  }
  let pin = pin.unwrap()
  if @wire.string(@wire.field(pin, "profile")) !=
    "morphir-rust-evaluator-pin-v1" ||
    @wire.string(@wire.field(pin, "protocol")) != "1.1.0-draft.1" {
    raise @protocol.Invalid("conformance.rust_pin_profile")
  }
  let source = @wire.string(@wire.field(pin, "sourceRevision"))
  let runtime = @wire.string(@wire.field(pin, "runtimeRevision"))
  let identity = @wire.string(@wire.field(pin, "binaryIdentity"))
  fn hex(value : String, size : Int32) -> Bool {
    value.length() == size &&
    value.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
  if !hex(source, 40) ||
    !hex(runtime, 40) ||
    !hex(identity, 64) ||
    timeout < 1 ||
    timeout > 300000 {
    raise @protocol.Invalid("conformance.rust_pin_identity")
  }
  if rust_binary_identity(program, helper, node) != identity {
    raise @protocol.Invalid("conformance.rust_binary_identity")
  }
  let helper_identity = @identity.sha256(@platform.read_bytes(helper))
  {
    name: "rust",
    required,
    evidence: {
      "sourceRevision": source,
      "runtimeRevision": runtime,
      "binaryIdentity": identity,
      "helperIdentity": helper_identity,
      "protocol": "1.1.0-draft.1",
      "conversion": "lossless-classic-v3-roundtrip",
      "supportedTypes": ["int64", "bool", "unit", "valid-utf16-text"],
      "supportedIR": "sdk-free scalar literal and identity definitions",
      "errorMappings": {
        "runtime": "conformance.rust_runtime_error",
        "codec": "unsupported",
        "unavailable": "unavailable",
      },
    },
    unsupported: fn(plan, call) {
      try {
        rust_supported_ir(rust_classic_ir(plan.unit))
        let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
        if !rust_supported_type(entry.output) ||
          !entry.inputs.all(rust_supported_type) {
          return Some("conformance.rust_unsupported_type")
        }
        for argument in call.arguments {
          ignore(rust_wire_value(argument))
        }
        None
      } catch {
        @wire.Invalid(code, detail) =>
          Some("conformance.rust_ir: " + code + ": " + detail)
        @protocol.Invalid(code) => Some(code)
        @sdk.UnrepresentableText(_) =>
          Some("conformance.rust_unrepresentable_utf16")
        _ => Some("conformance.rust_unsupported_conversion")
      }
    },
    evaluator: Some({
      profile: "rust-classic-v3/1.1.0-draft.1/int64-bounded",
      evaluate: fn(unit, call, output, definitions) raise {
        if rust_binary_identity(program, helper, node) != identity ||
          @identity.sha256(@platform.read_bytes(helper)) != helper_identity {
          raise @protocol.Invalid("conformance.rust_changed_binary_or_helper")
        }
        let file = rust_classic_ir(unit)
        rust_supported_ir(file)
        let definition = rust_definition(file, call.entry)
        if call.arguments.length() != definition.input_types.length() {
          raise @protocol.Invalid("conformance.rust_arity")
        }
        let arguments : Array[Json] = []
        for i, argument in call.arguments {
          arguments.push({
            "type": @classic_json.write_type(definition.input_types[i].2, fn(
              value,
            ) raise {
              @wire.write_unit(value)
            }),
            "value": rust_wire_value(argument),
          })
        }
        let request : Json = {
          "version": "1.1.0-draft.1",
          "provider": "morphir_ir",
          "program": {
            "kind": "morphir_ir",
            "distribution": @versioned_json.to_json(@versioned.V3(file)),
          },
          "calls": [
            { "id": call.id, "entrypoint": call.entry, "arguments": arguments },
          ],
          "limits": { "fuel": 100000, "maxCallDepth": 128 },
          "timeout_ms": timeout,
        }
        let bytes = @utf8.encode(request.stringify())
        if bytes.length() > 8388608 {
          raise @protocol.Invalid("conformance.rust_request_limit")
        }
        let directory = @platform.temporary()
        let path = directory + "/request.json"
        let mut retained = false
        let outcome = try {
          @platform.write(
            path,
            (
              {
                "profile": "morphir-rust-evaluator-worker-v1",
                "program": program,
                "binaryIdentity": identity,
                "helperIdentity": helper_identity,
                "input": request.stringify(),
                "timeout": timeout,
                "cancelFile": cancel_file,
              } : Json).stringify(),
          )
          let result = @platform.process(
            node,
            [helper, path],
            @platform.cwd(),
            "",
            timeout + 6000,
          )
          let diagnostic = build_text(result, "stderr")
          let code = build_field(result, "exitCode")
          if diagnostic.contains("execution.tree_termination_failed") ||
            diagnostic.contains("execution.tree_termination_unavailable") ||
            (match code {
              Number(n, ..) => n == -1.0 || n == 124.0 || n >= 128.0
              _ => true
            }) {
            retained = true
            raise @protocol.Invalid(
              "conformance.rust_provider_terminated: " +
              code.stringify() +
              ": " +
              diagnostic,
            )
          }
          if code != Json::number(0.0) {
            raise @protocol.Invalid(
              "conformance.rust_provider_failed: " + diagnostic,
            )
          }
          let response = @wire.parse(build_text(result, "stdout"))
          if @wire.string(@wire.field(response, "profile")) !=
            "morphir-rust-evaluator-result-v1" ||
            @wire.string(@wire.field(response, "binaryIdentity")) != identity ||
            @wire.string(@wire.field(response, "helperIdentity")) !=
            helper_identity ||
            @wire.string(@wire.field(response, "requestIdentity")) !=
            @identity.sha256(bytes) {
            raise @protocol.Invalid("conformance.rust_receipt_identity")
          }
          let report = @wire.field(response, "report")
          if @wire.string(@wire.field(report, "version")) != "1.1.0-draft.1" ||
            @wire.string(@wire.field(report, "provider")) != "morphir_ir" {
            raise @protocol.Invalid("conformance.rust_protocol")
          }
          let results = @wire.tuple(@wire.field(report, "results"), 1)
          let result = results[0]
          if @wire.string(@wire.field(result, "id")) != call.id ||
            @wire.string(@wire.field(result, "entrypoint")) != call.entry {
            raise @protocol.Invalid("conformance.rust_call_identity")
          }
          if @wire.string(@wire.field(result, "status")) == "error" {
            raise @protocol.Invalid(
              "conformance.rust_runtime_error: " +
              @wire.string(@wire.field(result, "code")),
            )
          }
          if @wire.string(@wire.field(result, "status")) != "value" {
            raise @protocol.Invalid("conformance.rust_status")
          }
          let value = @wire.field(result, "value")
          if @classic_json.read_type(@wire.field(value, "type"), fn(
              value,
            ) raise {
              @wire.unit(value)
            }) !=
            definition.output_type {
            raise @protocol.Invalid("conformance.rust_return_type")
          }
          let value = rust_result(@wire.field(value, "value"))
          ignore(rust_wire_value(value))
          @protocol.validate_as(value, output, definitions, output=true)
          if rust_binary_identity(program, helper, node) != identity ||
            @identity.sha256(@platform.read_bytes(helper)) != helper_identity {
            raise @protocol.Invalid("conformance.rust_changed_binary_or_helper")
          }
          Ok(value)
        } catch {
          error => Err(error)
        }
        let cleanup : Error? = if retained {
          Some(
            @protocol.Invalid(
              "conformance.rust_tree_cleanup_pending: " + directory,
            ),
          )
        } else {
          try {
            @platform.remove_dir(directory)
            None
          } catch {
            error => Some(error)
          }
        }
        match (outcome, cleanup) {
          (Ok(value), None) => value
          (Err(error), None) => raise error
          (result, Some(error)) =>
            raise @execution.CleanupFailed(
              match result {
                Err(primary) => Some(primary)
                _ => None
              },
              error,
            )
        }
      },
    }),
  }
}

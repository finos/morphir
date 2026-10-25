///|
fn execution_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let conform = cli.command == "conform"
  let options : Map[String, String] = Map([])
  for name in execution_options + conformance_options {
    if name != "dependency" && !values(cli, name).is_empty() {
      options["--" + name] = value(cli, name)
    }
  }
  let dependencies : Map[String, String] = Map([])
  for dependency in values(cli, "dependency") {
    guard dependency.split_once("=") is Some((name, path)) &&
      name != "" &&
      path != "" else {
      raise @config.Invalid("Expected module=path")
    }
    if dependencies.contains(name.to_owned()) {
      raise @config.Invalid("Duplicate dependency")
    }
    dependencies[name.to_owned()] = path.to_owned()
  }
  let model = value(cli, "path")
  let dry_run = flag(cli, "dry-run")
  if model == "" ||
    !options.contains(if conform { "--cases" } else { "--suite" }) {
    raise @config.Invalid(
      "execution requires a model and " +
      (if conform { "--cases" } else { "--suite" }),
    )
  }
  if conform &&
    (
      options.contains("--suite") ||
      options.contains("--comparison") ||
      options.contains("--absolute-tolerance") ||
      options.contains("--relative-tolerance")
    ) {
    raise @config.Invalid(
      "conformance requires exact expectations without --suite",
    )
  }
  if !conform &&
    options
    .keys()
    .any(k => {
      [
        "--cases", "--cases-format", "--evaluators", "--require-evaluator", "--rust-evaluator",
        "--rust-evaluator-pin", "--rust-helper", "--receipt", "--receipt-format",
      ].contains(k)
    }) {
    raise @config.Invalid("conformance options require conform")
  }
  let receipt_format = options.get("--receipt-format").unwrap_or("ion-binary")
  if !["ion-binary", "ion-text", "json"].contains(receipt_format) {
    raise @config.Invalid("conformance.receipt_format")
  }
  if options.contains("--receipt-format") && !options.contains("--receipt") {
    raise @config.Invalid("conformance.receipt_required")
  }
  let build_mode = options.get("--build-mode").unwrap_or("debug")
  if !["debug", "release"].contains(build_mode) {
    raise @config.Invalid("execution.invalid_build_mode")
  }
  let comparison = match options.get("--comparison").unwrap_or("exact") {
    "exact" => {
      if options.contains("--absolute-tolerance") ||
        options.contains("--relative-tolerance") {
        raise @config.Invalid("execution.explicit_approximate_required")
      }
      @protocol.Exact
    }
    "approximate" =>
      @protocol.Approximate(
        @string.parse_double(options.get("--absolute-tolerance").unwrap_or("0")),
        @string.parse_double(options.get("--relative-tolerance").unwrap_or("0")),
      )
    _ => raise @config.Invalid("execution.comparison_policy")
  }
  comparison.validate()
  let adapter = options.get("--telemetry-adapter").unwrap_or("local")
  if !["local", "none", "opentelemetry-native"].contains(adapter) {
    raise @config.Invalid("observability.adapter_unavailable: " + adapter)
  }
  let native_telemetry = if adapter == "opentelemetry-native" {
    if options.contains("--log-file") {
      raise @config.Invalid("observability.native_adapter_exclusive_sink")
    }
    let required = [
      "--otel-binary", "--otel-pin", "--otel-helper", "--otel-endpoint",
    ]
    if required.any(key => !options.contains(key)) {
      raise @config.Invalid(
        "observability.native_adapter_explicit_configuration_required",
      )
    }
    let endpoint = options["--otel-endpoint"]
    let protocol = options.get("--otel-protocol").unwrap_or("http/json")
    let flush_timeout = build_timeout(
      options.get("--otel-flush-timeout").unwrap_or("1000"),
    )
    if !@host.native_telemetry_endpoint(endpoint) ||
      protocol != "http/json" ||
      flush_timeout > 5000 {
      raise @config.Invalid("observability.native_adapter_configuration")
    }
    // Dry-run validates options without opening files, probing or exporting.
    if dry_run {
      None
    } else {
      if @platform.kind(options["--otel-pin"]) != 1 {
        raise @config.Invalid("observability.native_adapter_pin_file")
      }
      Some(
        @host.NativeTelemetry::new(
          options["--otel-binary"],
          options["--otel-helper"],
          options["--otel-endpoint"],
          options.get("--otel-protocol").unwrap_or("http/json"),
          @json.parse(@platform.read(options["--otel-pin"])),
          timeout=build_timeout(
            options.get("--otel-flush-timeout").unwrap_or("1000"),
          ),
        ),
      )
    }
  } else {
    if options.keys().any(key => key.has_prefix("--otel-")) {
      raise @config.Invalid("observability.native_adapter_selection_required")
    }
    None
  }
  let pin = options
    .get("--toolchain-pin")
    .map(path => @json.parse(@platform.read(path)))
  let logs = if native_telemetry is Some(_) {
    @host.TelemetrySession::new(
      if dry_run {
        None
      } else {
        Some("native-export")
      },
      format=options.get("--log-format").unwrap_or("ion-binary"),
    )
  } else {
    @host.TelemetrySession::for_project(
      @platform.cwd(),
      if dry_run || adapter == "none" {
        None
      } else {
        options.get("--log-file")
      },
      enabled=flag(cli, "log") && !dry_run && adapter != "none",
      format=options.get("--log-format").unwrap_or("ion-binary"),
    )
  }
  // Dry runs never open a log file or acquire a process session.
  let observer = if dry_run {
    @observe.Observer::noop()
  } else {
    logs.observer()
  }
  let flush_logs = fn() {
    match native_telemetry {
      Some(adapter) =>
        logs.flush_native(adapter, options.get("--node").unwrap_or("node"))
      None => logs.flush()
    }
  }
  errdefer flush_logs()
  let available = match pin {
    Some(value) => execution_pin_targets(value)
    None => ["js", "wasm-gc", "native"]
  }
  let mut expectations : @conformance.Expectations? = None
  let scope = observer.scope()
  let plan = scope.observe(@observe.Plan, fn(scope) raise {
    let unit = scope.observe(@observe.Decode, fn(_) raise {
      let format = options
        .get("--model-format")
        .unwrap_or(
          if model.has_suffix(".ionb") || model.has_suffix(".10n") {
            "ion-binary"
          } else if model.has_suffix(".ion") {
            "ion-text"
          } else {
            "morphir-json"
          },
        )
      let content = if format == "ion-binary" {
        @data.Binary(@platform.read_bytes(model))
      } else {
        @data.Text(@platform.read(model))
      }
      @data.Registry::new().decode(format, {
        unit_id: options.get("--unit-id").unwrap_or("model"),
        content,
      })
    })
    let path = options[if conform { "--cases" } else { "--suite" }]
    let format = options
      .get(if conform { "--cases-format" } else { "--suite-format" })
      .unwrap_or(
        if path.has_suffix(".ionb") || path.has_suffix(".10n") {
          "ion-binary"
        } else if path.has_suffix(".json") {
          "json"
        } else {
          "ion-text"
        },
      )
    let suite = if conform {
      let cases = @conformance.Expectations::decode(
        @platform.read_bytes(path),
        format~,
      )
      expectations = Some(cases)
      cases.suite()
    } else {
      @protocol.Suite::decode(@platform.read_bytes(path), format)
    }
    scope.observe(@observe.Generate, fn(_) raise {
      @execution.plan(
        unit,
        suite,
        target=options.get("--target").unwrap_or("js"),
        available_targets=available,
      )
    })
  })
  let conformance_plan = if conform {
    let selected = options
      .get("--evaluators")
      .unwrap_or("scheme,rust")
      .split(",")
      .map(s => s.to_owned())
      .collect()
    let required = options
      .get("--require-evaluator")
      .unwrap_or("")
      .split(",")
      .map(s => s.to_owned())
      .filter(s => s != "")
      .collect()
    if selected.is_empty() ||
      selected.any(s => !["scheme", "rust"].contains(s)) ||
      required.any(s => !selected.contains(s)) {
      raise @config.Invalid("conformance.evaluator_selection")
    }
    let lanes = selected.map(name => {
      if name == "scheme" {
        @conformance.EvaluatorLane::scheme()
      } else {
        @host.rust_evaluator_lane(
          options.get("--rust-evaluator").unwrap_or(""),
          options.get("--rust-helper").unwrap_or(""),
          options
          .get("--rust-evaluator-pin")
          .map(path => @json.parse(@platform.read(path))),
          node=options.get("--node").unwrap_or("node"),
          required=required.contains("rust"),
          timeout=build_timeout(options.get("--timeout").unwrap_or("5000")),
          cancel_file=options.get("--cancel-file").unwrap_or(""),
        )
      }
    })
    Some(@conformance.prepare(plan, expectations.unwrap(), lanes~))
  } else {
    None
  }
  if dry_run {
    let result : Json = {
      "dryRun": true,
      "capabilityVerification": "deferred",
      "target": plan.target,
      "buildMode": build_mode,
      "comparison": comparison.to_json(),
      "calls": plan.suite.calls.map(c => c.id),
      "entries": plan.suite.calls.map(c => c.entry),
      "evaluator": if conform {
        "independent+configured-live"
      } else if cli.command == "verify" {
        "scheme-portable-v1/shared-sdk/bounded"
      } else {
        "none"
      },
    }
    if mode is Human {
      println(
        "Planned " +
        plan.suite.calls.length().to_string() +
        " call(s) for " +
        plan.target,
      )
    } else {
      emit_result(result, mode)
    }
    return 0
  }
  let provider = if dry_run {
    None
  } else {
    Some(
      @host.process_execution(
        options.get("--node").unwrap_or("node"),
        options.get("--execution-helper").unwrap_or(""),
        options.get("--home").unwrap_or(""),
        dependencies,
        timeout=build_timeout(options.get("--timeout").unwrap_or("120000")),
        toolchain_pin=pin,
        build_mode~,
        cancel_file=options.get("--cancel-file").unwrap_or(""),
        observer~,
      ),
    )
  }
  if conformance_plan is Some(prepared) {
    let result = @conformance.run(prepared, provider.unwrap(), observer~, cancelled=fn() {
      match options.get("--cancel-file") {
        Some(path) => (@platform.kind(path) catch { _ => 1 }) != 0
        None => false
      }
    })
    flush_logs()
    if options.get("--receipt") is Some(path) {
      @platform.write_bytes(path, result.encode(format=receipt_format))
    }
    if mode is Human {
      for lane in result.coverage {
        for call in lane.calls {
          println(
            lane.provider +
            " " +
            call.id +
            ": " +
            call.status +
            call.mismatch_path.map(p => " at " + p).unwrap_or("") +
            call.reason.map(r => " " + r).unwrap_or(""),
          )
        }
      }
    } else {
      emit_result(result.to_json(), mode)
    }
    return if result.cancelled() {
      130
    } else if result.successful() {
      0
    } else {
      1
    }
  }
  let result = @execution.run_report(
    plan,
    provider.unwrap(),
    evaluator=if cli.command == "verify" {
      Some(@execution.Evaluator::scheme())
    } else {
      None
    },
    observer~,
    comparison~,
    cancelled=fn() {
      match options.get("--cancel-file") {
        Some(path) => (@platform.kind(path) catch { _ => 1 }) != 0
        None => false
      }
    },
  )
  flush_logs()
  if mode is Human {
    if result.failure is Some(failure) {
      @platform.stderr(failure.to_json().stringify() + "\n")
    }
    for call in result.calls {
      println(
        call.id +
        ": " +
        call.actual.to_json().stringify() +
        (if call.matches { "" } else { " MISMATCH" }),
      )
    }
  } else {
    emit_result(result.to_json(), mode)
  }
  if result.successful() {
    0
  } else {
    1
  }
}

///|
/// A dry run validates declared pin shape without invoking or acquiring tooling.
fn execution_pin_targets(pin : Json) -> Array[String] raise {
  guard pin is Object(fields) else {
    raise @config.Invalid("execution.invalid_pin")
  }
  fn text(name : String) -> String raise {
    guard fields.get(name) is Some(String(s)) else {
      raise @config.Invalid("execution.invalid_pin")
    }
    s
  }
  fn digest(s : String) -> Bool {
    s.length() == 64 &&
    s.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
  if text("profile") != "morphir-toolchain-pin-v1" ||
    !digest(text("compilerIdentity")) ||
    !digest(text("coreIdentity")) {
    raise @config.Invalid("execution.invalid_pin")
  }
  guard fields.get("targets") is Some(Array(items)) else {
    raise @config.Invalid("execution.invalid_pin")
  }
  let targets : Array[String] = []
  for item in items {
    guard item is String(target) else {
      raise @config.Invalid("execution.invalid_pin")
    }
    if targets.contains(target) ||
      !["js", "wasm-gc", "native", "llvm"].contains(target) {
      raise @config.Invalid("execution.invalid_pin")
    }
    targets.push(target)
  }
  if targets.contains("llvm") &&
    (
      targets.length() != 1 ||
      text("compilerVersion") != "0.10.15+1e9f6672d-nightly" ||
      text("platform") != "darwin" ||
      text("arch") != "arm64"
    ) {
    raise @config.Invalid("execution.unverified_llvm_pin")
  }
  if !targets.contains("llvm") &&
    text("compilerVersion") != @toolchain.compiler_version {
    raise @config.Invalid("execution.unverified_stable_pin")
  }
  if targets.is_empty() {
    raise @config.Invalid("execution.invalid_pin")
  }
  targets
}

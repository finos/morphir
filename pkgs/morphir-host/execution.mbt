///|
fn invocation_snapshot(files : Array[@moonbit.Artifact]) -> String {
  let sorted = files.copy()
  sorted.sort_by(fn(a, b) { a.path.compare(b.path) })
  Json::array(
    sorted.map(a => {
      Json::array([
        Json::string(a.path),
        match a.content {
          Text(s) => Json::array([Json::string("text"), Json::string(s)])
          Binary(b) =>
            Json::array([
              Json::string("binary"),
              Json::array(
                b.to_array().map(v => Json::number(v.to_int().to_double())),
              ),
            ])
        },
      ])
    }),
  ).stringify()
}

///|
fn entry_manifest(plan : @execution.Plan) -> String {
  Json::array(
    plan.library.invocations.map(e => {
      (
        {
          "fqname": e.fqname,
          "generatedName": e.generated_name,
          "inputs": e.inputs.map(t => t.name()),
          "output": e.output.name(),
          "inputTypes": e.inputs.map(t => t.to_json()),
          "outputType": e.output.to_json(),
          "customTypes": plan.library.invocation_types.map(t => {
            (
              {
                "name": t.name,
                "constructors": t.constructors.map(c => {
                  (
                    { "name": c.name, "inputs": c.inputs.map(t => t.to_json()) } :
                    Json)
                }),
              } : Json)
          }),
        } : Json)
    }),
  ).stringify()
}

///|
fn execution_driver_main(target : String) -> Array[@moonbit.Artifact] {
  let io = match target {
    "js" =>
      (
        #|#module("node:fs")
        #|extern "js" fn read(path : String) -> Bytes = "readFileSync"
        #|fn read_input() -> Bytes { read(arg(2)) }
        #|#module("node:fs")
        #|extern "js" fn write(path : String, bytes : Bytes) -> Unit = "writeFileSync"
        #|fn write_output(bytes : Bytes) -> Unit { write(arg(3),bytes) }
        #|extern "js" fn arg(i : Int) -> String = "i => process.argv[i]"
        #|fn trace_header() -> String { arg(5) }
        #|extern "js" fn identity() -> String = "() => process.argv[4]"
        #|extern "js" fn clock() -> Double = "() => Number(process.hrtime.bigint())/1e9"
        #|
      )
    "native" | "llvm" =>
      (
        #|fn read_input() -> Bytes raise { @fs.read_file_to_bytes(@env.args()[1]) }
        #|fn write_output(bytes : Bytes) -> Unit raise { @fs.write_bytes_to_file(@env.args()[2],bytes) }
        #|fn identity() -> String { @env.args()[3] }
        #|fn trace_header() -> String { @env.args()[4] }
        #|extern "C" fn clock() -> Double = "morphir_driver_monotonic"
        #|
      )
    _ =>
      (
        #|extern "wasm" fn trace_length() -> Int = "morphir_execution_v1" "trace_length"
        #|extern "wasm" fn trace_char(i : Int) -> Int = "morphir_execution_v1" "trace_char"
        #|fn trace_header() -> String { String::from_array(Array::makei(trace_length(), i => trace_char(i).unsafe_to_char())) }
        #|extern "wasm" fn input_length() -> Int = "morphir_execution_v1" "input_length"
        #|extern "wasm" fn input_byte(i : Int) -> Int = "morphir_execution_v1" "input_byte"
        #|extern "wasm" fn identity_length() -> Int = "morphir_execution_v1" "identity_length"
        #|extern "wasm" fn identity_char(i : Int) -> Int = "morphir_execution_v1" "identity_char"
        #|extern "wasm" fn output_begin(size : Int) -> Unit = "morphir_execution_v1" "output_begin"
        #|extern "wasm" fn output_byte(i : Int, byte : Int) -> Unit = "morphir_execution_v1" "output_byte"
        #|extern "wasm" fn clock() -> Double = "morphir_execution_v1" "monotonic"
        #|fn read_input() -> Bytes { Bytes::makei(input_length(), i => input_byte(i).to_byte()) }
        #|fn identity() -> String { String::from_array(Array::makei(identity_length(), i => identity_char(i).unsafe_to_char())) }
        #|fn write_output(bytes : Bytes) -> Unit { output_begin(bytes.length()); for i = 0; i < bytes.length(); i = i+1 { output_byte(i,bytes[i].to_int()) } }
        #|
      )
  }
  let source = io +
    (
      #|///|
      #|fn main {
      #|  try {
      #|    let traceparent = trace_header()
      #|    if traceparent != "" { ignore(@observe.TraceContext::parse(traceparent)) }
      #|    let suite = @execution.Suite::decode(read_input(), "ion-binary")
      #|    let values = suite.calls.map(call => {
      #|      let start = if traceparent == "" { 0.0 } else { clock() }
      #|      let value = @driver.invoke(call)
      #|      let duration = if traceparent == "" { 0.0 } else { clock() - start }
      #|      @execution.record([
      #|        ("id",@ion.IonValue::string(call.id)),
      #|        ("value",value.to_ion()),
      #|        ("duration_seconds",@ion.IonValue::float(duration)),
      #|      ])
      #|    })
      #|    write_output(@binary.write_binary_value(@execution.record([
      #|      ("profile",@ion.IonValue::string("morphir-outcomes-v1")),
      #|      ("suite_identity",@ion.IonValue::string(identity())),
      #|      ("calls",@ion.IonValue::list(values)),
      #|      ("traceparent",@ion.IonValue::string(traceparent)),
      #|      ("extensions",suite.extension_value()),
      #|    ])))
      #|  } catch { _ => abort("execution.driver_failed") }
      #|}
      #|
    )
  let native = target == "native" || target == "llvm"
  let files : Array[@moonbit.Artifact] = [
    { path: "main/main.mbt", role: Source, content: Text(source), },
    {
      path: "main/moon.pkg",
      role: PackageManifest,
      content: Text(
        "pkgtype(kind: \"executable\")\nimport {\n\"morphir-generated/driver\" @driver,\n\"finos/morphir-execution\" @execution,\n\"finos/morphir-execution/observability\" @observe,\n\"moonrockz/ion/ion\",\n\"moonrockz/ion/binary\",\n" +
        (if native {
          "\"moonbitlang/x/fs\",\n\"moonbitlang/core/env\",\n"
        } else {
          ""
        }) +
        "}\n" +
        (if native { "options(\"native-stub\": [\"clock.c\"])\n" } else { "" }),
      ),
    },
  ]
  if native {
    files.push({
      path: "main/clock.c",
      role: Source,
      content: Text(
        (
          #|#include <time.h>
          #|double morphir_driver_monotonic(void) {
          #|  struct timespec value;
          #|  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0.0;
          #|  return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
          #|}
          #|
        ),
      ),
    })
  }
  files
}

///|
/// An explicit process session owns scratch state until disposal, including failed builds.
pub fn process_execution(
  program : String,
  helper : String,
  compiler_home : String,
  dependencies : Map[String, String],
  timeout~ : Int32 = 120000,
  toolchain_pin~ : Json? = None,
  build_mode~ : String = "debug",
  cancel_file~ : String = "",
  payload_capture~ : @observe.PayloadCapture = @observe.PayloadCapture::disabled(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> @execution.Provider raise {
  if !["debug", "release"].contains(build_mode) {
    raise @config.Invalid("execution.invalid_build_mode")
  }
  if !@platform.process_supported() ||
    program == "" ||
    helper == "" ||
    compiler_home == "" ||
    timeout < 1 ||
    timeout > 600000 {
    raise @config.Invalid("execution.provider_required")
  }
  let capability_directory = @platform.temporary()
  let capabilities = {
    errdefer dispose_build_tree(capability_directory)
    let path = capability_directory + "/capabilities.json"
    @platform.write(
      path,
      (
        {
          "operation": "capabilities",
          "compilerHome": compiler_home,
          "toolchainPin": toolchain_pin.unwrap_or(Json::null()),
          "timeout": timeout,
        } : Json).stringify(),
    )
    let response = @platform.process(
      program,
      [helper, path],
      @platform.cwd(),
      "",
      timeout,
    )
    if build_field(response, "exitCode") != Json::number(0.0) {
      raise @config.Invalid(
        "execution.capability_unavailable: " + build_text(response, "stderr"),
      )
    }
    let value = @wire.parse(build_text(response, "stdout"))
    dispose_build_tree(capability_directory)
    value
  }
  if build_text(capabilities, "profile") != "morphir-execution-capabilities-v1" {
    raise @config.Invalid("execution.invalid_capabilities")
  }
  let descriptors = match build_field(capabilities, "targets") {
    Array(items) => items
    _ => raise @config.Invalid("execution.invalid_capabilities")
  }
  let targets : Array[String] = []
  for descriptor in descriptors {
    let target = build_text(descriptor, "target")
    if targets.contains(target) ||
      !["js", "wasm-gc", "native", "llvm"].contains(target) ||
      !(build_field(descriptor, "compile") is True) ||
      !(build_field(descriptor, "run") is True) ||
      build_text(descriptor, "protocol") != "morphir-invocations-v1/ion-binary" {
      raise @config.Invalid("execution.invalid_capabilities")
    }
    targets.push(target)
  }
  let supplied = dependencies.copy()
  {
    targets,
    acquire: fn() raise {
      let directory = @platform.temporary()
      let id = @identity.sha256(@utf8.encode(directory))
      let mut disposed = false
      let mut poisoned = false
      let mut tree_cleanup_pending = false
      let mut built : Json? = None
      let mut attempt = 0
      fn request(fields : Map[String, Json]) -> Json raise {
        if disposed {
          raise @config.Invalid("execution.disposed")
        }
        if poisoned {
          raise @config.Invalid("execution.poisoned")
        }
        if cancel_file != "" && @platform.kind(cancel_file) != 0 {
          raise @protocol.Invalid("Cancelled")
        }
        errdefer {
          poisoned = true
        }
        fields["cancelFile"] = Json::string(cancel_file)
        fields["toolchainPin"] = toolchain_pin.unwrap_or(Json::null())
        fields["leaseId"] = Json::string(id)
        fields["timeout"] = Json::number(
          (if timeout < 10 { 1 } else { timeout * 9 / 10 }).to_double(),
        )
        let path = directory + "/request.json"
        @platform.write(path, Json::object(fields).stringify())
        let result = @platform.process(
          program,
          [helper, path],
          @platform.cwd(),
          "",
          timeout,
        )
        let exit_code = build_field(result, "exitCode")
        if exit_code != Json::number(0.0) {
          let diagnostic = build_text(result, "stderr")
          // Native helpers report signal death as 128 + signal. The runner owns
          // a separate group, so abrupt helper exit cannot prove it stopped.
          let termination_unconfirmed = match exit_code {
            Number(code, ..) => code == -1.0 || code == 124.0 || code >= 128.0
            _ => true
          }
          if diagnostic.contains("execution.tree_termination_failed") ||
            diagnostic.contains("execution.tree_termination_unavailable") ||
            termination_unconfirmed {
            tree_cleanup_pending = true
          }
          if diagnostic.has_prefix("execution.cancelled") ||
            diagnostic.has_prefix("build.cancelled") {
            raise @protocol.Invalid("Cancelled")
          }
          raise @config.Invalid(
            "execution.provider_failed: " +
            (if diagnostic.length() > 1024 {
              diagnostic[:1024].to_owned()
            } else {
              diagnostic
            }),
          )
        }
        @wire.parse(build_text(result, "stdout"))
      }
      {
        id,
        build: fn(plan, trace) raise {
          if disposed {
            raise @config.Invalid("execution.disposed")
          }
          if poisoned {
            raise @config.Invalid("execution.poisoned")
          }
          errdefer {
            poisoned = true
          }
          if built is Some(_) {
            raise @config.Invalid("execution.already_built")
          }
          guard descriptors
            .filter(d => build_text(d, "target") == plan.target)
            .get(0)
            is Some(descriptor) else {
            raise @config.Invalid("execution.provider_target")
          }
          let snapshot = invocation_snapshot(plan.library.artifacts)
          let driver_files = plan.driver + execution_driver_main(plan.target)
          let deps = plan.library.project.dependencies.map(d => @engine.ProjectDependency::{
            module_name: d.module_name,
            version: d.version,
            api_profile: d.api_profile,
            semantic_pin: d.semantic_pin,
          })
          for
            (module_name, version, api_profile, semantic_pin) in [
              (
                "finos/morphir-execution", "0.1.0", "morphir-invocations-v1", "morphir-invocations-v1",
              ),
              ("moonrockz/ion", "0.3.0", "ion-v1", "ion-0.3.0"),
              ("moonbitlang/x", "0.5.5", "moonbit-x", "x-0.5.5"),
              ("moonbitlang/async", "0.22.4", "moonbit-async", "async-0.22.4"),
            ] {
            deps.push({ module_name, version, api_profile, semantic_pin, })
          }
          let project : @engine.LibraryProject = {
            id: plan.library.project.module_name,
            source: plan.unit.id,
            root: "generated",
            members: plan.library.project.members,
            dependencies: deps,
            build_contract: "moonbit-library-v1",
            policy: @engine.Required(plan.target),
          }
          let source_identity = @identity.sha256(@utf8.encode(snapshot))
          let driver = invocation_snapshot(driver_files)
          let manifest = entry_manifest(plan)
          let result = request(
            Map::from_array([
              ("operation", Json::string("build")),
              ("buildMode", Json::string(build_mode)),
              (
                "traceparent",
                trace.map(t => Json::string(t.header())).unwrap_or(Json::null()),
              ),
              ("projectId", Json::string(project.id)),
              ("contract", Json::string(project.build_contract)),
              ("snapshot", Json::string(snapshot)),
              ("sourceIdentity", Json::string(source_identity)),
              ("target", Json::string(plan.target)),
              ("driver", Json::string(driver)),
              ("manifest", Json::string(manifest)),
              ("compilerHome", Json::string(compiler_home)),
              (
                "suppliedDependencies",
                Json::object(supplied.map(fn(_, path) { Json::string(path) })),
              ),
              (
                "dependencies",
                Json::array(
                  deps.map(d => {
                    (
                      {
                        "moduleName": d.module_name,
                        "version": d.version,
                        "apiProfile": d.api_profile,
                        "semanticPin": d.semantic_pin,
                      } : Json)
                  }),
                ),
              ),
            ]),
          )
          validate_evidence(
            { project, snapshot, source_identity, target: plan.target, },
            id,
            result,
            compiler_version=build_text(capabilities, "compilerVersion"),
          )
          if build_text(result, "buildMode") != build_mode ||
            build_text(result, "driverIdentity") !=
            @identity.sha256(@utf8.encode(driver)) ||
            build_text(result, "manifestIdentity") !=
            @identity.sha256(@utf8.encode(manifest)) ||
            !digest_shape(build_text(result, "executableIdentity")) ||
            !digest_shape(build_text(result, "runtimeIdentity")) ||
            build_field(result, "capability") != descriptor ||
            build_text(result, "runtimeIdentity") !=
            build_text(build_field(descriptor, "runtime"), "identity") ||
            build_text(result, "compilerIdentity") !=
            build_text(capabilities, "compilerIdentity") ||
            build_text(result, "coreIdentity") !=
            build_text(capabilities, "coreIdentity") {
            raise @config.Invalid("execution.evidence_mismatch")
          }
          built = Some(result)
          result
        },
        invoke: fn(suite, trace) raise {
          if disposed {
            raise @config.Invalid("execution.disposed")
          }
          if poisoned {
            raise @config.Invalid("execution.poisoned")
          }
          errdefer {
            poisoned = true
          }
          guard built is Some(evidence) else {
            raise @config.Invalid("execution.not_built")
          }
          if disposed {
            raise @config.Invalid("execution.disposed")
          }
          attempt += 1
          let bytes = suite.encode("ion-binary")
          let suite_identity = @identity.sha256(bytes)
          let output = directory + "/outcomes.ionb"
          if @platform.kind(output) != 0 {
            @platform.remove_file(output)
          }
          @platform.write_bytes(directory + "/suite.ionb", bytes)
          let result = request(
            Map::from_array([
              ("operation", Json::string("invoke")),
              ("attemptId", Json::string(attempt.to_string())),
              (
                "traceparent",
                trace.map(t => Json::string(t.header())).unwrap_or(Json::null()),
              ),
              ("target", build_field(evidence, "target")),
              ("suiteIdentity", Json::string(suite_identity)),
            ]),
          )
          if build_text(result, "leaseId") != id ||
            build_text(result, "suiteIdentity") != suite_identity ||
            build_text(result, "target") != build_text(evidence, "target") ||
            build_text(result, "attemptId") != attempt.to_string() ||
            build_text(result, "traceparent") !=
            trace.map(t => t.header()).unwrap_or("") ||
            build_text(result, "executableIdentity") !=
            build_text(evidence, "executableIdentity") {
            raise @config.Invalid("execution.evidence_mismatch")
          }
          let bytes = @platform.read_bytes(output)
          if bytes.length() > 1048576 {
            raise @config.Invalid("execution.output_limit")
          }
          let f = @protocol.fields(@ion_binary.read_binary_value(bytes[:]), [
            "profile", "suite_identity", "calls", "traceparent", "extensions",
          ])
          if @protocol.string(@protocol.required(f, "profile")) !=
            "morphir-outcomes-v1" ||
            @protocol.string(@protocol.required(f, "suite_identity")) !=
            suite_identity ||
            @protocol.string(@protocol.required(f, "traceparent")) !=
            trace.map(t => t.header()).unwrap_or("") {
            raise @config.Invalid("execution.outcome_identity")
          }
          let extensions = f
            .get("extensions")
            .unwrap_or(@ion.IonValue::untyped_null())
          if !extensions.equals(suite.extension_value()) {
            raise @config.Invalid("execution.outcome_extensions")
          }
          guard @protocol.required(f, "calls").kind() is List(calls) else {
            raise @config.Invalid("execution.outcomes_list")
          }
          if calls.length() != suite.calls.length() {
            raise @config.Invalid("execution.result_count")
          }
          let values = []
          for i = 0; i < calls.length(); i = i + 1 {
            let f = @protocol.fields(calls[i], [
              "id", "value", "duration_seconds",
            ])
            if @protocol.string(@protocol.required(f, "id")) !=
              suite.calls[i].id {
              raise @config.Invalid("execution.call_identity")
            }
            let duration = match
              @protocol.required(f, "duration_seconds").kind() {
              Float(n) => n
              _ => raise @config.Invalid("execution.invalid_duration")
            }
            if duration < 0.0 ||
              duration > 600.0 ||
              duration.is_nan() ||
              duration.is_inf() {
              raise @config.Invalid("execution.invalid_duration")
            }
            let value = @protocol.Value::from_ion(
              @protocol.required(f, "value"),
            )
            if trace is Some(parent) && (observer.enabled)() {
              observer.sequence.val += 1
              ignore(
                observer.record({
                  context: {
                    run_id: observer.run_id,
                    trace_id: parent.trace_id,
                    span_id: (observer.next_id)(),
                    parent_id: parent.parent_id,
                  },
                  details: Some({
                    entry: suite.calls[i].entry,
                    code: match value {
                      ModelError(code) => code
                      _ => "execution.ok"
                    },
                  }),
                  correlation: Some({
                    target: build_text(evidence, "target"),
                    lease_id: id,
                    call_id: suite.calls[i].id,
                    attempt_id: attempt.to_string(),
                  }),
                  sequence: observer.sequence.val,
                  stage: @observe.Call,
                  signal: @observe.Succeeded,
                  wall_seconds: (observer.wall)(),
                  duration_seconds: duration,
                }),
              )
            }
            ignore(payload_capture.record(suite.calls[i], value))
            values.push(value)
          }
          // Trace context is validated above, but is outside required receipts.
          guard result is Object(receipt) else {
            raise @config.Invalid("execution.evidence_mismatch")
          }
          ignore(receipt.remove("traceparent"))
          { values, evidence: Json::object(receipt), }
        },
        dispose: fn() raise {
          if !disposed {
            if tree_cleanup_pending {
              raise @config.Invalid(
                "execution.tree_cleanup_pending: " + directory,
              )
            }
            dispose_build_tree(directory)
            disposed = true
          }
        },
      }
    },
  }
}

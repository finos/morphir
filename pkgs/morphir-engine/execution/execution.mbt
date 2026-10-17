///|
pub(all) struct Plan {
  unit : @data.IRUnit
  suite : @protocol.Suite
  library : @moonbit.Output
  driver : Array[@moonbit.Artifact]
  target : String
}

///|
/// Providers own executable storage; the engine never assumes a filesystem.
pub(all) struct InvocationResults {
  values : Array[@protocol.Value]
  evidence : Json
}

///|
pub(all) struct Session {
  id : String
  build : (Plan, @observe.TraceContext?) -> Json raise
  invoke : (@protocol.Suite, @observe.TraceContext?) -> InvocationResults raise
  dispose : () -> Unit raise
}

///|
pub(all) struct Provider {
  targets : Array[String]
  acquire : () -> Session raise
}

///|
pub(all) struct Evaluator {
  profile : String
  evaluate : (
    @data.IRUnit,
    @protocol.Call,
    @protocol.ValueType,
    Array[@protocol.CustomType],
  ) -> @protocol.Value raise
}

///|
pub(all) struct CallResult {
  id : String
  actual : @protocol.Value
  expected : @protocol.Value?
  matches : Bool
  mismatch_path : String?
}

///|
pub(all) struct Report {
  calls : Array[CallResult]
  evidence : Json
  invocation_evidence : Json
  evaluator : String?
  target : String
  comparison : @protocol.ComparisonPolicy
  extensions : Bytes?
  terminals : Array[Terminal]
  failure : Failure?
}

///|
pub fn Report::successful(self : Report) -> Bool {
  self.failure is None &&
  !self.terminals.is_empty() &&
  self.terminals.all(t => t.status == "succeeded") &&
  self.calls.length() == self.terminals.length() &&
  self.calls.all(c => c.matches)
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "profile": "morphir-execution-v1",
    "successful": self.successful(),
    "target": self.target,
    "targetStatus": self.status(),
    "terminals": self.terminals.map(t => {
      ({ "id": t.id, "target": self.target, "status": t.status } : Json)
    }),
    "failure": self.failure.map(f => f.to_json()).unwrap_or(Json::null()),
    "comparison": self.comparison.to_json(),
    "extensions": match self.extensions {
      Some(bytes) =>
        {
          "format": "ion-binary",
          "bytes": bytes.to_array().map(b => b.to_int()),
        }
      None => Json::null()
    },
    "evaluator": match self.evaluator {
      Some(s) => Json::string(s)
      None => Json::null()
    },
    "evidence": self.evidence,
    "invocationEvidence": self.invocation_evidence,
    "calls": self.calls.map(c => {
      (
        {
          "id": c.id,
          "actual": c.actual.to_json(),
          "expected": match c.expected {
            Some(v) => v.to_json()
            None => Json::null()
          },
          "matches": c.matches,
          "mismatchPath": c.mismatch_path
          .map(Json::string)
          .unwrap_or(Json::null()),
        } : Json)
    }),
  }
}

///|
/// Validation and pure generation occur before acquiring a provider session.
pub fn plan(
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  target~ : String = "js",
  available_targets~ : Array[String] = ["js", "wasm-gc", "native"],
) -> Plan raise {
  suite.validate()
  if !["js", "wasm-gc", "native", "llvm"].contains(target) ||
    !available_targets.contains(target) {
    raise @protocol.Invalid("execution.unsupported_target: " + target)
  }
  let library = @moonbit.generate({
    unit_id: unit.id,
    ir: unit.distribution,
    metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: unit.annotations,
    provenance: unit.provenance,
  })
  validate_calls(library, suite)
  {
    unit,
    suite,
    library,
    driver: @moonbit.invocation_driver(library, suite.calls.map(c => c.entry)),
    target,
  }
}

///|
fn validate_calls(
  library : @moonbit.Output,
  suite : @protocol.Suite,
) -> Unit raise {
  @protocol.validate_invocations(
    suite,
    library.invocations.map(e => @protocol.PublicEntry::{
      name: e.fqname,
      inputs: e.inputs,
      output: e.output,
    }),
    library.invocation_types,
    rejections=library.invocation_rejections,
  )
  for call in suite.calls {
    for argument in call.arguments {
      validate_sdk_boundary(argument)
    }
  }
}

///|
pub fn Evaluator::scheme() -> Evaluator {
  {
    profile: "scheme-portable-v1/shared-sdk/bounded",
    evaluate: fn(unit, call, expected, definitions) raise {
      let runtime = @scheme.Runtime::new(limits={
        steps: 1000000,
        depth: 128,
        frames: 100000,
      })
      @backend.install(runtime, accelerators=false, model_errors=true)
      try {
        let result = @backend.run_file_in(
          runtime,
          unit.distribution,
          @ir.FQName::parse(call.entry),
          call.arguments.map(scheme_input),
        )
        let value = scheme_output(result, expected, definitions, 0)
        @protocol.validate_as(value, expected, definitions, output=true)
        value
      } catch {
        @scheme.Domain(code, _) => {
          let value = @protocol.Value::ModelError(code)
          @protocol.validate_as(value, expected, definitions, output=true)
          value
        }
        error => raise error
      }
    },
  }
}

///|
pub fn run_report(
  plan : Plan,
  provider : Provider,
  evaluator~ : Evaluator? = None,
  observer~ : @observe.Observer = @observe.Observer::noop(),
  cancelled~ : () -> Bool = fn() { false },
  comparison~ : @protocol.ComparisonPolicy = @protocol.Exact,
) -> Report raise {
  let observer = observer.isolated(@observe.Health::new())
  comparison.validate()
  if !provider.targets.contains(plan.target) {
    raise @protocol.Invalid("execution.provider_target")
  }
  let frozen = @protocol.Suite::decode(
    plan.suite.encode("ion-binary"),
    "ion-binary",
  )
  validate_calls(plan.library, frozen)
  let source = @data.Registry::new().encode("ion-binary", plan.unit)
  let frozen_unit = @data.Registry::new().decode("ion-binary", {
    unit_id: plan.unit.id,
    content: source,
  })
  let frozen_plan = freeze_plan(
    frozen_unit,
    frozen,
    target=plan.target,
    available_targets=provider.targets,
  )
  if frozen_plan.library.artifacts != plan.library.artifacts ||
    frozen_plan.driver != plan.driver {
    raise @protocol.Invalid("execution.plan_changed")
  }
  let plan = frozen_plan
  let artifacts = plan.library.artifacts.copy()
  let driver = plan.driver.copy()
  let suite_identity = frozen.encode("ion-binary")
  let required_ids = frozen.calls.map(c => c.id)
  let manifest = manifest_snapshot(plan)
  let results : Array[CallResult] = []
  let mut evidence = Json::null()
  let mut invocation_evidence = Json::null()
  let mut failure : Failure? = None
  let mut phase = "acquire"
  fn check() -> Unit raise {
    if cancelled() {
      raise @protocol.Invalid("Cancelled")
    }
    if @data.Registry::new().encode("ion-binary", plan.unit) != source ||
      plan.library.artifacts != artifacts ||
      plan.driver != driver ||
      frozen.encode("ion-binary") != suite_identity ||
      manifest_snapshot(plan) != manifest {
      raise @protocol.Invalid("execution.input_mutation")
    }
  }
  observer
  .scope()
  .observe(@observe.Execute, fn(scope) raise {
    let mut session : Session? = None
    let mut cause : Error? = None
    try {
      check()
      let lease = (provider.acquire)()
      session = Some(lease)
      if lease.id == "" {
        raise @protocol.Invalid("execution.invalid_lease")
      }
      phase = "build"
      evidence = scope.observe(@observe.Build, fn(child) raise {
        check()
        (lease.build)(plan, child.trace_context())
      })
      phase = "invoke"
      let invocation = scope.observe(@observe.Invoke, fn(child) raise {
        check()
        (lease.invoke)(frozen, child.trace_context())
      })
      check()
      invocation_evidence = invocation.evidence
      let actual = invocation.values.copy()
      if actual.length() != frozen.calls.length() {
        raise @protocol.Invalid("execution.result_count")
      }
      for i = 0; i < frozen.calls.length(); i = i + 1 {
        let call = frozen.calls[i]
        let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
        @protocol.validate_as(
          actual[i],
          entry.output,
          plan.library.invocation_types,
          output=true,
        )
        validate_sdk_boundary(actual[i])
        actual[i] = @protocol.Value::from_ion(actual[i].to_ion())
        results.push({
          id: call.id,
          actual: actual[i],
          expected: None,
          matches: false,
          mismatch_path: None,
        })
      }
      for i = 0; i < frozen.calls.length(); i = i + 1 {
        check()
        let call = frozen.calls[i]
        let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
        phase = "evaluate"
        let expected = match evaluator {
          Some(e) =>
            Some(
              scope.observe(
                @observe.Evaluate,
                fn(_) raise {
                  let value = (e.evaluate)(
                    plan.unit,
                    call,
                    entry.output,
                    plan.library.invocation_types,
                  )
                  @protocol.validate_as(
                    value,
                    entry.output,
                    plan.library.invocation_types,
                    output=true,
                  )
                  @protocol.Value::from_ion(value.to_ion())
                },
                details=Some({ entry: call.entry, code: "execution.evaluate", }),
              ),
            )
          None => None
        }
        phase = "compare"
        let mismatch_path = scope.observe(@observe.Compare, fn(_) raise {
          check()
          match expected {
            Some(value) =>
              @protocol.mismatch_path(value, actual[i], policy=comparison)
            None => None
          }
        })
        results[i] = {
          id: call.id,
          actual: actual[i],
          expected,
          matches: mismatch_path is None,
          mismatch_path,
        }
      }
      check()
    } catch {
      error => cause = Some(error)
    }
    let mut cleanup : Error? = None
    if session is Some(lease) {
      scope.observe(@observe.Cleanup, fn(_) raise { (lease.dispose)() }) catch {
        error => cleanup = Some(error)
      }
    }
    if cause is None {
      check() catch {
        error => cause = Some(error)
      }
    }
    if cause is Some(_) || cleanup is Some(_) {
      failure = Some({
        phase: if cause is None {
          "cleanup"
        } else {
          phase
        },
        cause,
        cleanup,
      })
      // The enclosing scope still observes a logical failure/cancellation.
      if cause is Some(error) {
        raise error
      }
      raise CleanupFailed(None, cleanup.unwrap())
    }
  }) catch {
    _ => ()
  }
  let terminals = required_ids.map(id => {
    let status = match results.filter(r => r.id == id).get(0) {
      Some(r) =>
        if r.matches {
          "succeeded"
        } else if r.mismatch_path is Some(_) {
          "mismatch"
        } else if failure is Some(f) && f.cancelled() {
          "cancelled"
        } else {
          "failed"
        }
      None =>
        if failure is Some(f) && f.cancelled() {
          "cancelled"
        } else {
          "failed"
        }
    }
    Terminal::{ id, status, }
  })
  {
    calls: results,
    evidence,
    invocation_evidence,
    evaluator: evaluator.map(e => e.profile),
    target: plan.target,
    comparison,
    extensions: frozen.extensions,
    terminals,
    failure,
  }
}

///|
/// Compatibility API preserves typed causes. Reporting callers use run_report.
pub fn run(
  plan : Plan,
  provider : Provider,
  evaluator~ : Evaluator? = None,
  observer~ : @observe.Observer = @observe.Observer::noop(),
  cancelled~ : () -> Bool = fn() { false },
  comparison~ : @protocol.ComparisonPolicy = @protocol.Exact,
) -> Report raise {
  let report = run_report(
    plan,
    provider,
    evaluator~,
    observer~,
    cancelled~,
    comparison~,
  )
  if report.failure is Some(f) {
    if f.cleanup is Some(error) {
      raise CleanupFailed(f.cause, error)
    }
    raise f.cause.unwrap()
  }
  report
}

///|
fn freeze_plan(
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  target~ : String,
  available_targets~ : Array[String],
) -> Plan raise {
  plan(unit, suite, target~, available_targets~)
}

///|
fn manifest_snapshot(plan : Plan) -> String {
  let entries = plan.library.invocations.map(e => {
    (
      {
        "fqname": e.fqname,
        "generated_name": e.generated_name,
        "inputs": e.inputs.map(t => t.to_json()),
        "output": e.output.to_json(),
        "input_codecs": e.input_codecs,
        "output_codec": e.output_codec,
      } : Json)
  })
  let types = plan.library.invocation_types.map(t => {
    (
      {
        "name": t.name,
        "constructors": t.constructors.map(c => {
          ({ "name": c.name, "inputs": c.inputs.map(t => t.to_json()) } : Json)
        }),
      } : Json)
  })
  ({ "entries": entries, "types": types } : Json).stringify()
}

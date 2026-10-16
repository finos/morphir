///|
/// Hosts supply availability and supported-intersection checks before execution.
pub(all) struct EvaluatorLane {
  name : String
  required : Bool
  evaluator : @execution.Evaluator?
  unsupported : (@execution.Plan, @protocol.Call) -> String? raise
  evidence : Json
}

///|
pub fn EvaluatorLane::scheme() -> EvaluatorLane {
  {
    name: "scheme",
    required: true,
    evaluator: Some(@execution.Evaluator::scheme()),
    unsupported: fn(_, _) { None },
    evidence: { "independence": "shared-sdk", "limits": "bounded" },
  }
}

///|
pub(all) struct Plan {
  execution : @execution.Plan
  expectations : Expectations
  lanes : Array[EvaluatorLane]
}

///|
pub(all) struct Comparison {
  id : String
  status : String
  actual : @protocol.Value?
  expected : @protocol.Value?
  mismatch_path : String?
  reason : String?
}

///|
pub(all) struct Coverage {
  provider : String
  profile : String
  required : Bool
  evidence : Json
  calls : Array[Comparison]
}

///|
pub(all) struct Report {
  execution : @execution.Report
  coverage : Array[Coverage]
}

///|
pub fn Report::cancelled(self : Report) -> Bool {
  (self.execution.failure is Some(f) && f.cancelled()) ||
  self.coverage.any(lane => lane.calls.any(c => c.status == "cancelled"))
}

///|
pub fn Report::successful(self : Report) -> Bool {
  if !self.execution.successful() ||
    self.coverage.is_empty() ||
    self.coverage[0].provider != "independent" ||
    !self.coverage[0].required {
    return false
  }
  let ids = self.execution.terminals.map(t => t.id)
  let names : Map[String, Bool] = Map([])
  self.coverage.all(lane => {
    if names.contains(lane.provider) {
      return false
    }
    names[lane.provider] = true
    lane.calls.map(c => c.id) == ids &&
    lane.calls.all(c => {
      c.status == "matched" ||
      (!lane.required && ["unavailable", "unsupported"].contains(c.status))
    })
  })
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "profile": "morphir-conformance-report-v1",
    "successful": self.successful(),
    "cancelled": self.cancelled(),
    "execution": self.execution.to_json(),
    "coverage": self.coverage.map(lane => {
      (
        {
          "provider": lane.provider,
          "profile": lane.profile,
          "required": lane.required,
          "evidence": lane.evidence,
          "calls": lane.calls.map(c => {
            (
              {
                "id": c.id,
                "status": c.status,
                "matches": if c.status == "matched" {
                  Json::boolean(true)
                } else if c.status == "mismatch" {
                  Json::boolean(false)
                } else {
                  Json::null()
                },
                "actual": c.actual.map(v => v.to_json()).unwrap_or(Json::null()),
                "expected": c.expected
                .map(v => v.to_json())
                .unwrap_or(Json::null()),
                "mismatchPath": c.mismatch_path
                .map(Json::string)
                .unwrap_or(Json::null()),
                "reason": c.reason.map(Json::string).unwrap_or(Json::null()),
              } : Json)
          }),
        } : Json)
    }),
  }
}

///|
pub fn prepare(
  execution : @execution.Plan,
  expectations : Expectations,
  lanes~ : Array[EvaluatorLane] = [EvaluatorLane::scheme()],
) -> Plan raise {
  expectations.validate()
  if execution.suite.encode("ion-binary") !=
    expectations.suite().encode("ion-binary") {
    raise @protocol.Invalid("conformance.suite_identity")
  }
  let names : Map[String, Bool] = Map([])
  for lane in lanes {
    if lane.name == "" ||
      lane.name == "independent" ||
      names.contains(lane.name) {
      raise @protocol.Invalid("conformance.evaluator_identity")
    }
    names[lane.name] = true
    if lane.required {
      if lane.evaluator is None {
        raise @protocol.Invalid(
          "conformance.evaluator_unavailable: " + lane.name,
        )
      }
      for call in execution.suite.calls {
        if (lane.unsupported)(execution, call) is Some(reason) {
          raise @protocol.Invalid(
            "conformance.evaluator_unsupported: " +
            lane.name +
            ": " +
            call.id +
            ": " +
            reason,
          )
        }
      }
    }
  }
  for case in expectations.cases {
    let entry = execution.library.invocations.filter(e => {
        e.fqname == case.call.entry
      })[0]
    @protocol.validate_as(
      case.expected,
      entry.output,
      execution.library.invocation_types,
      output=true,
    )
  }
  { execution, expectations, lanes: lanes.copy(), }
}

///|
fn compared(
  id : String,
  actual : @protocol.Value,
  expected : @protocol.Value,
) -> Comparison raise {
  let path = @protocol.mismatch_path(expected, actual)
  {
    id,
    status: if path is None {
      "matched"
    } else {
      "mismatch"
    },
    actual: Some(actual),
    expected: Some(expected),
    mismatch_path: path,
    reason: None,
  }
}

///|
fn diagnostic(error : Error) -> String {
  let failure : @execution.Failure = match error {
    @execution.CleanupFailed(primary, cleanup) =>
      { phase: "evaluate", cause: primary, cleanup: Some(cleanup), }
    _ => { phase: "evaluate", cause: Some(error), cleanup: None, }
  }
  let text = failure.to_json().stringify()
  if text.length() > 1024 {
    text[:1024].to_owned()
  } else {
    text
  }
}

///|
pub fn run(
  plan : Plan,
  provider : @execution.Provider,
  observer~ : @observe.Observer = @observe.Observer::noop(),
  cancelled~ : () -> Bool = fn() { false },
) -> Report raise {
  let expectations = Expectations::from_ion(plan.expectations.to_ion())
  let source = @data.Registry::new().encode("ion-binary", plan.execution.unit)
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: plan.execution.unit.id,
    content: source,
  })
  let frozen = @execution.plan(
    unit,
    expectations.suite(),
    target=plan.execution.target,
    available_targets=provider.targets,
  )
  if frozen.library.artifacts != plan.execution.library.artifacts ||
    frozen.driver != plan.execution.driver {
    raise @protocol.Invalid("conformance.plan_changed")
  }
  let artifacts = frozen.library.artifacts.copy()
  let driver = frozen.driver.copy()
  let suite = frozen.suite.encode("ion-binary")
  fn check() -> Unit raise {
    if @data.Registry::new().encode("ion-binary", frozen.unit) != source ||
      frozen.library.artifacts != artifacts ||
      frozen.driver != driver ||
      frozen.suite.encode("ion-binary") != suite {
      raise @protocol.Invalid("conformance.input_mutation")
    }
  }
  let plan = prepare(frozen, expectations, lanes=plan.lanes)
  check()
  let execution = @execution.run_report(
    plan.execution,
    provider,
    observer~,
    cancelled~,
  )
  check()
  let rows = expectations.cases.map(c => {
    match execution.calls.filter(r => r.id == c.call.id).get(0) {
      Some(result) => compared(c.call.id, result.actual, c.expected)
      None =>
        Comparison::{
          id: c.call.id,
          status: if execution.failure is Some(f) && f.cancelled() {
            "cancelled"
          } else {
            "error"
          },
          actual: None,
          expected: Some(c.expected),
          mismatch_path: None,
          reason: Some("execution.no_result"),
        }
    }
  })
  let coverage = [
    Coverage::{
      provider: "independent",
      profile: "morphir-conformance-v1",
      required: true,
      evidence: {
        "version": expectations.version,
        "provenance": expectations.provenance,
      },
      calls: rows,
    },
  ]
  for lane in plan.lanes {
    let calls = expectations.cases.map(case => {
      let actual = execution.calls
        .filter(r => r.id == case.call.id)
        .get(0)
        .map(r => r.actual)
      let empty = Comparison::{
        id: case.call.id,
        status: "error",
        actual,
        expected: None,
        mismatch_path: None,
        reason: None,
      }
      if actual is None {
        return {
          ..empty,
          status: if execution.failure is Some(f) && f.cancelled() {
            "cancelled"
          } else {
            "error"
          },
          reason: Some("execution.no_result"),
        }
      }
      if cancelled() {
        return { ..empty, status: "cancelled", reason: Some("Cancelled"), }
      }
      guard lane.evaluator is Some(evaluator) else {
        return {
          ..empty,
          status: "unavailable",
          reason: Some("conformance.evaluator_unavailable"),
        }
      }
      try {
        check()
        let unsupported = (lane.unsupported)(plan.execution, case.call)
        check()
        if cancelled() {
          return { ..empty, status: "cancelled", reason: Some("Cancelled"), }
        }
        if unsupported is Some(reason) {
          return { ..empty, status: "unsupported", reason: Some(reason), }
        }
        let entry = plan.execution.library.invocations.filter(e => {
            e.fqname == case.call.entry
          })[0]
        let expected = observer
          .scope()
          .observe(@observe.Evaluate, fn(_) raise {
            let value = (evaluator.evaluate)(
              plan.execution.unit,
              case.call,
              entry.output,
              plan.execution.library.invocation_types,
            )
            if cancelled() {
              raise @protocol.Invalid("Cancelled")
            }
            value
          })
        check()
        @protocol.validate_as(
          expected,
          entry.output,
          plan.execution.library.invocation_types,
          output=true,
        )
        compared(
          case.call.id,
          actual.unwrap(),
          @protocol.Value::from_ion(expected.to_ion()),
        )
      } catch {
        error =>
          {
            ..empty,
            status: if cancelled() || evaluator_cancelled(error) {
              "cancelled"
            } else {
              "error"
            },
            reason: Some(diagnostic(error)),
          }
      }
    })
    coverage.push({
      provider: lane.name,
      profile: lane.evaluator.map(e => e.profile).unwrap_or("unavailable"),
      required: lane.required,
      evidence: lane.evidence,
      calls,
    })
  }
  check()
  { execution, coverage, }
}

///|
/// Rich semantic values stay native Ion. Provider identity fields use their
/// explicitly selected JSON profile, converted without numeric coercion.
pub fn Report::to_ion(self : Report) -> @ion.IonValue raise {
  @protocol.record([
    ("profile", @ion.IonValue::string("morphir-conformance-report-v1")),
    ("successful", @ion.IonValue::bool(self.successful())),
    ("cancelled", @ion.IonValue::bool(self.cancelled())),
    ("execution", self.execution.to_ion()),
    (
      "coverage",
      @ion.IonValue::list(
        self.coverage.map(lane => {
          @protocol.record([
            ("provider", @ion.IonValue::string(lane.provider)),
            ("profile", @ion.IonValue::string(lane.profile)),
            ("required", @ion.IonValue::bool(lane.required)),
            ("evidence", @text.read_ion(lane.evidence.stringify()[:])),
            (
              "calls",
              @ion.IonValue::list(
                lane.calls.map(c => {
                  @protocol.record([
                    ("id", @ion.IonValue::string(c.id)),
                    ("status", @ion.IonValue::string(c.status)),
                    (
                      "matches",
                      if c.status == "matched" {
                        @ion.IonValue::bool(true)
                      } else if c.status == "mismatch" {
                        @ion.IonValue::bool(false)
                      } else {
                        @ion.IonValue::untyped_null()
                      },
                    ),
                    (
                      "actual",
                      c.actual
                      .map(v => v.to_ion())
                      .unwrap_or(@ion.IonValue::untyped_null()),
                    ),
                    (
                      "expected",
                      c.expected
                      .map(v => v.to_ion())
                      .unwrap_or(@ion.IonValue::untyped_null()),
                    ),
                    (
                      "mismatch_path",
                      c.mismatch_path
                      .map(@ion.IonValue::string)
                      .unwrap_or(@ion.IonValue::untyped_null()),
                    ),
                    (
                      "reason",
                      c.reason
                      .map(@ion.IonValue::string)
                      .unwrap_or(@ion.IonValue::untyped_null()),
                    ),
                  ])
                }),
              ),
            ),
          ])
        }),
      ),
    ),
  ])
}

///|
pub fn Report::encode(
  self : Report,
  format~ : String = "ion-binary",
) -> Bytes raise {
  match format {
    "ion-binary" => @binary.write_binary([self.to_ion()])
    "ion-text" => @utf8.encode(@text.write_ion(self.to_ion()))
    "json" => @utf8.encode(self.to_json().stringify())
    _ => raise @protocol.Invalid("conformance.receipt_format")
  }
}

///|
fn evaluator_cancelled(error : Error) -> Bool {
  match error {
    @protocol.Invalid("Cancelled") => true
    @execution.CleanupFailed(Some(primary), _) => evaluator_cancelled(primary)
    _ => false
  }
}

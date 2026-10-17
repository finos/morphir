///|
/// The policy-aware interpreter boundary. The narrow selected-plan API remains
/// separate so its historical exact contract keeps its original behavior.
pub fn plan_scheme_capabilities(
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  policy~ : AdmissionPolicy = Strict,
  limits~ : @data.Limits = @data.Limits::default(),
) -> SchemePlan raise {
  let selected = plan_scheme(unit, suite, policy~, limits~)
  if policy is Permissive {
    let captured = @data.Registry::new(limits=selected.limits).decode(
      "ion-binary",
      { unit_id: selected.unit_id, content: Binary(selected.source), },
    )
    for entry in selected.entries {
      ignore(
        @backend.emit_selected(
          captured.distribution,
          @ir.FQName::parse(entry.name),
        ),
      )
    }
  }
  selected
}

///|
/// Check complete terminal evidence against the plan's captured public context.
/// This validates evidence; it neither executes nor authenticates a job.
pub fn SchemePlan::validate_outcomes(
  self : SchemePlan,
  outcomes : @protocol.Outcomes,
) -> Unit raise {
  let suite = @protocol.Suite::decode(self.suite, "json")
  @protocol.validate_outcomes(outcomes, suite, self.entries, self.definitions)
  if @utf8.encode(outcomes.to_json().stringify()).length() > 1048576 {
    raise AdmissionInvalid("execution.output_limit")
  }
}

///|
fn scheme_capability_failure(error : Error) -> @protocol.TerminalOutcome {
  let (code, message) = match error {
    @scheme.Limit("cancelled") => return @protocol.Cancelled
    @scheme.Stage("evaluate", "execution.unsupported_reached") =>
      ("execution.unsupported_reached", "Unsupported operation reached")
    @scheme.Unbound(_) => ("scheme.unbound", "Unbound runtime reference")
    @scheme.Limit(_) => ("scheme.limit", "Runtime resource limit exceeded")
    @scheme.Invalid(_) => ("scheme.invalid", "Invalid runtime operation")
    @scheme.Unsupported(_) =>
      ("scheme.unsupported", "Unsupported Scheme operation")
    @scheme.Syntax(_, _) => ("scheme.syntax", "Invalid Scheme syntax")
    @scheme.Stage(_, _) => ("scheme.stage", "Runtime stage failed")
    @protocol.Invalid(detail) | AdmissionInvalid(detail) => {
      let code = detail.split(":").next().unwrap_or("").to_owned()
      if code.length() > 0 && code.length() <= 128 {
        (code, "Invalid typed evaluation result")
      } else {
        ("execution.evaluate", "Scheme evaluation failed")
      }
    }
    _ => ("execution.evaluate", "Scheme evaluation failed")
  }
  @protocol.Failed({ stage: Evaluate, code, message, })
}

///|
fn scheme_call_bytes(call : @protocol.CallOutcome) -> Int32 {
  let one : @protocol.Outcomes = {
    calls: [call],
    cleanup: None,
    extensions: None,
  }
  guard one.to_json() is Object(fields) && fields["calls"] is Array([value]) else {
    abort("canonical outcome projection")
  }
  @utf8.encode(value.stringify()).length()
}

///|
/// Execute each captured call and publish only fully validated typed terminals.
/// Cancellation and runtime limits share the file-load and invocation budget.
pub fn SchemePlan::evaluate_outcomes(
  self : SchemePlan,
  cancelled~ : () -> Bool = fn() { false },
) -> @protocol.Outcomes raise {
  let unit = @data.Registry::new(limits=self.limits).decode("ion-binary", {
    unit_id: self.unit_id,
    content: Binary(self.source),
  })
  let suite = @protocol.Suite::decode(self.suite, "json")
  let calls = []
  let mut retained_bytes = 0
  for call in suite.calls {
    let entry = self.entries.filter(e => e.name == call.entry)[0]
    let terminal : @protocol.TerminalOutcome = try {
      let runtime = @scheme.Runtime::new(limits={
        steps: 1000000,
        depth: 128,
        frames: 100000,
      })
      runtime.set_cancelled(cancelled)
      @backend.install(runtime, accelerators=false, model_errors=true)
      let value = try {
        let actual = if self.admission is Permissive {
          @backend.run_selected_in(
            runtime,
            unit.distribution,
            @ir.FQName::parse(call.entry),
            call.arguments.map(scheme_input),
          )
        } else {
          @backend.run_file_in(
            runtime,
            unit.distribution,
            @ir.FQName::parse(call.entry),
            call.arguments.map(scheme_input),
          )
        }
        scheme_output(actual, entry.output, self.definitions, 0)
      } catch {
        @scheme.Domain(code, _) => @protocol.ModelError(code)
        error => raise error
      }
      @protocol.validate_as(value, entry.output, self.definitions, output=true)
      match value {
        ModelError(code) => @protocol.ModelError(code)
        _ => @protocol.Returned(value)
      }
    } catch {
      error => scheme_capability_failure(error)
    }
    let observed : @protocol.CallOutcome = { id: call.id, outcome: terminal, }
    retained_bytes += scheme_call_bytes(observed) + 1
    if retained_bytes > 1048576 {
      raise AdmissionInvalid("execution.output_limit")
    }
    calls.push(observed)
  }
  let outcomes : @protocol.Outcomes = {
    calls,
    cleanup: None,
    extensions: suite.extensions,
  }
  self.validate_outcomes(outcomes)
  outcomes
}

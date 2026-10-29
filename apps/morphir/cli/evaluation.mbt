///|
/// This command interprets a captured model. Generated-library execution keeps
/// its existing execute/verify/conform commands and provider contract.
fn evaluation_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let path = value(cli, "path")
  let suite_path = value(cli, "suite")
  if path == "" || suite_path == "" {
    raise @config.Invalid("eval requires a model and --suite")
  }
  if path == "-" && suite_path == "-" {
    raise @config.Invalid("Only one input may read stdin")
  }
  let provider = value(cli, "provider", fallback="scheme")
  if provider != "scheme" {
    raise @config.Invalid("eval.unsupported_provider: " + provider)
  }
  let policy = evaluation_policy(
    value(cli, "checking-policy", fallback="strict"),
  )
  let timeout = build_timeout(value(cli, "timeout", fallback="120000"))
  let limits = @data.Limits::default()
  let suite_format = value(cli, "suite-format", fallback="json")
  if !["json", "ion-text", "ion-binary"].contains(suite_format) {
    raise @config.Invalid("eval.unsupported_suite_format")
  }
  if !@platform.interruption_supported() {
    raise @config.Invalid("eval.interruption_unavailable")
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  // All input boundaries are checked before entering the interpreter. A model
  // codec does not change the invocation suite's independently versioned codec.
  let unit = load_local_model(cli, limits)
  let suite = @protocol.Suite::decode(
    @platform.read_input(suite_path, 1048576),
    suite_format,
  )
  let started = @platform.monotonic_seconds()
  let cancel_file = value(cli, "cancel-file")
  let cancelled = fn() {
    @platform.interruption_requested() ||
    (cancel_file != "" && (@platform.kind(cancel_file) catch { _ => 1 }) != 0)
  }
  let expired = fn() {
    (@platform.monotonic_seconds() - started) * 1000.0 >= timeout.to_double()
  }
  let plan = @execution.plan_scheme_capabilities(unit, suite, policy~, limits~) catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      let report : Json = {
        "operation": "evaluate",
        "provider": "scheme-portable-v1/shared-sdk/bounded",
        "checkingPolicy": value(cli, "checking-policy", fallback="strict"),
        "successful": false,
        "error": message,
        "boundary": Json::null(),
        "terminalOutcomes": Json::null(),
        "failure": { "stage": "plan", "code": @host.error_code(error) },
      }
      match mode {
        JSON => println(report.stringify())
        JSONLines => emit_record("error", report)
        Human => ()
      }
      return 1
    }
  }
  let outcomes = plan.evaluate_outcomes(cancelled=fn() {
    cancelled() || expired()
  })
  let status = evaluation_status(outcomes, timed_out=expired())
  let report : Json = {
    "operation": "evaluate",
    "provider": "scheme-portable-v1/shared-sdk/bounded",
    "checkingPolicy": match policy {
      Strict => "strict"
      Permissive => "permissive"
    },
    "unitId": unit.id,
    "boundary": plan.boundary_json().stringify(),
    "successful": status == 0,
    "timedOut": status == 1 && expired(),
    "terminalOutcomes": outcomes.to_json(),
    "failure": Json::null(),
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => {
      // Preserve complete typed values in each record. The final record also
      // retains the canonical evidence for consumers of the ordinary envelope.
      guard outcomes.to_json() is Object(fields) &&
        fields.get("calls") is Some(Array(calls)) else {
        abort("canonical outcome inventory")
      }
      for call in calls {
        emit_record("call", call)
      }
      emit_record("result", report)
    }
    Human =>
      for call in outcomes.calls {
        println(call.id + "\t" + call.outcome.to_json().stringify())
      }
  }
  status
}

///|
fn evaluation_policy(text : String) -> @execution.CapabilityPolicy raise {
  match text {
    "strict" => @execution.Strict
    "permissive" => @execution.Permissive
    _ => raise @config.Invalid("eval.unsupported_checking_policy")
  }
}

///|
/// A timeout is a failed evaluation; an acknowledged user cancellation is 130.
/// Domain errors remain typed model outcomes and make this command fail.
fn evaluation_status(
  outcomes : @protocol.Outcomes,
  timed_out~ : Bool = false,
) -> Int32 {
  if outcomes.calls.any(call => call.outcome is Cancelled) {
    if timed_out {
      1
    } else {
      130
    }
  } else if outcomes.cleanup is Some(_) ||
    outcomes.calls.any(call => !(call.outcome is Returned(_))) {
    1
  } else {
    0
  }
}

///|
fn model_input_format(
  path : String,
  explicit : String,
) -> @data.ModelFormat raise {
  if explicit != "" {
    @data.ModelFormat::from_control(explicit)
  } else {
    match @data.ModelFormat::infer_path(path) {
      Some(format) => format
      None => raise @config.Invalid("Model input requires --model-format")
    }
  }
}

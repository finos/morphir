///|
#cfg(target="native")
async fn extension_generate_tree(
  host : @worker.Host,
  pin : ExtensionPin,
  claims : @worker.Claims?,
  inputs : ExtensionInputs,
  deadline~ : () -> @worker.Deadline raise ExtensionError,
  stop~ : @worker.StopSignal,
  diagnostics~ : Array[@worker.Diagnostic],
) -> (Json, String)? {
  let input : @worker.TreeGenerationInput = match inputs.task_result {
    Some(record) => CompileResult(record)
    None => {
      // The original single-file handoff still owns inline model input.
      guard (@platform.kind(inputs.path) catch { _ => 0 }) == 2 else {
        return None
      }
      ExplicitDirectory(inputs.path)
    }
  }
  let target = match claims {
    Some(claims) => extension_target(claims, inputs.target)
    None => {
      guard inputs.target != "" else {
        raise input_invalid(
          "recorded bounded WASM generation requires --target",
        )
      }
      inputs.target
    }
  }
  let generated = host.generate_tree(
    pin.spec,
    expected?=claims,
    input~,
    output=inputs.output,
    target~,
    requested_ir=inputs.ir_version,
    deadline=deadline(),
    stop~,
    diagnostics~,
    profile=inputs.qualification,
  ) catch {
    @worker.Refusal(..) as refusal => raise refusal_error(refusal)
    @worker.Ended(ending, report~) => {
      if report.stop is Some(stopped) {
        @platform.stderr(extension_stderr_text(stopped.stderr))
      }
      raise ending_error(ending)
    }
    @worker.TreeSource(message) => raise input_invalid(message)
    @worker.TreeOutput(message) => raise failed(OutputFailed, message)
    @worker.TreeGuest(message) => raise failed(ResultInvalid, message)
    @worker.TreeUnsuccessful =>
      raise failed(
        OperationUnsuccessful,
        "the worker reported failed bounded generation",
      )
    @worker.TreeExpired => raise ending_error(Deadline)
    @worker.TreeInterrupted => raise ending_error(Cancelled)
    error => raise error
  }
  guard generated.session.stop is Some(stopped) else {
    abort("published bounded generation requires a stopped worker")
  }
  @platform.stderr(extension_stderr_text(stopped.stderr))
  let (result, summary) = extension_session_result(
    Generate,
    inputs,
    generated.claims,
    extension_worker_json(pin),
    generated.session,
    generated.files,
    stopped.stderr,
    protocol=Mep0_2Draft2,
    probe=if claims is None || inputs.qualification != Standard {
      "initialized"
    } else {
      "described"
    },
  )
  if inputs.qualification != Standard && result is Object(fields) {
    fields["treeAccounting"] = generated.accounting.to_json()
  }
  Some((result, summary))
}

///|
#cfg(target="js")
fn extension_generate_tree(
  _host : @worker.Host,
  _pin : ExtensionPin,
  _claims : @worker.Claims?,
  inputs : ExtensionInputs,
  deadline~ : () -> @worker.Deadline raise ExtensionError,
  stop~ : @worker.StopSignal,
  diagnostics~ : Array[@worker.Diagnostic],
) -> (Json, String)? raise ExtensionError {
  ignore((deadline, stop, diagnostics))
  if inputs.task_result is Some(_) {
    raise refused(
      Worker(RuntimeUnavailable),
      "--task-result needs the native macOS or Linux CLI",
    )
  }
  None
}

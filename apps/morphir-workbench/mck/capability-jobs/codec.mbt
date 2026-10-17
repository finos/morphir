///|
fn selected_policy(input : Json) -> @engine.AdmissionPolicy {
  if field_value(field_value(input, "admission"), "policy") ==
    Json::string("permissive") {
    @engine.Permissive
  } else {
    @engine.Strict
  }
}

///|
fn policy_name(policy : @engine.AdmissionPolicy) -> String {
  match policy {
    Strict => "strict"
    Permissive => "permissive"
  }
}

///|
fn error_code(error : Error) -> String {
  let code = match error {
    @host.Invalid(code) => code
    @receipts.Invalid(code) => code
    @engine.AdmissionInvalid(code) => code
    @data.Invalid(code, _) => code
    @wire.Invalid(code, _) => code
    @protocol.Invalid(code) => code
    @generator.Invalid(code, _, _) => code
    @ion.LimitExceeded(_) => "execution.value_limit"
    @ion.Syntax(_) => "workbench.invalid_ion"
    @scheme.Unsupported(_) => "scheme.unsupported"
    @scheme.Unbound(_) => "scheme.unbound"
    @scheme.Limit(_) => "scheme.limit"
    @scheme.Syntax(_, _) => "scheme.syntax"
    @scheme.Invalid(_) => "scheme.invalid"
    @scheme.Domain(code, _) => code
    @scheme.Stage(code, _) => code
    _ => "workbench.capability_failure"
  }
  let stable = code
    .split(":")
    .next()
    .unwrap_or("workbench.capability_failure")
    .to_owned()
  if stable.length() == 0 || stable.length() > 128 {
    "workbench.capability_failure"
  } else {
    stable
  }
}

///|
fn invocation_arguments(input : Json) -> Json raise {
  let arguments = field_value(input, "inputs")
  let source = @wire.string(field_value(arguments, "source"))
  if field_value(arguments, "format") == Json::string("ion-text") {
    return @arguments.ion_arguments(Json::null(), source, true) catch {
      @protocol.Invalid(_) as error => raise error
      @ion.LimitExceeded(_) as error => raise error
      _ => raise @protocol.Invalid("execution.invalid_arguments")
    }
  }
  // Tagged values use several JSON levels per value level. Preserve bounded
  // parser and production codec limits as resource failures, not grammar errors.
  let value = @wire.parse_bounded(source, max_depth=512) catch {
    @wire.Invalid("json_limit", _) =>
      raise @protocol.Invalid("execution.value_limit")
    _ => raise @protocol.Invalid("execution.invalid_arguments")
  }
  guard value is Array(_) else {
    raise @protocol.Invalid("execution.invalid_arguments")
  }
  value
}

///|
fn text_limit(value : Json, limit : Int32, nonempty~ : Bool = false) -> Bool {
  guard value is String(source) else { return false }
  let length = source.iter().count()
  (!nonempty || length > 0) && length <= limit
}

///|
fn text_payload(value : Json) -> Bool {
  closed(value, ["format", "source"]) &&
  text_limit(field_value(value, "source"), 262144) &&
  [Json::string("json"), Json::string("ion-text")].contains(
    field_value(value, "format"),
  )
}

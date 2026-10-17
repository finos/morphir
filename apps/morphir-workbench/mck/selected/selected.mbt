///|
fn text_limit(value : Json, limit : Int32, nonempty~ : Bool = false) -> Bool {
  guard value is String(source) else { return false }
  let length = source.iter().count()
  (!nonempty || length > 0) && length <= limit
}

///|
fn valid_input(input : Json) -> Bool {
  guard input is Object(fields) &&
    (fields.length() == 4 || fields.length() == 5) &&
    fields
    .keys()
    .all(name => {
      ["model", "entry", "inputs", "runtime", "admission"].contains(name)
    }) &&
    text_limit(field_value(input, "model"), 262144) &&
    text_limit(field_value(input, "entry"), 512, nonempty=true) &&
    field_value(input, "runtime") == Json::string("scheme") &&
    @utf8.encode(input.stringify()).length() <= 491520 else {
    return false
  }
  let arguments = field_value(input, "inputs")
  guard closed(arguments, ["format", "source"]) &&
    text_limit(field_value(arguments, "source"), 16384) &&
    [Json::string("json"), Json::string("ion-text")].contains(
      field_value(arguments, "format"),
    ) else {
    return false
  }
  match fields.get("admission") {
    None => true
    Some(selection) =>
      closed(selection, ["profile", "contractVersion", "policy"]) &&
      field_value(selection, "profile") ==
      Json::string("morphir/workbench/admission") &&
      field_value(selection, "contractVersion") == Json::string("0.1.0-draft.1") &&
      [Json::string("strict"), Json::string("permissive")].contains(
        field_value(selection, "policy"),
      )
  }
}

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
/// Canonical projection only. The shared Rust MCK owns the independent verdict.
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let names = fields.keys().collect()
      names.sort_by(fn(a, b) { a.lexical_compare(b) })
      "{" +
      names
      .map(name => {
        Json::string(name).stringify() + ":" + canonical_json(fields[name])
      })
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.map(canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn error_code(error : Error) -> String {
  let code = match error {
    @engine.AdmissionInvalid(code) => code
    @data.Invalid(code, _) => code
    @wire.Invalid(code, _) => code
    @protocol.Invalid(code) => code
    @generator.Invalid(code, _, _) => code
    @ion.LimitExceeded(_) => "execution.value_limit"
    @scheme.Unsupported(_) => "scheme.unsupported"
    @scheme.Unbound(_) => "scheme.unbound"
    @scheme.Limit(_) => "scheme.limit"
    @scheme.Syntax(_, _) => "scheme.syntax"
    @scheme.Invalid(_) => "scheme.invalid"
    @scheme.Domain(code, _) => code
    @scheme.Stage(code, _) => code
    _ => "workbench.admission_failure"
  }
  let stable = code
    .split(":")
    .next()
    .unwrap_or("workbench.admission_failure")
    .to_owned()
  if stable.length() == 0 || stable.length() > 128 {
    "workbench.admission_failure"
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
fn observe(input : Json) -> Json {
  let requested = selected_policy(input)
  let mut effective = requested
  let mut stage = "decode"
  let mut boundary = Json::null()
  try {
    let unit = @data.Registry::new().open_checkpoint(
      "morphir-json",
      @data.Text(@wire.string(field_value(input, "model"))),
    )
    let suite = @protocol.Suite::from_json({
      "profile": "morphir-invocations-v1",
      "calls": [
        {
          "id": "selected",
          "entry": field_value(input, "entry"),
          "arguments": invocation_arguments(input),
        },
      ],
    })
    stage = "plan"
    let plan = @engine.plan_scheme(unit, suite, policy=requested)
    effective = plan.policy()
    let declaration = canonical_json(plan.boundary_json())
    // Reserve framing and failure space before retaining an escaped projection.
    if @utf8.encode(Json::string(declaration).stringify()).length() > 1047552 {
      raise @protocol.Invalid("workbench.projection_limit")
    }
    boundary = Json::string(declaration)
    stage = "evaluate"
    let values = plan.evaluate().map(value => value.to_json())
    let projection : Json = {
      "policy": policy_name(effective),
      "runtime": "scheme",
      "boundary": boundary,
      "values": values,
      "failure": null,
    }
    if @utf8.encode(projection.stringify()).length() > 1048576 {
      raise @protocol.Invalid("workbench.projection_limit")
    }
    projection
  } catch {
    error =>
      {
        "policy": policy_name(effective),
        "runtime": "scheme",
        "boundary": boundary,
        "values": null,
        "failure": { "stage": stage, "code": error_code(error) },
      }
  }
}

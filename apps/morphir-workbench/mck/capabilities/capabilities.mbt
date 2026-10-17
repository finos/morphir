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

///|
fn valid_input(input : Json) -> Bool {
  guard input is Object(fields) &&
    fields
    .keys()
    .all(name => {
      ["model", "calls", "runtime", "admission", "extensions", "completion"].contains(
        name,
      )
    }) &&
    fields.contains("extensions") &&
    text_limit(field_value(input, "model"), 262144) &&
    field_value(input, "runtime") == Json::string("scheme") &&
    @utf8.encode(input.stringify()).length() <= 1048576 &&
    field_value(input, "calls") is Array(calls) &&
    calls.length() > 0 &&
    calls.length() <= 1000 else {
    return false
  }
  for call in calls {
    if !closed(call, ["id", "entry", "inputs"]) ||
      !text_limit(field_value(call, "id"), 128, nonempty=true) ||
      !text_limit(field_value(call, "entry"), 512, nonempty=true) ||
      !text_payload(field_value(call, "inputs")) {
      return false
    }
  }
  match fields.get("admission") {
    None => ()
    Some(selection) =>
      if !closed(selection, ["profile", "contractVersion", "policy"]) ||
        field_value(selection, "profile") !=
        Json::string("morphir/workbench/admission") ||
        field_value(selection, "contractVersion") !=
        Json::string("0.1.0-draft.1") ||
        ![Json::string("strict"), Json::string("permissive")].contains(
          field_value(selection, "policy"),
        ) {
        return false
      }
  }
  match fields.get("completion") {
    None => ()
    Some(completion) => if !text_payload(completion) { return false }
  }
  match field_value(input, "extensions") {
    Null => true
    extension => {
      guard closed(extension, ["format", "bytes"]) &&
        field_value(extension, "format") == Json::string("ion-binary") &&
        field_value(extension, "bytes") is Array(bytes) &&
        bytes.length() > 0 &&
        bytes.length() <= 65536 else {
        return false
      }
      bytes.all(byte => {
        byte is Number(n, ..) && n >= 0 && n <= 255 && n.floor() == n
      })
    }
  }
}

///|
fn observe(input : Json) -> Json {
  let policy = selected_policy(input)
  let mode = if input is Object(fields) && fields.contains("completion") {
    "validate-completion"
  } else {
    "execute"
  }
  let mut stage = "decode"
  let mut boundary = Json::null()
  try {
    let unit = @data.Registry::new().open_checkpoint(
      "morphir-json",
      @data.Text(@wire.string(field_value(input, "model"))),
    )
    let calls = @wire.array(field_value(input, "calls"))
    let invocation : Json = {
      "profile": "morphir-invocations-v1",
      "calls": calls.map(call => {
        (
          {
            "id": field_value(call, "id"),
            "entry": field_value(call, "entry"),
            "arguments": invocation_arguments(call),
          } : Json)
      }),
    }
    let extension = field_value(input, "extensions")
    if extension != Json::null() && invocation is Object(fields) {
      fields["extensions"] = extension
    }
    let suite = @protocol.Suite::from_json(invocation)
    stage = "plan"
    let plan = @engine.plan_scheme_capabilities(unit, suite, policy~)
    let declaration = canonical_json(plan.boundary_json())
    if @utf8.encode(Json::string(declaration).stringify()).length() > 1047552 {
      raise @protocol.Invalid("workbench.projection_limit")
    }
    boundary = Json::string(declaration)
    stage = "complete"
    let outcomes = if mode == "validate-completion" {
      let supplied = field_value(input, "completion")
      let source = @wire.string(field_value(supplied, "source"))
      let format = @wire.string(field_value(supplied, "format"))
      if format == "json" {
        ignore(@wire.parse_bounded(source, max_depth=512)) catch {
          @wire.Invalid("json_limit", _) =>
            raise @protocol.Invalid("execution.value_limit")
          error => raise error
        }
      }
      let evidence = @protocol.Outcomes::decode(@utf8.encode(source), format)
      plan.validate_outcomes(evidence)
      evidence
    } else {
      plan.evaluate_outcomes()
    }
    let projection : Json = {
      "mode": mode,
      "policy": policy_name(plan.policy()),
      "runtime": "scheme",
      "boundary": boundary,
      "outcomes": outcomes.to_json(),
      "failure": null,
    }
    if @utf8.encode(projection.stringify()).length() > 1048576 {
      raise @protocol.Invalid("workbench.projection_limit")
    }
    projection
  } catch {
    error =>
      {
        "mode": mode,
        "policy": policy_name(policy),
        "runtime": "scheme",
        "boundary": boundary,
        "outcomes": null,
        "failure": { "stage": stage, "code": error_code(error) },
      }
  }
}

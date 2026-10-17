///|
/// Keep the historical complete-manifest description for strict host mappings.
fn typed_profiles(file : @ir.IRFile) -> Json {
  try {
    let library = @moonbit.generate(@moonbit.Input::new("workbench", file))
    let values = evaluation_definitions(file)
    @wire.obj([
      (
        "entries",
        @wire.obj(
          library.invocations.map(entry => {
            (
              entry.fqname,
              typed_profile(
                {
                  name: entry.fqname,
                  inputs: entry.inputs,
                  output: entry.output,
                },
                library.invocation_types,
                values,
              ),
            )
          }),
        ),
      ),
    ])
  } catch {
    @moonbit.Invalid(code, _, detail) =>
      @wire.obj([("reason", @wire.text(code + ": " + detail))])
  }
}

///|
fn typed_profile(
  entry : @protocol.PublicEntry,
  definitions : Array[@protocol.CustomType],
  values : Map[String, @ir.ValueDefinition],
) -> Json {
  let registry = definitions.map(d => {
    (
      {
        "name": d.name,
        "constructors": d.constructors.map(c => {
          (
            {
              "name": c.name,
              "inputs": c.inputs.map(@protocol.ValueType::to_json),
            } : Json)
        }),
      } : Json)
  })
  let (defaults, default_reason) = (
    Json::array(
      entry.inputs.map(t => @arguments.typed_default(t.to_json(), registry)),
    ),
    "",
  ) catch {
    _ =>
      (
        Json::array([]),
        "No finite default was found. Enter tagged values in parameter order.",
      )
  }
  let names = match values.get(entry.name) {
    Some(ExpressionBody(inputs, _, _)) => inputs.map(p => display_name(p.0))
    _ => []
  }
  {
    "supported": true,
    "default": defaults,
    "defaultReason": default_reason,
    "inputs": entry.inputs.mapi((i, t) => {
      (
        {
          "label": names.get(i).unwrap_or("Argument " + (i + 1).to_string()),
          "type": t.to_json(),
        } : Json)
    }),
    "output": entry.output.to_json(),
    "definitions": registry,
  }
}

///|
/// Local worker descriptions only. Each selected type closure is discovered
/// independently; neither this description nor generated-code success admits a run.
fn capability_profiles(file : @ir.IRFile) -> Json {
  let values = evaluation_definitions(file)
  let names = values.keys().collect()
  names.sort()
  let profiles : Array[(String, Json)] = []
  let mut bytes = 0
  for name in names {
    // This eagerly describes inputs for the inspector. Bound both the number of
    // independent closures and their combined editor/default expansion.
    if profiles.length() >= 128 || bytes >= 1048576 {
      break
    }
    let profile = try {
      let (entry, definitions) = @typed_engine.scheme_entry_boundary(file, name)
      typed_profile(entry, definitions, values)
    } catch {
      error =>
        (
          {
            "supported": false,
            "reason": "Unsupported input/output boundary: " +
            capability_problem(error).0,
          } : Json)
    }
    bytes += @utf8.encode(profile.stringify()).length()
    if bytes > 1048576 {
      break
    }
    profiles.push((name, profile))
  }
  {
    "evaluator": "scheme-portable-v1/shared-sdk/bounded",
    "admission": {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policies": ["strict", "permissive"],
    },
    "entries": @wire.obj(profiles),
    "reason": "No supported public boundary is described for this function. Local descriptions are limited to 128 entries and 1 MiB.",
  }
}

///|
/// The standalone worker captures the policy and builds an immutable plan before
/// execution. Connected/native mappings continue to use their strict old path.
fn evaluate_capabilities(file : @ir.IRFile, request : Json) -> Json raise {
  let selection = @wire.optional(request, "admission").unwrap_or({
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "policy": "strict",
  })
  guard selection is Object(fields) &&
    fields.length() == 3 &&
    fields.get("profile") == Some(Json::string("morphir/workbench/admission")) &&
    fields.get("contractVersion") == Some(Json::string("0.1.0-draft.1")) else {
    raise @scheme.Invalid("Unknown checking-policy profile")
  }
  let policy : @typed_engine.AdmissionPolicy = match fields.get("policy") {
    Some(String("strict")) => Strict
    Some(String("permissive")) => Permissive
    _ => raise @scheme.Invalid("Unknown checking policy")
  }
  let reply = try {
    let raw = match @wire.optional(request, "argumentsIon") {
      Some(String(source)) =>
        @arguments.ion_arguments(Json::null(), source, true)
      _ => @wire.field(request, "arguments")
    }
    let suite = @protocol.Suite::from_json({
      "profile": "morphir-invocations-v1",
      "calls": [
        {
          "id": "workbench",
          "entry": @wire.field(request, "entry"),
          "arguments": raw,
        },
      ],
    })
    let plan = @typed_engine.plan_scheme_capabilities(
      @data.IRUnit::new("workbench", file),
      suite,
      policy~,
    )
    let outcomes = plan.evaluate_outcomes()
    (
      {
        "profile": "scheme-portable-v1/shared-sdk/bounded",
        "terminalOutcomes": outcomes.to_json(),
        "admission": selection,
      } : Json)
  } catch {
    error => {
      let (code, message) = capability_problem(error)
      let failed = failure(@outcomes.bounded(message, 480), code, "evaluate")
      guard failed is Object(fields) else { abort("failure object") }
      fields["admission"] = selection
      Json::object(fields)
    }
  }
  @outcomes.prepare(reply, expected_ids=Some(["workbench"])).0
}

///|
fn capability_problem(error : Error) -> (String, String) {
  match error {
    @ion.Syntax(message) => ("ion.syntax", "Ion: " + message)
    @ion.DataModel(message) => ("ion.data_model", "Ion: " + message)
    @ion.Unsupported(message) => ("ion.unsupported", "Ion: " + message)
    @typed_engine.AdmissionInvalid(code) | @protocol.Invalid(code) =>
      (code, code)
    @moonbit.Invalid(code, _, detail) => (code, detail)
    @wire.Invalid(code, detail) => (code, detail)
    _ => (scheme_code(error), @scheme.error_message(error))
  }
}

///|
fn evaluate_typed(file : @ir.IRFile, request : Json) -> Json raise {
  evaluate_typed_with(file, request, @typed_engine.Evaluator::scheme())
}

///|
fn evaluate_typed_with(
  file : @ir.IRFile,
  request : Json,
  evaluator : @typed_engine.Evaluator,
) -> Json raise {
  let raw = match @wire.optional(request, "argumentsIon") {
    Some(String(source)) =>
      @wire.array(@arguments.ion_arguments(Json::null(), source, true))
    _ => @wire.array(@wire.field(request, "arguments"))
  }
  let entry = @wire.string(@wire.field(request, "entry"))
  // Decode and validate the published profile before entering the runtime.
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [{ "id": "workbench", "entry": entry, "arguments": raw }],
  })
  // The public decoder enforces the encoded byte budget too.
  ignore(@protocol.Suite::decode(suite.encode("json"), "json"))
  let unit = @data.IRUnit::new("workbench", file)
  let plan = @typed_engine.plan(unit, suite)
  let manifest = plan.library.invocations.filter(e => e.fqname == entry)[0]
  let terminal : @protocol.TerminalOutcome = try {
    let value = (evaluator.evaluate)(
      unit,
      suite.calls[0],
      manifest.output,
      plan.library.invocation_types,
    )
    match value {
      ModelError(code) => ModelError(code)
      _ => Returned(value)
    }
  } catch {
    error =>
      Failed({
        stage: Evaluate,
        code: "execution.evaluate",
        message: @outcomes.bounded(@scheme.error_message(error), 480),
      })
  }
  let evidence : @protocol.Outcomes = {
    calls: [{ id: suite.calls[0].id, outcome: terminal, }],
    cleanup: None,
    extensions: suite.extensions,
  }
  @protocol.validate_outcomes(
    evidence,
    suite,
    plan.library.invocations.map(e => @protocol.PublicEntry::{
      name: e.fqname,
      inputs: e.inputs,
      output: e.output,
    }),
    plan.library.invocation_types,
  )
  let reply : Json = {
    "profile": evaluator.profile,
    "terminalOutcomes": evidence.to_json(),
    "message": match terminal {
      Failed(failure) => failure.code + ": " + failure.message
      _ => ""
    },
  }
  @outcomes.prepare(reply, expected_ids=Some(["workbench"])).0
}

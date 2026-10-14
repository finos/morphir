///|
/// The manifest is authoritative for public execution boundaries. Importing an
/// unsupported model still succeeds and leaves the local Scheme mode available.
fn typed_profiles(file : @ir.IRFile) -> Json {
  try {
    let library = @moonbit.generate(@moonbit.Input::new("workbench", file))
    let definitions = library.invocation_types
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
    let values = evaluation_definitions(file)
    let profiles = library.invocations.map(entry => {
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
      let names = match values.get(entry.fqname) {
        Some(ExpressionBody(inputs, _, _)) => inputs.map(p => display_name(p.0))
        _ => []
      }
      let profile : Json = {
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
      (entry.fqname, profile)
    })
    @wire.obj([("entries", @wire.obj(profiles))])
  } catch {
    @moonbit.Invalid(code, _, detail) =>
      @wire.obj([("reason", @wire.text(code + ": " + detail))])
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

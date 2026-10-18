///|
/// The controlled worker can consume a retained owner claim exactly once.
priv enum SelectedClaim {
  Retained(Json)
  Consumed
}

///|
/// Validate only fixture control structure here. Model, checking policy and
/// selection acceptance remain decisions of production decoders and owners.
fn admit_policy_owner_input(input : Json) -> Unit raise {
  guard input is Object(fields) else {
    abort("native policy owner MCK: object")
  }
  let evaluation = field(input, "evaluation")
  guard evaluation is Object(values) &&
    values.contains("runtime") &&
    values.contains("providerId") &&
    values
    .keys()
    .all(key => {
      ["model", "entry", "inputs", "runtime", "providerId", "admission"].contains(
        key,
      )
    }) else {
    abort("native policy owner MCK: evaluation fields")
  }
  ignore(text(values["runtime"]))
  ignore(text(values["providerId"]))
  let common_evaluation = values.copy()
  common_evaluation.remove("runtime") |> ignore
  common_evaluation.remove("providerId") |> ignore
  common_evaluation.remove("admission") |> ignore
  let actions : Array[Json] = []
  for action in array(field(input, "actions"), 32) {
    let op = text(field(action, "op"))
    if op == "claim" || op == "evaluate" {
      guard action is Object(parts) else {
        abort("native policy owner MCK: selected action")
      }
      ignore(
        closed(
          action,
          if op == "claim" && parts.contains("selection") {
            ["op", "execution", "selection"]
          } else {
            ["op", "execution"]
          },
        ),
      )
      ignore(text(field(action, "execution"), token=true))
      if parts.get("selection") is Some(selection) {
        let selection = closed(selection, [
          "planId", "runtime", "policy", "providerId",
        ])
        for key in ["planId", "runtime", "policy", "providerId"] {
          ignore(text(selection[key]))
        }
      }
    } else {
      actions.push(action)
    }
  }
  let common = fields.copy()
  common["evaluation"] = Json::object(common_evaluation)
  common["actions"] = Json::array(actions)
  admit_input(Json::object(common))
}

///|
fn Runtime::policy_execution_request(
  self : Runtime,
  service : ControlledExecutions,
  operation : String,
  payload : Json,
  path : String,
) -> Bytes {
  try {
    let result = service.host.handle(
      (
        {
          "op": if path == "submit" {
            "submit-native-policy"
          } else {
            path
          },
          "body": payload.stringify(),
        } : Json).stringify(),
    )
    if field(result, "ok") == Json::boolean(false) {
      return @reply.failure(
        @native.native_code(text(field(result, "code"))),
        @reply.NoEffect,
      )
    }
    let value = field(result, "value")
    if path == "submit" {
      ignore(self.aliases.identity(field(value, "identity")))
      self.accepted_plans.push(
        self.aliases.execution_value(field(value, "plan")),
      )
    }
    @reply.success_policy(operation, value)
  } catch {
    _ => @reply.failure(@reply.Unavailable, @reply.UnknownEffect)
  }
}

///|
fn selected_context(plan : Json) -> Json {
  {
    "planId": field(plan, "planId"),
    "runtime": field(plan, "runtime"),
    "policy": field(field(plan, "admission"), "policy"),
    "providerId": field(field(plan, "identity"), "providerId"),
  }
}

///|
fn Runtime::selected_action(self : Runtime, action : Json) -> Unit {
  let op = text(field(action, "op"))
  let name = text(field(action, "execution"))
  guard action is Object(action_fields) else {
    abort("native policy owner selected action")
  }
  let mut selection = action_fields.get("selection").unwrap_or(Json::null())
  let mut outcomes = Json::null()
  let mut code = Json::null()
  try {
    guard self.aliases.reverse.get(name) is Some(identity) &&
      self.services.get(host_scope(identity)) is Some(service) else {
      raise @executions.Invalid("workbench.host_selection_mismatch")
    }
    let accepted = service.host.scheme_selection(identity)
    let expected = selected_context(accepted.projection())
    if selection == Json::null() {
      selection = expected
    }
    if selection != expected {
      // Exercise the production owner boundary with the supplied mismatch.
      // A fixture comparison alone must not manufacture rejection evidence.
      let rejected = service.host.handle(
        (
          { "op": "claim-scheme", "identity": identity, "selection": selection } :
          Json).stringify(),
      )
      guard field(rejected, "ok") == Json::boolean(false) else {
        abort("native policy owner MCK: owner claimed a mismatched selection")
      }
      raise @executions.Invalid(text(field(rejected, "code")))
    }
    if op == "claim" {
      let request = service.host.claim_selected(accepted)
      self.claims[name] = Retained(request)
    } else {
      guard self.claims.get(name) is Some(Retained(request)) else {
        raise @executions.Invalid("workbench.host_already_claimed")
      }
      self.claims[name] = Consumed
      let result = @executions.evaluate_scheme_claim(request)
      outcomes = field(result, "terminalOutcomes")
      let completion = service.host.handle(
        ({ "op": "complete", "identity": identity, "outcomes": outcomes } : Json).stringify(),
      )
      if field(completion, "ok") != Json::boolean(true) {
        outcomes = Json::null()
        raise @executions.Invalid(text(field(completion, "code")))
      }
    }
  } catch {
    @executions.Invalid(reason) => code = Json::string(reason)
    @owner.Invalid(reason) => code = Json::string(reason)
    _ => code = Json::string("workbench.host_selection_mismatch")
  }
  self.selected_results.push({
    "op": op,
    "execution": name,
    "status": if code == Json::null() {
      "ok"
    } else {
      "invalid"
    },
    "code": code,
    "selection": selection,
    "outcomes": outcomes,
  })
}

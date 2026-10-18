///|
async test "policy owner retains selection across claim and evaluates it once" {
  let response = @mck.handle_line(
    (
      {
        "id": 1,
        "op": "run-native-policy-owner",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.22",
        "format": "json",
        "input": {
          "context": { "window": "main", "origin": "app", "page": "page" },
          "services": { "executions": "enabled", "workspace": false },
          "evaluation": {
            "model": "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"client\",\"dependencies\":{},\"def\":{\"modules\":{\"main\":{\"Public\":{\"types\":{},\"values\":{\"answer\":{\"Public\":{\"doc\":\"Native client immutable fixture\",\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}}}}}}}}}",
            "entry": "client:main#answer",
            "inputs": { "format": "json", "source": "[]" },
            "runtime": "scheme",
            "providerId": "moonbit-scheme",
            "admission": {
              "profile": "morphir/workbench/admission",
              "contractVersion": "0.1.0-draft.1",
              "policy": "permissive",
            },
          },
          "roots": [],
          "pickers": [],
          "cleanups": [],
          "actions": [
            { "op": "call", "id": "open", "operation": "session.open" },
            {
              "op": "call",
              "id": "submit",
              "operation": "execution.submit",
              "session": "session-1",
            },
            {
              "op": "claim",
              "execution": "execution-1",
              "selection": {
                "planId": "plan-1",
                "runtime": "scheme",
                "policy": "strict",
                "providerId": "moonbit-scheme",
              },
            },
            { "op": "claim", "execution": "execution-1" },
            { "op": "claim", "execution": "execution-1" },
            { "op": "evaluate", "execution": "execution-1" },
            { "op": "evaluate", "execution": "execution-1" },
          ],
        },
      } : Json).stringify(),
  ).unwrap()
  guard response is Object(reply) &&
    reply["value"] is Object(value) &&
    value["acceptedPlans"] is Array(plans) &&
    value["selectedResults"] is Array(results) else {
    fail("Expected policy owner observation")
  }
  assert_eq(plans.length(), 1)
  guard results[0] is Object(mismatch) &&
    results[1] is Object(claim) &&
    results[2] is Object(duplicate) &&
    results[3] is Object(evaluated) &&
    results[4] is Object(repeated) else {
    fail("Expected selected execution observations")
  }
  assert_eq(mismatch["code"], Json::string("workbench.host_selection_mismatch"))
  assert_eq(claim["status"], Json::string("ok"))
  assert_eq(claim["outcomes"], Json::null())
  assert_eq(duplicate["code"], Json::string("workbench.host_already_claimed"))
  assert_eq(evaluated["status"], Json::string("ok"))
  assert_eq(evaluated["selection"], claim["selection"])
  assert_eq(
    evaluated["outcomes"],
    (
      {
        "contractVersion": "0.1.0-draft.5",
        "cleanup": null,
        "extensions": null,
        "calls": [
          {
            "id": "workbench",
            "outcome": {
              "status": "returned",
              "value": { "type": "int", "value": "42" },
            },
          },
        ],
      } : Json),
  )
  assert_eq(repeated["code"], Json::string("workbench.host_already_claimed"))
}

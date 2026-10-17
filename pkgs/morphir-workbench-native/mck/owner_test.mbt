///|
async test "wrong window reaches owner caller admission without dependencies" {
  let response = @mck.handle_line(
    (
      {
        "id": 1,
        "op": "run-native-owner",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.10",
        "format": "json",
        "input": {
          "context": { "window": "other", "origin": "app", "page": "page" },
          "services": { "jobs": "enabled", "workspace": true },
          "evaluation": {
            "model": "opaque model",
            "entry": "demo:main#answer",
            "inputs": { "format": "json", "source": "[]" },
          },
          "roots": [],
          "pickers": [],
          "cleanups": [],
          "actions": [
            { "op": "call", "id": "open", "operation": "session.open" },
          ],
        },
      } : Json).stringify(),
  ).unwrap()
  guard response is Object(response) && response["value"] is Object(value) else {
    fail("Expected observation")
  }
  assert_eq(value["calls"], ([] : Json))
  assert_eq(
    value["results"],
    (
      [
        {
          "id": "open",
          "state": "returned",
          "failure": null,
          "cleanup": null,
          "reply": { "ok": false, "code": "unauthorized", "effect": "none" },
        },
      ] : Json),
  )
}

///|
async test "owner workspace captures inline bytes and rejects unresolved references" {
  let response = @mck.handle_line(
    (
      {
        "id": 1,
        "op": "run-native-owner",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.10",
        "format": "json",
        "input": {
          "context": { "window": "main", "origin": "app", "page": "page" },
          "services": { "jobs": "disabled", "workspace": true },
          "evaluation": {
            "model": "opaque",
            "entry": "demo:main#answer",
            "inputs": { "format": "json", "source": "[]" },
          },
          "roots": [
            {
              "id": "memory",
              "manifest": "{\"name\":\"demo/memory\",\"exposedModules\":[]}",
              "files": [
                {
                  "name": "morphir-ir.json",
                  "encoding": "utf8",
                  "source": "  original\n",
                },
              ],
            },
          ],
          "pickers": [
            { "id": "pick", "held": false, "root": "memory", "fail": false },
          ],
          "cleanups": [],
          "actions": [
            { "op": "call", "id": "open", "operation": "session.open" },
            {
              "op": "call",
              "id": "choose",
              "operation": "workspace.choose",
              "session": "session-1",
            },
            {
              "op": "call",
              "id": "capture",
              "operation": "workspace.open",
              "session": "session-1",
              "grant": "grant-1",
              "project": "project-1",
              "sequence": 1,
            },
            {
              "op": "replace",
              "root": "memory",
              "name": "morphir-ir.json",
              "encoding": "utf8",
              "source": "replacement",
            },
            {
              "op": "call",
              "id": "read",
              "operation": "workspace.read",
              "session": "session-1",
              "grant": "grant-1",
              "sequence": 1,
              "offset": 0,
            },
            {
              "op": "call",
              "id": "unknown",
              "operation": "session.check",
              "session": "session-99",
            },
          ],
        },
      } : Json).stringify(),
  ).unwrap()
  guard response is Object(response) &&
    response["value"] is Object(value) &&
    value["results"] is Array(results) else {
    fail("Expected results")
  }
  guard results[3] is Object(read) &&
    read["reply"] is Object(reply) &&
    reply["value"] is String(source) else {
    fail("Expected read")
  }
  guard @wire.parse(source) is Object(chunk) else { fail("Expected chunk") }
  assert_eq(chunk["content"], Json::string(@base64.encode(b"  original\n")))
  assert_eq(
    results[4],
    (
      {
        "id": "unknown",
        "state": "rejected",
        "reply": null,
        "cleanup": null,
        "failure": "reference",
      } : Json),
  )
  assert_eq(value["usedPickers"], Json::number(1))
}

///|
async test "held cleanup is shared across revoke and shutdown waiters" {
  let response = @mck.handle_line(
    (
      {
        "id": 1,
        "op": "run-native-owner",
        "suite": "workbench",
        "contractVersion": "0.1.0-draft.10",
        "format": "json",
        "input": {
          "context": { "window": "main", "origin": "app", "page": "page" },
          "services": { "jobs": "enabled", "workspace": false },
          "evaluation": {
            "model": "opaque",
            "entry": "demo:main#answer",
            "inputs": { "format": "json", "source": "[]" },
          },
          "roots": [],
          "pickers": [],
          "cleanups": [
            {
              "id": "exit",
              "session": "session-1",
              "held": true,
              "success": false,
            },
          ],
          "actions": [
            { "op": "call", "id": "open", "operation": "session.open" },
            { "op": "revoke" },
            { "op": "shutdown", "id": "shutdown" },
            { "op": "deliver", "id": "exit" },
          ],
        },
      } : Json).stringify(),
  ).unwrap()
  guard response is Object(response) &&
    response["value"] is Object(value) &&
    value["steps"] is Array(steps) &&
    value["results"] is Array(results) else {
    fail("Expected observation")
  }
  guard steps[2] is Object(step) else { fail("Expected step") }
  guard results[0] is Object(open) && open["reply"] is Object(open_reply) else {
    fail("Expected descriptor")
  }
  assert_eq(
    open_reply["value"],
    Json::string(
      "{\"contractVersion\":\"0.1.0-draft.1\",\"offer\":{\"contractVersion\":\"0.1.0-draft.1\",\"hostId\":\"host-1\",\"operations\":[\"query\",\"cancel\"],\"profile\":\"morphir/workbench/jobs\",\"providerId\":\"moonbit-scheme\",\"sessionId\":\"session-1\"},\"operations\":[\"jobs\"],\"profile\":\"morphir/workbench/native\",\"sessionId\":\"session-1\"}",
    ),
  )
  assert_eq(
    step["attempts"],
    (
      [
        { "id": "open", "state": "returned" },
        { "id": "shutdown", "state": "pending" },
      ] : Json),
  )
  assert_eq(
    results[1],
    (
      {
        "id": "shutdown",
        "state": "rejected",
        "reply": null,
        "cleanup": false,
        "failure": null,
      } : Json),
  )
  assert_eq(value["usedCleanups"], Json::number(1))
  assert_eq(value["unusedCleanups"], Json::number(0))
}

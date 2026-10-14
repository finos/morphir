///|
fn terminal_request(
  calls : Array[Json],
  cleanup? : Json = Json::null(),
) -> Json {
  {
    "id": 1,
    "op": "validate-outcomes",
    "suite": "workbench",
    "contractVersion": "0.1.0-draft.5",
    "format": "json",
    "input": {
      "suite": {
        "profile": "morphir-invocations-v1",
        "calls": [{ "id": "first", "entry": "demo:main#run", "arguments": [] }],
      },
      "manifest": {
        "entries": [
          { "name": "demo:main#run", "inputs": [], "output": { "type": "int" } },
        ],
        "definitions": [],
      },
      "outcomes": {
        "contractVersion": "0.1.0-draft.5",
        "calls": calls,
        "cleanup": cleanup,
        "extensions": Json::null(),
      },
    },
  }
}

///|
test "terminal admission preserves returned value and separate cleanup failure" {
  let call : Json = {
    "id": "first",
    "outcome": {
      "status": "returned",
      "value": { "type": "int", "value": "0009007199254740993" },
    },
  }
  let cleanup : Json = {
    "stage": "cleanup",
    "code": "provider.dispose",
    "message": "Disposal failed",
  }
  assert_eq(@mck.handle(terminal_request([call], cleanup~)), {
    "id": 1,
    "status": "ok",
    "value": {
      "contractVersion": "0.1.0-draft.5",
      "calls": [
        {
          "id": "first",
          "outcome": {
            "status": "returned",
            "value": { "type": "int", "value": "9007199254740993" },
          },
        },
      ],
      "cleanup": cleanup,
      "extensions": Json::null(),
    },
  })
}

///|
test "terminal admission retains the primary failure alongside cleanup" {
  let call : Json = {
    "id": "first",
    "outcome": {
      "status": "failed",
      "failure": {
        "stage": "invoke",
        "code": "provider.crash",
        "message": "Invocation failed",
      },
    },
  }
  let cleanup : Json = {
    "stage": "cleanup",
    "code": "provider.dispose",
    "message": "Disposal failed",
  }
  let response = @mck.handle(terminal_request([call], cleanup~))
  assert_eq(response, {
    "id": 1,
    "status": "ok",
    "value": {
      "contractVersion": "0.1.0-draft.5",
      "calls": [call],
      "cleanup": cleanup,
      "extensions": Json::null(),
    },
  })
}

///|
test "terminal admission requires complete inventory and declared outputs" {
  assert_eq(@mck.handle(terminal_request([])), {
    "id": 1,
    "status": "invalid",
    "code": "execution.result_count",
  })
  assert_eq(
    @mck.handle(
      terminal_request([
        {
          "id": "first",
          "outcome": {
            "status": "returned",
            "value": { "type": "bool", "value": true },
          },
        },
      ]),
    ),
    { "id": 1, "status": "invalid", "code": "execution.wrong_type" },
  )
}

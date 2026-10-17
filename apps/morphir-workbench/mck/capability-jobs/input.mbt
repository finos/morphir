///|
fn valid_selection(value : Json) -> Bool {
  closed(value, ["planId", "runtime", "policy", "providerId"]) &&
  text_limit(field_value(value, "planId"), 128, nonempty=true) &&
  text_limit(field_value(value, "runtime"), 128, nonempty=true) &&
  text_limit(field_value(value, "policy"), 128, nonempty=true) &&
  text_limit(field_value(value, "providerId"), 128, nonempty=true)
}

///|
fn valid_submission(value : Json) -> Bool {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(name => {
      ["model", "calls", "runtime", "admission", "extensions"].contains(name)
    }) &&
    fields.contains("extensions") &&
    text_limit(field_value(value, "model"), 262144) &&
    field_value(value, "runtime") == Json::string("scheme") &&
    field_value(value, "calls") is Array(calls) &&
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
  if fields.get("admission") is Some(selection) {
    if !closed(selection, ["profile", "contractVersion", "policy"]) ||
      field_value(selection, "profile") !=
      Json::string("morphir/workbench/admission") ||
      field_value(selection, "contractVersion") != Json::string("0.1.0-draft.1") ||
      ![Json::string("strict"), Json::string("permissive")].contains(
        field_value(selection, "policy"),
      ) {
      return false
    }
  }
  match field_value(value, "extensions") {
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
fn valid_offer(value : Json) -> Bool {
  guard closed(value, [
      "profile", "contractVersion", "hostId", "sessionId", "providerId", "operations",
    ]) &&
    field_value(value, "profile") == Json::string("morphir/workbench/jobs") &&
    field_value(value, "contractVersion") == Json::string("0.1.0-draft.1") &&
    ["hostId", "sessionId", "providerId"].all(name => {
      text_limit(field_value(value, name), 128, nonempty=true)
    }) &&
    field_value(value, "operations") is Array(operations) &&
    operations.length() >= 1 &&
    operations.length() <= 2 else {
    return false
  }
  operations.contains(Json::string("query")) &&
  operations.all(op => {
    [Json::string("query"), Json::string("cancel")].contains(op)
  }) &&
  (operations.length() == 1 || operations[0] != operations[1])
}

///|
fn valid_input(value : Json) -> Bool {
  guard closed(value, ["offer", "submission", "actions"]) &&
    @utf8.encode(value.stringify()).length() <= 1048576 &&
    valid_offer(field_value(value, "offer")) &&
    valid_submission(field_value(value, "submission")) &&
    field_value(value, "actions") is Array(actions) &&
    actions.length() <= 32 else {
    return false
  }
  let mut replans = 0
  for action in actions {
    if field_value(action, "op") == Json::string("replan") {
      replans += 1
      if replans > 3 {
        return false
      }
    }
    let op = field_value(action, "op")
    if op == Json::string("transport-gap") {
      if !closed(action, ["op"]) {
        return false
      }
      continue
    }
    if op == Json::string("mutate-caller") {
      if !closed(action, ["op", "policy"]) ||
        ![Json::string("strict"), Json::string("permissive")].contains(
          field_value(action, "policy"),
        ) {
        return false
      }
      continue
    }
    guard field_value(action, "job") is Number(job, ..) &&
      job >= 0 &&
      job <= 3 &&
      job.floor() == job else {
      return false
    }
    if [
        "inspect", "query", "cancel", "release", "query-lost-reply", "mutate-plan-view",
      ]
      .map(Json::string)
      .contains(op) {
      if !closed(action, ["op", "job"]) {
        return false
      }
    } else if ["claim", "run", "replan", "claim-lost-reply"]
      .map(Json::string)
      .contains(op) {
      if !closed(action, ["op", "job", "selection"]) ||
        !valid_selection(field_value(action, "selection")) {
        return false
      }
    } else if op == Json::string("complete") {
      if !closed(action, ["op", "job", "outcomes"]) ||
        !text_payload(field_value(action, "outcomes")) {
        return false
      }
    } else {
      return false
    }
  }
  true
}

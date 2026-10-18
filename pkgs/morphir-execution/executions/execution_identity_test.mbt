///|
test "accepted execution identities use executionId" {
  let source : Json = {
    "hostId": "host",
    "sessionId": "session",
    "providerId": "provider",
    "executionId": "execution-1",
    "snapshotId": "snapshot",
  }
  let identity = @executions.Identity::from_json(source)
  assert_eq(identity.to_json(), source)
  assert_eq(identity.execution_id().to_string(), "execution-1")
}

///|
test "execution identity rejects retired and duplicate identity fields" {
  for
    source in [
      "{\"hostId\":\"host\",\"sessionId\":\"session\",\"providerId\":\"provider\",\"jobId\":\"old\",\"snapshotId\":\"snapshot\"}",
      "{\"hostId\":\"host\",\"sessionId\":\"session\",\"providerId\":\"provider\",\"jobId\":\"old\",\"executionId\":\"new\",\"snapshotId\":\"snapshot\"}",
    ] {
    let accepted = try {
      ignore(@executions.Identity::from_json(@json.parse(source)))
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
}

///|
test "opaque execution IDs enforce nonempty UTF16 bounds" {
  for value in ["execution-1", "x".repeat(128), "😀".repeat(64)] {
    assert_eq(@executions.ExecutionId::from_string(value).to_string(), value)
  }
  for value in ["", "x".repeat(129), "😀".repeat(65)] {
    let accepted = try {
      ignore(@executions.ExecutionId::from_string(value))
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
}

///|
test "execution offers require the replacement profile and exact version" {
  for
    (profile, version) in [
      ("morphir/workbench/jobs", "0.2.0-draft.1"),
      ("morphir/workbench/executions", "0.1.0-draft.1"),
      ("morphir/workbench/executions", "0.2.0-draft.1+build"),
    ] {
    let accepted = try {
      ignore(
        @executions.Offer::from_json({
          "profile": profile,
          "contractVersion": version,
          "hostId": "host",
          "sessionId": "session",
          "providerId": "provider",
          "operations": ["query"],
        }),
      )
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
}

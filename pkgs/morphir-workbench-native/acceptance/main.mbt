///|
fn fixture_executable(
  executable : String,
  arguments : ArrayView[String],
) -> String raise {
  let command = @argparse.Command(
    "acceptance",
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
    positionals=[
      @argparse.PositionArg(
        "fixture-executable",
        num_args=@argparse.ValueRange(lower=0),
      ),
    ],
  )
  // Legacy callers select the last literal operand, or this executable when no
  // operand is supplied. These values are never forwarded as a child argv tail.
  let literal = ["--"]
  literal.append(arguments)
  let matches = command.parse(argv=literal, env=Map([]))
  match matches.values.get("fixture-executable") {
    Some(values) => values.last().unwrap_or(executable)
    None => executable
  }
}

///|
fn body(format~ : String = "json") -> String raise {
  (
    {
      "contractVersion": "0.2.0-draft.1",
      "model": @codec.to_json(@fixtures.invocation_library()).stringify(),
      "entry": "calls:main#subtract",
      "inputs": {
        "format": format,
        "source": if format == "json" {
          "[{\"type\":\"int\",\"value\":\"45\"},{\"type\":\"int\",\"value\":\"3\"}]"
        } else {
          "[45,3]"
        },
      },
    } : Json).stringify()
}

///|
fn value(reply : Json) -> Json raise {
  assert_eq(
    @wire.field(reply, "status"),
    Json::number(200),
    msg=reply.stringify(),
  )
  @executions.decode(@wire.string(@wire.field(reply, "source")))
}

///|
fn identity(service : @native.Service, format~ : String = "json") -> Json raise {
  @wire.field(value(service.request("submit", Some(body(format~)))), "identity")
}

///|
fn request(identity : Json) -> String {
  ({ "contractVersion": "0.2.0-draft.1", "identity": identity } : Json).stringify()
}

///|
async fn terminal(service : @native.Service, id : Json) -> Json {
  for _ in 0..<1000 {
    let receipt = value(service.request("query", Some(request(id))))
    if @wire.field(receipt, "state") == Json::string("terminal") {
      return receipt
    }
    @async.sleep(10)
  }
  abort("Native worker failed to terminate within acceptance deadline")
}

///|
fn outcome(receipt : Json) -> Json raise {
  @wire.field(
    @wire.array(@wire.field(@wire.field(receipt, "outcomes"), "calls"))[0],
    "outcome",
  )
}

///|
async fn main {
  let args = @env.args()
  let executable = fixture_executable(args[0], args[1:])
  let directory = @env.current_dir().unwrap() +
    "/.dev/native-workers-" +
    @env.now().to_string()
  @fs.mkdir(directory)
  defer @fs.rmdir(directory, recursive=true)
  let binary = @fs.read_file(executable)
  let mut count = 0
  for
    mode in [
      "normal", "fault-hang", "fault-crash", "fault-frame", "fault-stderr", "fault-after",
      "fault-trailing", "fault-late-cancel", "fault-memory",
    ] {
    let path = directory + "/" + mode + ".exe"
    @fs.write_file(path, binary, permission=0o700)
    @fs.chmod(path, 0o700)
    @async.with_task_group(async fn(group) {
      let service = @native.Service::new(
        group,
        path,
        "acceptance-" + mode,
        deadline=if mode == "fault-hang" { 100 } else { 5000 },
        memory=if mode == "fault-memory" { 1.0 } else { 268435456.0 },
      )
      defer service.close()
      for
        format in (if mode == "normal" {
          ["json", "ion-text"]
        } else {
          ["json"]
        }) {
        let id = identity(service, format~)
        if mode == "fault-late-cancel" {
          for _ in 0..<500 {
            if @wire.field(service.stats(), "captured") != Json::number(0) {
              break
            }
            @async.sleep(10)
          }
          assert_eq(@wire.field(service.stats(), "captured"), Json::number(1))
          ignore(value(service.request("cancel", Some(request(id)))))
        }
        let receipt = terminal(service, id)
        assert_eq(@wire.field(service.stats(), "active"), Json::number(0))
        for child in @wire.array(@wire.field(service.stats(), "children")) {
          assert_eq(@wire.field(child, "exited"), Json::boolean(true))
          assert_eq(@wire.field(child, "residentBytes"), Json::number(-1))
        }
        let result = outcome(receipt)
        if ["normal", "fault-after", "fault-trailing", "fault-late-cancel"].contains(
            mode,
          ) {
          assert_eq(
            @wire.field(result, "status"),
            Json::string("returned"),
            msg=mode + " " + receipt.stringify(),
          )
          assert_eq(@wire.field(result, "value"), {
            "type": "int",
            "value": "42",
          })
          assert_eq(
            @wire.field(@wire.field(receipt, "outcomes"), "cleanup") ==
            Json::null(),
            ["normal", "fault-late-cancel"].contains(mode),
          )
        } else {
          assert_eq(@wire.field(result, "status"), Json::string("failed"))
          let code = @wire.string(
            @wire.field(@wire.field(result, "failure"), "code"),
          )
          assert_eq(
            code,
            match mode {
              "fault-hang" => "workbench.worker_deadline"
              "fault-memory" => "workbench.worker_memory"
              "fault-frame" | "fault-crash" => "workbench.worker_frame"
              _ => "workbench.worker_stderr_limit"
            },
          )
        }
        ignore(value(service.request("release", Some(request(id)))))
        count += 1
      }
      service.shutdown()
      assert_eq(@wire.field(service.stats(), "uncertain"), Json::boolean(false))
      assert_eq(@wire.field(service.stats(), "retained"), Json::number(0))
    })
  }
  @async.with_task_group(async fn(group) {
    let service = @native.Service::new(group, executable, "pricing")
    defer service.close()
    let model = @codec.to_json(@fixtures.pricing()).stringify()
    let err : Json = {
      "type": "result",
      "case": "err",
      "value": { "type": "text", "units": [69] },
    }
    let exact : Json = {
      "type": "decimal",
      "coefficient": "9007199254740993",
      "exponent": -2,
    }
    for
      (entry, arguments, expected) in [
        (
          "pricing:boundaries#decimal",
          [exact],
          ({ "status": "returned", "value": exact } : Json),
        ),
        (
          "pricing:boundaries#result",
          [err],
          ({ "status": "returned", "value": err } : Json),
        ),
        (
          "pricing:results#failure",
          [],
          ({ "status": "model-error", "code": "sdk.division_by_zero" } : Json),
        ),
      ] {
      let payload : Json = {
        "contractVersion": "0.2.0-draft.1",
        "model": model,
        "entry": entry,
        "inputs": {
          "format": "json",
          "source": Json::array(arguments).stringify(),
        },
      }
      let submitted = value(
        service.request("submit", Some(payload.stringify())),
      )
      let id = @wire.field(submitted, "identity")
      assert_eq(outcome(terminal(service, id)), expected)
      ignore(value(service.request("release", Some(request(id)))))
      count += 1
    }
    for
      (format, source) in [
        (
          "json", "[{\"type\":\"record\",\"fields\":[{\"name\":\"price\",\"value\":{\"type\":\"decimal\",\"coefficient\":\"125\",\"exponent\":-1}},{\"name\":\"quantity\",\"value\":{\"type\":\"int\",\"value\":\"3\"}}]}]",
        ),
        (
          "ion-text", "[morphir_value::{type:\"record\",fields:[{name:\"price\",value:{type:\"decimal\",coefficient:\"125\",exponent:-1}},{name:\"quantity\",value:{type:\"int\",value:\"3\"}}]}]",
        ),
      ] {
      let payload : Json = {
        "contractVersion": "0.2.0-draft.1",
        "model": model,
        "entry": "pricing:quotes#total",
        "inputs": { "format": format, "source": source },
      }
      let id = @wire.field(
        value(service.request("submit", Some(payload.stringify()))),
        "identity",
      )
      assert_eq(outcome(terminal(service, id)), {
        "status": "returned",
        "value": { "type": "decimal", "coefficient": "375", "exponent": -1 },
      })
      ignore(value(service.request("release", Some(request(id)))))
      count += 1
    }
    service.shutdown()
  })
  @async.with_task_group(async fn(group) {
    let service = @native.Service::new(
      group,
      directory + "/fault-hang.exe",
      "queue",
    )
    defer service.close()
    let ids = Array::makei(8, _ => identity(service))
    assert_eq(
      @wire.field(service.request("submit", Some(body())), "status"),
      Json::number(409),
    )
    @async.sleep(50)
    assert_eq(@wire.field(service.stats(), "active"), Json::number(2))
    assert_eq(
      @wire.field(
        value(service.request("query", Some(request(ids[2])))),
        "state",
      ),
      Json::string("submitted"),
    )
    ignore(value(service.request("cancel", Some(request(ids[2])))))
    assert_eq(
      @wire.field(outcome(terminal(service, ids[2])), "status"),
      Json::string("cancelled"),
    )
    assert_eq(@wire.field(service.stats(), "queued"), Json::number(5))
    ignore(value(service.request("release", Some(request(ids[2])))))
    let acknowledgement = value(
      service.request("cancel", Some(request(ids[0]))),
    )
    assert_eq(
      @wire.field(acknowledgement, "cancelRequested"),
      Json::boolean(true),
    )
    assert_eq(@wire.field(acknowledgement, "state"), Json::string("running"))
    let stopped = terminal(service, ids[0])
    assert_eq(
      @wire.field(outcome(stopped), "status"),
      Json::string("cancelled"),
    )
    service.shutdown()
    assert_eq(@wire.field(service.stats(), "active"), Json::number(0))
    assert_eq(@wire.field(service.stats(), "completed"), Json::number(7))
    for child in @wire.array(@wire.field(service.stats(), "children")) {
      assert_eq(@wire.field(child, "exited"), Json::boolean(true))
      assert_eq(@wire.field(child, "residentBytes"), Json::number(-1))
    }
    count += 1
  })
  count += policy_acceptance(executable)
  println(
    (
      {
        "nativeWorkers": true,
        "cases": count,
        "framing": true,
        "confirmedExit": true,
        "lateCancellation": true,
      } : Json).stringify(),
  )
}

///|
fn selected_body(source : String, policy : String?, format : String) -> Json {
  let fields : Map[String, Json] = {
    "contractVersion": "0.2.0-draft.1",
    "model": source,
    "entry": "selected:main#answer",
    "runtime": "scheme",
    "providerId": "moonbit-scheme",
    "inputs": { "format": format, "source": "[]" },
  }
  if policy is Some(policy) {
    fields["admission"] = {
      "profile": "morphir/workbench/admission",
      "contractVersion": "0.1.0-draft.1",
      "policy": policy,
    }
  }
  Json::object(fields)
}

///|
async fn policy_acceptance(executable : String) -> Int32 {
  let model = @fs.read_file(
    "apps/morphir-workbench/fixtures/capability-execution.json",
  ).text()
  let mut count = 0
  @async.with_task_group(async fn(group) {
    let service = @native.Service::new(group, executable, "native-checking")
    defer service.close()
    for policy in [None, Some("strict")] {
      let rejected = service.policy_request(
        "submit",
        Some(selected_body(model, policy, "json").stringify()),
      )
      assert_eq(@wire.field(rejected, "status"), Json::number(400))
      assert_eq(@wire.field(service.stats(), "retained"), Json::number(0))
      count += 1
    }
    for format in ["json", "ion-text"] {
      for taken in [false, true] {
        let changed = @executions.decode(model)
        let library = @wire.field(
          @wire.field(changed, "distribution"),
          "Library",
        )
        let module_def = @wire.field(
          @wire.field(
            @wire.field(@wire.field(library, "def"), "modules"),
            "main",
          ),
          "Public",
        )
        let definition = @wire.field(
          @wire.field(@wire.field(module_def, "values"), "answer"),
          "Public",
        )
        let expression = @wire.field(definition, "ExpressionBody")
        guard @wire.field(@wire.field(expression, "body"), "IfThenElse")
          is Object(branch) else {
          abort("Policy fixture")
        }
        branch["condition"] = Json::boolean(taken)
        let payload = selected_body(
          changed.stringify(),
          Some("permissive"),
          format,
        )
        let accepted = value(
          service.policy_request("submit", Some(payload.stringify())),
        )
        let id = @wire.field(accepted, "identity")
        let captured = @wire.field(accepted, "plan")
        assert_eq(
          @wire.field(@wire.field(captured, "admission"), "policy"),
          Json::string("permissive"),
        )
        // Edits to caller-owned inputs after acceptance cannot change the worker.
        guard payload is Object(fields) else { abort("Payload") }
        fields["admission"] = {
          "profile": "morphir/workbench/admission",
          "contractVersion": "0.1.0-draft.1",
          "policy": "strict",
        }
        fields["model"] = Json::string("{}")
        let result = outcome(terminal(service, id))
        if taken {
          assert_eq(@wire.field(result, "status"), Json::string("failed"))
          assert_eq(
            @wire.field(@wire.field(result, "failure"), "code"),
            Json::string("execution.unsupported_reached"),
          )
        } else {
          assert_eq(result, {
            "status": "returned",
            "value": { "type": "int", "value": "42" },
          })
        }
        ignore(value(service.policy_request("release", Some(request(id)))))
        count += 1
      }
    }
    assert_eq(@wire.field(service.stats(), "active"), Json::number(0))
    for child in @wire.array(@wire.field(service.stats(), "children")) {
      assert_eq(@wire.field(child, "exited"), Json::boolean(true))
      assert_eq(@wire.field(child, "residentBytes"), Json::number(-1))
    }
    service.shutdown()
    assert_eq(@wire.field(service.stats(), "retained"), Json::number(0))
  })
  count
}

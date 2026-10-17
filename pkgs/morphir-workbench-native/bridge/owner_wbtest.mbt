///|
fn test_frame(operation : String, id~ : String = "") -> String {
  let fields : Map[String, Json] = {
    "profile": "morphir/workbench/native",
    "contractVersion": "0.1.0-draft.1",
    "operation": Json::string(operation),
  }
  if operation != "session.open" {
    fields["sessionId"] = Json::string(id)
  }
  Json::object(fields).stringify()
}

///|
fn test_value(source : String, operation : String) -> Json raise {
  let decoded = @reply.decode(@utf8.encode(source), operation).to_json()
  guard decoded is Object(fields) &&
    fields.get("ok") == Some(Json::boolean(true)) &&
    fields.get("value") is Some(value) else {
    fail(source)
  }
  value
}

///|
fn test_id(value : Json) -> String raise {
  guard value is Object(fields) && fields.get("sessionId") is Some(String(id)) else {
    fail("Missing session")
  }
  id
}

///|
async test "replacement open rechecks the trusted page after awaited cleanup" {
  @async.with_task_group(async fn(group) {
    let created : Array[String] = []
    let entered = Ref(false)
    let released = Ref(false)
    let waiting = @async.CondVar::Cond()
    let release = @async.CondVar::Cond()
    let factory : (String) -> JobsService raise = fn(id) {
      created.push(id)
      {
        offer: fn() {
          {
            "profile": "morphir/workbench/jobs",
            "contractVersion": "0.1.0-draft.1",
            "hostId": "host",
            "sessionId": id,
            "providerId": "scheme",
            "operations": ["query", "cancel"],
          }
        },
        request: fn(_, _) {
          @reply.failure(@reply.Unavailable, @reply.NoEffect)
        },
        close: fn() { () },
        shutdown: async fn() {
          if id == created[0] && !released.val {
            entered.val = true
            waiting.broadcast()
            while !released.val {
              release.wait()
            }
          }
        },
      }
    }
    let owner = Owner::with_services(group, {
      jobs: Some(factory),
      workspace: None,
    })
    let page = Ref("page-A")
    let caller = fn() raise {
      @session.Caller::admit("main", "app", Some(page.val))
    }
    let picker : async () -> String? = fn() { None }
    let first = test_id(
      test_value(
        owner.request(test_frame("session.open"), caller, picker),
        "session.open",
      ),
    )
    page.val = "page-B"
    let opening = group.spawn(async fn() {
      owner.request(test_frame("session.open"), caller, picker)
    })
    while !entered.val {
      waiting.wait()
    }
    assert_eq(created.length(), 1)
    page.val = "page-C"
    released.val = true
    release.broadcast()
    let late = @reply.decode(@utf8.encode(opening.wait()), "session.open").to_json()
    guard late is Object(fields) && fields.get("error") is Some(Object(error)) else {
      fail(late.stringify())
    }
    assert_eq(error["code"], Json::string("unauthorized"))
    assert_eq(error["effect"], Json::string("unknown"))
    assert_eq(created.length(), 1)
    let current = test_id(
      test_value(
        owner.request(test_frame("session.open"), caller, picker),
        "session.open",
      ),
    )
    assert_true(current != first)
    assert_eq(created.length(), 2)
    owner.shutdown()
  })
}

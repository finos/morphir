///|
fn files_frame(
  operation : String,
  id~ : String = "",
  payload~ : Json? = None,
) -> String {
  let fields : Map[String, Json] = {
    "profile": @filewire.PROFILE,
    "contractVersion": @filewire.VERSION,
    "operation": Json::string(operation),
  }
  if operation != "session.open" {
    fields["sessionId"] = Json::string(id)
  }
  if payload is Some(value) {
    fields["payload"] = value
  }
  Json::object(fields).stringify()
}

///|
fn files_reply(request : String, reply : String) -> Map[String, Json] raise {
  guard @filewire.decode_reply(
      @filewire.decode_request(@utf8.encode(request)),
      @utf8.encode(reply),
    ).to_json()
    is Object(fields) else {
    abort("reply")
  }
  fields
}

///|
async test "file owner binds requests to the current page and shutdown cannot reopen" {
  let owner = FileOwner::new(enabled=true)
  let page = Ref("A")
  let caller = fn() raise {
    @session.Caller::admit("main", "app", Some(page.val))
  }
  let choose : async () -> String? = fn() { None }
  let opening = files_frame("session.open")
  let opened = files_reply(opening, owner.request(opening, caller, choose))
  guard opened["sessionId"] is String(id) else { abort("session") }
  let checking = files_frame("session.check", id~)
  assert_eq(
    files_reply(checking, owner.request(checking, caller, choose))["ok"],
    Json::boolean(true),
  )
  page.val = "B"
  assert_eq(
    files_reply(checking, owner.request(checking, caller, choose))["ok"],
    Json::boolean(false),
  )
  let replacement = files_reply(opening, owner.request(opening, caller, choose))
  assert_true(replacement["sessionId"] != opened["sessionId"])
  owner.close()
  assert_eq(
    files_reply(opening, owner.request(opening, caller, choose))["ok"],
    Json::boolean(false),
  )
}

///|
async test "a file picker returning after navigation cannot open its path" {
  @async.with_task_group(async fn(group) {
    let owner = FileOwner::new(enabled=true)
    defer owner.close()
    let page = Ref("A")
    let caller = fn() raise {
      @session.Caller::admit("main", "app", Some(page.val))
    }
    let opening = files_frame("session.open")
    let opened = files_reply(
      opening,
      owner.request(opening, caller, async fn() { None }),
    )
    guard opened["sessionId"] is String(id) else { abort("session") }
    let entered = Ref(false)
    let released = Ref(false)
    let wait = @async.CondVar::Cond()
    let release = @async.CondVar::Cond()
    let request = files_frame("workspace.choose-write", id~)
    let pending = group.spawn(async fn() {
      owner.request(request, caller, async fn() {
        entered.val = true
        wait.broadcast()
        while !released.val {
          release.wait()
        }
        Some("/never-open-this-native-path")
      })
    })
    while !entered.val {
      wait.wait()
    }
    page.val = "B"
    released.val = true
    release.broadcast()
    let reply = files_reply(request, pending.wait())
    assert_eq(reply["ok"], Json::boolean(false))
    guard reply["error"] is Object(error) else { abort("error") }
    assert_eq(error["code"], Json::string("workbench.native_stale_session"))
  })
}

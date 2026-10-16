///|
fn caller(page : String) -> Caller raise {
  Caller::admit("main", "app", Some(page))
}

///|
fn fields(reply : Json) -> Map[String, Json] {
  match reply {
    Object(values) => values
    _ => abort("Expected an object")
  }
}

///|
fn id(reply : Json) -> String {
  match fields(reply).get("sessionId") {
    Some(String(value)) => value
    _ => abort("Expected a session identity")
  }
}

///|
test "only native main-window app callers with a page can negotiate" {
  for
    (window, origin, page) in [
      ("other", "app", Some("page")),
      ("main", "https://example.com", Some("page")),
      ("main", "http://127.0.0.1:5173", Some("page")),
      ("main", "app", None),
      ("main", "app", Some("")),
    ] {
    let rejected = try {
      ignore(Caller::admit(window, origin, page))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "handshake is exact, stable for a page, and offers no execution operations" {
  let session = Session::new()
  let first = session.open(caller("one"), "0.1.0-draft.1")
  assert_eq(session.open(caller("one"), "0.1.0-draft.1"), first)
  assert_eq(session.check(caller("one"), id(first)), first)
  assert_eq(fields(first).get("operations"), Some(Json::array([])))
  assert_eq(fields(first).length(), 4)
  let rejected = try {
    ignore(session.open(caller("one"), "0.1.0-draft.2"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(session.check(caller("one"), id(first)), first)
}

///|
test "new page invalidates old identities and stale close cannot close its replacement" {
  let session = Session::new()
  let first = session.open(caller("one"), "0.1.0-draft.1")
  let next = session.open(caller("two"), "0.1.0-draft.1")
  assert_true(id(first) != id(next))
  for
    (page, value) in [("one", id(first)), ("one", id(next)), ("two", id(first))] {
    let rejected = try {
      ignore(session.close(caller(page), value))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(session.check(caller("two"), id(next)), next)
}

///|
test "navigation revokes access; window shutdown cannot be reopened" {
  let session = Session::new()
  let first = session.open(caller("one"), "0.1.0-draft.1")
  session.revoke()
  let rejected = try {
    ignore(session.check(caller("one"), id(first)))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let next = session.open(caller("one"), "0.1.0-draft.1")
  assert_true(id(first) != id(next))
  assert_eq(session.close(caller("one"), id(next)), { "ok": true })
  session.shutdown()
  session.revoke()
  let rejected = try {
    ignore(session.open(caller("one"), "0.1.0-draft.1"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
fn sample_request() -> String {
  let text =
    #|{"scope":"native-reader-adapter","caseId":"acme-orders/4.0.0/plainJson","binding":{"opaque":[1.00,"not an expectation"]},"treeRoot":"/private/tmp/tree","snapshot":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","irVersion":"4.0.0","profile":"plainJson","selection":"pkg/acme/orders/domain/module","pageSize":2,"documentLimit":8192,"attributes":[]}
  text
}

///|
test "request admission bounds and opaque binding" {
  let admitted = read_request(@utf8.encode(sample_request()))
  assert_eq(admitted.page_size, 2)
  assert_eq(admitted.selection, "pkg/acme/orders/domain/module")
  assert_eq(admitted.binding, "{\"opaque\":[1.00,\"not an expectation\"]}")
  for
    text in [
      sample_request().replace_all(old="\"pageSize\":2", new="\"pageSize\":0"),
      sample_request().replace_all(
        old="\"documentLimit\":8192",
        new="\"documentLimit\":8193",
      ),
      sample_request().replace_all(
        old="\"pageSize\":2",
        new="\"pageSize\":2,\"pageSize\":2",
      ),
      sample_request().replace_all(
        old="\"attributes\":[]",
        new="\"attributes\":[],\"unexpected\":true",
      ),
      sample_request().replace_all(
        old="\"binding\":{",
        new="\"binding\":{\"nested\":{\"x\":1,\"x\":2},",
      ),
      sample_request().replace_all(old="plainJson\"", new="unknown\""),
      sample_request().replace_all(
        old="\"selection\":\"pkg/acme/orders/domain/module\"",
        new="\"selection\":{\"package\":\"acme/orders\",\"module\":\"domain\"}",
      ),
      sample_request().replace_all(
        old="pkg/acme/orders/domain/module",
        new="../escape/module",
      ),
      sample_request() + " {}",
      " ".repeat(16385),
      "[".repeat(33) + "0" + "]".repeat(33),
    ] {
    let accepted = try {
      ignore(read_request(@utf8.encode(text)))
      true
    } catch {
      _ => false
    }
    assert_false(accepted)
  }
  let accepted = try {
    ignore(read_request(b"\xff"))
    true
  } catch {
    _ => false
  }
  assert_false(accepted)
}

///|
test "snapshot uses ordinal path and exact byte hashes" {
  let files = [("z.json", b"z"), ("a.json", b"a\n")]
  assert_eq(
    snapshot_digest(files),
    "3b12d998c0ca8c68ce9c23180fc2c543d15559421f225fb831356cede7d96eb5",
  )
}

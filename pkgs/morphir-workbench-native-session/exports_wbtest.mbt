///|
test "connected export origin uses the validated launch and canonical port" {
  assert_eq(
    loopback_launch_origin("http://127.0.0.1:1234/launch?token=a-b_c"),
    Some("http://127.0.0.1:1234"),
  )
  assert_eq(
    loopback_launch_origin("http://127.0.0.1:00080/launch?token=a"),
    Some("http://127.0.0.1"),
  )
  for
    url in [
      "http://localhost:1234/launch?token=a", "http://127.0.0.1:0/launch?token=a",
      "http://127.0.0.1:65536/launch?token=a", "http://127.0.0.1:1234/launch?token=",
      "http://127.0.0.1:1234/launch?token=a#fragment", "http://127.0.0.1:1234.evil/launch?token=a",
      "http://127.0.0.1:1234/launch?token=a&other=b",
    ] {
    assert_eq(loopback_launch_origin(url), None, msg=url)
  }
}

///|
test "export policy binds native main page and Blob origin without path authority" {
  assert_true(
    allow_blob_export(
      "main", "https://proton.localhost/index.html", "blob:https://proton.localhost/id",
    ),
  )
  assert_true(
    allow_blob_export("main", "proton://app/index.html", "blob:proton://app/id"),
  )
  assert_true(
    allow_blob_export(
      "main",
      "http://127.0.0.1:1234/?mode=connected",
      "blob:http://127.0.0.1:1234/id",
      connected_origin=Some("http://127.0.0.1:1234"),
    ),
  )
  assert_true(
    allow_blob_export(
      "main",
      "http://127.0.0.1/",
      "blob:http://127.0.0.1/id",
      connected_origin=Some("http://127.0.0.1"),
    ),
  )
  for
    (window, page, url, origin) in [
      (
        "other",
        "https://proton.localhost/",
        "blob:https://proton.localhost/id",
        None,
      ),
      ("main", "https://evil/", "blob:https://proton.localhost/id", None),
      (
        "main",
        "https://proton.localhost.evil/",
        "blob:https://proton.localhost/id",
        None,
      ),
      (
        "main",
        "https://proton.localhost/",
        "blob:https://proton.localhost.evil/id",
        None,
      ),
      (
        "main",
        "https://proton.localhost/",
        "https://proton.localhost/model.json",
        None,
      ),
      ("main", "https://proton.localhost/", "file:///etc/passwd", None),
      ("main", "https://proton.localhost/", "blob:null/id", None),
      (
        "main",
        "https://proton.localhost/",
        "blob:https://proton.localhost/",
        None,
      ),
      ("main", "http://127.0.0.1:1234/", "blob:http://127.0.0.1:1234/id", None),
      (
        "main",
        "http://127.0.0.1:4321/",
        "blob:http://127.0.0.1:4321/id",
        Some("http://127.0.0.1:1234"),
      ),
      ("main", "http://evil/", "blob:http://evil/id", Some("http://evil")),
    ] {
    assert_false(
      allow_blob_export(window, page, url, connected_origin=origin),
      msg=page + " " + url,
    )
  }
}

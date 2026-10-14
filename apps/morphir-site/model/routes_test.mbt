///|
test "doc routes" {
  assert_eq(@model.doc_route("README.md"), "/docs/")
  assert_eq(@model.doc_route("index.html"), "/docs/")
  assert_eq(@model.doc_route("adr/README.md"), "/docs/adr/")
  assert_eq(@model.doc_route("ARCHITECTURE.md"), "/docs/architecture/")
  assert_eq(
    @model.doc_route("adr/0001-versioned-ir-models.md"),
    "/docs/adr/0001-versioned-ir-models/",
  )
  assert_eq(@model.doc_route("design/site.html"), "/docs/design/site/")
}

///|
test "post parts and routes" {
  assert_eq(
    @model.post_parts("2026-10-13-hello-world.md"),
    Some(("2026-10-13", "hello-world")),
  )
  assert_eq(@model.post_parts("2026-10-13-x.html"), Some(("2026-10-13", "x")))
  assert_eq(@model.post_parts("hello.md"), None)
  assert_eq(@model.post_parts("2026-1-13-x.md"), None)
  assert_eq(@model.post_parts("2026-10-13-.md"), None)
  assert_eq(@model.post_route("hello-world"), "/blog/hello-world/")
  assert_eq(@model.package_route("morphir-ir"), "/docs/packages/morphir-ir/")
}

///|
test "problem render" {
  assert_eq(@model.problem("a.md", "bad").render(), "a.md: bad")
  assert_eq(@model.problem("a.md", "bad", line=3).render(), "a.md:3: bad")
}

///|
test "blog slugs are lower-case URL-safe segments" {
  assert_eq(@model.post_parts("2026-10-13-..md"), None)
  assert_eq(@model.post_parts("2026-10-13-...md"), None)
  assert_eq(@model.post_parts("2026-10-13-Hello.md"), None)
  assert_eq(@model.post_parts("2026-10-13-a b.md"), None)
  assert_eq(@model.post_parts("2026-10-13--x.md"), None)
  assert_eq(
    @model.post_parts("2026-10-13-v0-1-release.md"),
    Some(("2026-10-13", "v0-1-release")),
  )
}

///|
test "blog dates are real calendar dates" {
  assert_eq(@model.post_parts("2026-99-99-x.md"), None)
  assert_eq(@model.post_parts("2026-00-10-x.md"), None)
  assert_eq(@model.post_parts("2026-04-31-x.md"), None)
  assert_eq(@model.post_parts("2026-02-29-x.md"), None)
  assert_eq(@model.post_parts("2028-02-29-x.md"), Some(("2028-02-29", "x")))
  assert_eq(@model.post_parts("2100-02-29-x.md"), None)
  assert_eq(@model.post_parts("2000-02-29-x.md"), Some(("2000-02-29", "x")))
  assert_eq(@model.post_parts("2026-12-31-x.md"), Some(("2026-12-31", "x")))
}

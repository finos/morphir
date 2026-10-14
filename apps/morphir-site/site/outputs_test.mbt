///|
async test "build writes every route, feed, index and copies" {
  let built = @site.build(
    { ..config, packages: [], },
    [
      {
        path: "docs/ARCHITECTURE.md",
        text: Some("# Architecture\n\n![flow](images/flow.png)\n"),
      },
      { path: "docs/images/flow.png", text: None, },
      {
        path: "site/blog/2026-10-13-hello.md",
        text: Some(
          "---\ntitle: Hello\ndate: 2026-10-13\nauthors: [Ada]\n---\nHi.\n",
        ),
      },
      {
        path: "site/pages/index.html",
        text: Some(
          "<section class=\"hero\">Hero</section><div data-site=\"latest-posts\"></div>",
        ),
      },
    ],
    main_build=true,
  )
  let paths = built.outputs.map(o => {
    match o {
      Text(path, _) => path
      Copy(path, _) => path
    }
  })
  assert_eq(paths, [
    "docs/architecture/index.html", "blog/hello/index.html", "index.html", "docs/index.html",
    "blog/index.html", "blog/atom.xml", "search-index.json", "docs/images/flow.png",
  ])
  guard built.outputs[2] is Text(_, home) else { fail("home is not text") }
  assert_true(home.contains("Hero"))
  assert_true(home.contains("href=\"/m/blog/hello/\""))
  guard built.outputs[4] is Text(_, blog) else { fail("blog is not text") }
  assert_true(blog.contains("content=\"Posts about T\""))
}

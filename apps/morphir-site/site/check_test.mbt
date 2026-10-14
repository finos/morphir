///|
test "check_site finds broken links, missing titles, bad feeds and forbidden files" {
  let problems = @site.check_site(
    "/m/",
    [
      "index.html", "docs/index.html", "assets/site.css", "docs/superpowers/x.html",
    ],
    [
      (
        "index.html", "<html><head><title>T</title></head><a href=\"/m/docs/\">d</a><a href=\"/m/nope/\">n</a><link href=\"/m/assets/site.css\"></html>",
      ),
      (
        "docs/index.html", "<html><head><title></title></head><a href=\"/m/#top\">t</a><a href=\"https://e.com\">e</a></html>",
      ),
    ],
    Some("<feed><entry></feed>"),
  )
  assert_eq(problems.map(p => p.render()), [
    "index.html: link `/m/nope/` does not resolve in the built site", "docs/index.html: page has no `<title>`",
    "blog/atom.xml: `</feed>` closes `<entry>`", "docs/superpowers/x.html: forbidden path in the built site",
  ])
}

///|
test "a well-formed feed passes" {
  assert_eq(
    @site.check_site(
      "/m/",
      [],
      [],
      Some(
        "<?xml version=\"1.0\"?>\n<feed><link href=\"x\"/><title>a &amp; b</title></feed>",
      ),
    ),
    [],
  )
}

///|
test "a missing feed is a problem" {
  assert_eq(@site.check_site("/m/", [], [], None).map(p => p.render()), [
    "blog/atom.xml: feed is missing",
  ])
}

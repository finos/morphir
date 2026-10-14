///|
test "markdown gets heading anchors and facts" {
  let doc = @content.render_markdown(
    "a.md", "# Hello *World*\n\nFirst para &amp; more.\n\n## Setup\n\n## Setup\n\n| a |\n|---|\n| 1 |\n",
  )
  assert_eq(doc.title, Some("Hello World"))
  assert_eq(doc.summary, "First para & more.")
  assert_eq(doc.headings.map(h => h.id), ["hello-world", "setup", "setup-2"])
  assert_true(doc.html.contains("<h2 id=\"setup-2\">Setup</h2>"))
  assert_true(doc.html.contains("<table>"))
  assert_eq(doc.ids, ["hello-world", "setup", "setup-2"])
}

///|
test "raw html is kept and code keeps its language" {
  let doc = @content.render_markdown(
    "a.md", "<div class=\"note\">n</div>\n\n```moonbit\nlet x = 1\n```\n",
  )
  assert_true(doc.html.contains("<div class=\"note\">n</div>"))
  assert_true(
    doc.html.contains(
      "<pre><code class=\"language-moonbit\">let x = 1\n</code></pre>",
    ),
  )
  assert_eq(doc.title, None)
}

///|
test "html fragments keep existing heading attributes and ids" {
  let doc = @content.analyse_html(
    "<h2 class=\"x\">Kept</h2><section id=\"hero\"><h1>Title</h1></section>",
  )
  assert_eq(doc.headings.map(h => h.id), ["title"])
  assert_eq(doc.ids, ["hero", "title"])
  assert_eq(doc.title, Some("Title"))
}

///|
test "duplicate heading ids are unique, even when a generated id is taken" {
  let doc = @content.render_markdown(
    "a.md", "## Setup\n\n## Setup\n\n## Setup 2\n",
  )
  assert_eq(doc.headings.map(h => h.id), ["setup", "setup-2", "setup-2-2"])
  assert_eq(doc.ids, ["setup", "setup-2", "setup-2-2"])
}

///|
test "generated heading ids avoid ids already in the html" {
  let doc = @content.analyse_html(
    "<section id=\"hero\"></section><h2>Hero</h2>",
  )
  assert_eq(doc.headings.map(h => h.id), ["hero-2"])
  assert_eq(doc.ids, ["hero", "hero-2"])
}

///|
test "heading text keeps inline markup tight" {
  let doc = @content.analyse_html(
    "<h3>WASI Target (<code>wasm</code>)</h3><h2>A <em>b</em>c</h2>",
  )
  assert_eq(doc.headings.map(h => (h.id, h.text)), [
    ("wasi-target-wasm", "WASI Target (wasm)"),
    ("a-bc", "A bc"),
  ])
}

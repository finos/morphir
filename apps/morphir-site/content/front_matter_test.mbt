///|
/// The problems that `action` raises. Fails when it raises nothing.
fn problems_of(action : () -> Unit raise) -> Array[@model.Problem] raise {
  try {
    action()
    fail("expected a build problem")
  } catch {
    @model.Invalid(problems) => problems
    other => raise other
  }
}

///|
test "markdown front matter with text and lists" {
  let fm = @content.parse_front_matter(
    "a.md", "---\ntitle: \"Hello\"\nauthors: [Ada, Zoë]\ndraft: true\n---\n# Body\n",
  )
  assert_eq(fm.text("title"), Some("Hello"))
  assert_eq(fm.list("authors"), ["Ada", "Zoë"])
  assert_true(fm.flag("draft"))
  assert_eq(fm.body, "# Body\n")
  assert_eq(fm.body_line, 6)
}

///|
test "dash list" {
  let fm = @content.parse_front_matter(
    "a.md", "---\nauthors:\n  - Ada\n  - Grace\n---\nx",
  )
  assert_eq(fm.list("authors"), ["Ada", "Grace"])
}

///|
test "html comment front matter" {
  let fm = @content.parse_front_matter(
    "a.html", "<!-- ---\ntitle: Landing\n--- -->\n<section>x</section>",
  )
  assert_eq(fm.text("title"), Some("Landing"))
  assert_eq(fm.body, "<section>x</section>")
}

///|
test "no front matter" {
  let fm = @content.parse_front_matter("a.md", "# Title\n")
  assert_eq(fm.fields.length(), 0)
  assert_eq(fm.body, "# Title\n")
}

///|
test "unknown key, duplicate key and unclosed block are errors" {
  assert_eq(
    problems_of(() => {
      ignore(@content.parse_front_matter("a.md", "---\ntags: x\n---\n"))
    }),
    [@model.problem("a.md", "unknown front matter key `tags`", line=2)],
  )
  assert_eq(
    problems_of(() => {
      ignore(
        @content.parse_front_matter("a.md", "---\ntitle: x\ntitle: y\n---\n"),
      )
    }),
    [@model.problem("a.md", "duplicate front matter key `title`", line=3)],
  )
  assert_eq(
    problems_of(() => {
      ignore(@content.parse_front_matter("a.md", "---\ntitle: x\n"))
    }),
    [@model.problem("a.md", "front matter is not closed with `---`", line=1)],
  )
}

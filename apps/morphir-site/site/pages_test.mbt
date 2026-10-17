///|
fn text(path : String, body : String) -> @site.SourceFile {
  { path, text: Some(body), }
}

///|
/// The shared test config without the package list.
let bare : @model.SiteConfig = { ..config, packages: [], }

///|
fn problems_of(action : () -> Unit raise) -> Array[String] raise {
  try {
    action()
    fail("expected build problems")
  } catch {
    @model.Invalid(problems) => problems.map(p => p.render())
    other => raise other
  }
}

///|
test "prepare builds pages with routes, titles and rewritten links" {
  let prepared = @site.prepare(
    config,
    [
      text(
        "docs/ARCHITECTURE.md", "# Architecture\n\nSee [ADRs](adr/README.md#records).\n",
      ),
      text(
        "docs/adr/README.md", "---\norder: 2\n---\n# Decision records\n\n## Records\n",
      ),
      text(
        "site/blog/2026-10-13-hello.md", "---\ntitle: Hello\ndate: 2026-10-13\nauthors: [Zoë]\n---\nFirst post.\n",
      ),
      text(
        "site/pages/index.html", "<section><a href=\"/docs/\">Docs</a></section>",
      ),
      text(
        "pkgs/morphir-ir/README.md", "# morphir-ir\n\nSee [moon.mod](moon.mod).\n",
      ),
      { path: "pkgs/morphir-ir/moon.mod", text: None, },
    ],
    main_build=true,
  )
  let routes = prepared.pages.map(p => p.route)
  assert_eq(routes, [
    "/docs/architecture/", "/docs/adr/", "/blog/hello/", "/", "/docs/packages/morphir-ir/",
  ])
  let arch = prepared.pages[0]
  assert_eq(arch.title, "Architecture")
  assert_true(arch.html.contains("href=\"/m/docs/adr/#records\""))
  assert_eq(prepared.pages[1].order, 2)
  let post = prepared.pages[2]
  assert_eq(post.date, "2026-10-13")
  assert_eq(post.authors, ["Zoë"])
  assert_eq(post.summary, "First post.")
  assert_true(prepared.pages[3].html.contains("href=\"/m/docs/\""))
  assert_true(
    prepared.pages[4].html.contains(
      "https://github.com/finos/morphir-moonbit/blob/main/pkgs/morphir-ir/moon.mod",
    ),
  )
}

///|
test "prepare reports every problem together" {
  let problems = problems_of(() => {
    ignore(
      @site.prepare(
        bare,
        [
          text("docs/a.md", "# A\n\n[x](b.md#nope) [y](missing.md)\n"),
          text("docs/b.md", "# B\n"),
          text("docs/B.md", "# B again\n"),
          text("docs/superpowers/plans/p.md", "# Plan\n"),
          text("docs/draft.md", "---\ndraft: true\n---\n# D\n"),
          text(
            "site/blog/2026-10-13-x.md", "---\ntitle: X\ndate: 2026-10-14\n---\nx\n",
          ),
          text(
            "site/blog/hello.md", "---\ntitle: H\ndate: 2026-10-13\nauthors: [A]\n---\nh\n",
          ),
        ],
        main_build=true,
      ),
    )
  })
  assert_eq(problems, [
    "docs/superpowers/plans/p.md: forbidden path: agent specs, plans and ledgers live in beads",
    "docs/draft.md: draft page in a main build", "site/blog/2026-10-13-x.md: blog post needs `authors`",
    "site/blog/2026-10-13-x.md: `date` 2026-10-14 does not match the file name date 2026-10-13",
    "site/blog/hello.md: blog file name must be `YYYY-MM-DD-slug.md` or `.html`, with a real date and a slug of a-z, 0-9 and single `-`",
    "docs/B.md: route `/docs/b/` is also written by `docs/b.md`", "docs/a.md: broken link `missing.md`: `docs/missing.md` does not exist",
    "docs/a.md: anchor `#nope` does not exist on `/docs/b/`",
  ])
}

///|
test "drafts are skipped with a warning outside main builds" {
  let prepared = @site.prepare(
    bare,
    [text("docs/draft.md", "---\ndraft: true\n---\n# D\n")],
    main_build=false,
  )
  assert_eq(prepared.pages.length(), 0)
  assert_eq(prepared.warnings.map(w => w.render()), [
    "docs/draft.md: draft page skipped",
  ])
}

///|
test "full html pages keep their markup and get site links" {
  let page = "<!doctype html><html><body><a href=\"b.md#b\">b</a> <a href='/docs/'>d</a></body></html>"
  let prepared = @site.prepare(
    bare,
    [text("docs/demo.html", page), text("docs/b.md", "# B\n")],
    main_build=true,
  )
  assert_true(prepared.pages[0].full)
  assert_eq(
    prepared.pages[0].html,
    "<!doctype html><html><body><a href=\"/m/docs/b/#b\">b</a> <a href='/m/docs/'>d</a></body></html>",
  )
}

///|
test "full html pages report broken links" {
  let problems = problems_of(() => {
    ignore(
      @site.prepare(
        bare,
        [
          text(
            "docs/demo.html", "<html><body><a href=\"x.md\">x</a></body></html>",
          ),
        ],
        main_build=true,
      ),
    )
  })
  assert_eq(problems, [
    "docs/demo.html: broken link `x.md`: `docs/x.md` does not exist",
  ])
}

///|
test "a bad blog file name still reports the missing fields" {
  let problems = problems_of(() => {
    ignore(
      @site.prepare(
        bare,
        [text("site/blog/hello.md", "---\ndate: 2026-10-13\n---\nh\n")],
        main_build=true,
      ),
    )
  })
  assert_eq(problems, [
    "site/blog/hello.md: blog file name must be `YYYY-MM-DD-slug.md` or `.html`, with a real date and a slug of a-z, 0-9 and single `-`",
    "site/blog/hello.md: blog post needs `title`", "site/blog/hello.md: blog post needs `authors`",
  ])
}

///|
test "a package without a README is a problem" {
  let problems = problems_of(() => {
    ignore(@site.prepare(config, [text("docs/a.md", "# A\n")], main_build=true))
  })
  assert_eq(problems, [
    "site/site.json: package `morphir-ir` in site/site.json has no README.md or README.mbt.md in pkgs/morphir-ir/ or apps/morphir-ir/",
  ])
}

///|
test "nav groups that miss a page fail the build" {
  let grouped = {
    ..bare,
    nav: Some([{ group: "Start", items: ["QUICK_START.md", "GONE.md"], }]),
  }
  let sources = [
    text("docs/QUICK_START.md", "# Quick start\n"),
    text("docs/adr/README.md", "# Decision records\n"),
  ]
  assert_eq(
    problems_of(() => ignore(@site.prepare(grouped, sources, main_build=true))),
    [
      "site/site.json: `nav` entry `GONE.md` matches no page", "site/site.json: docs directory `adr/` is not in `nav`",
    ],
  )
  let fixed = {
    ..bare,
    nav: Some([{ group: "Start", items: ["QUICK_START.md", "*/"], }]),
  }
  ignore(@site.prepare(fixed, sources, main_build=true))
}

///|
test "a package's sub-package READMEs become pages below it, and link to each other" {
  let prepared = @site.prepare(
    config,
    [
      text(
        "pkgs/morphir-ir/README.mbt.md", "# morphir-ir\n\nSee [JSON](json/README.mbt.md).\n",
      ),
      text(
        "pkgs/morphir-ir/json/README.mbt.md", "# JSON\n\nBack to [the package](../README.mbt.md).\n",
      ),
    ],
    main_build=true,
  )
  @expect.expect_all(s => {
    s
    .expect(prepared.pages.map(p => p.route), label="routes")
    .to_contain_exactly([
      "/docs/packages/morphir-ir/", "/docs/packages/morphir-ir/json/",
    ])
    s
    .expect(prepared.pages[0].html, label="link down")
    .to_contain("href=\"/m/docs/packages/morphir-ir/json/\"")
    s
    .expect(prepared.pages[1].html, label="link up")
    .to_contain("href=\"/m/docs/packages/morphir-ir/\"")
  })
}

///|
test "chapters in site.json order a package's sub-package pages, without front matter" {
  let ordered = {
    ..config,
    chapters: [{ name: "morphir-ir", chapters: ["zeta", "alpha"], }],
  }
  let prepared = @site.prepare(
    ordered,
    [
      text("pkgs/morphir-ir/README.mbt.md", "# morphir-ir\n"),
      text("pkgs/morphir-ir/alpha/README.mbt.md", "# Alpha\n"),
      text("pkgs/morphir-ir/beta/README.mbt.md", "# Beta\n"),
      text("pkgs/morphir-ir/zeta/README.mbt.md", "# Zeta\n"),
    ],
    main_build=true,
  )
  assert_eq(prepared.pages.map(p => (p.title, p.order)), [
    ("morphir-ir", 1000),
    ("Alpha", 2),
    ("Beta", 1000),
    ("Zeta", 1),
  ])
  let nav = @site.build_nav(
    prepared.pages.map(p => {
      route: p.route,
      source: p.source,
      title: p.title,
      order: p.order,
    }),
  )
  assert_eq(nav.map(item => (item.title, item.depth)), [
    ("Packages", 0),
    ("morphir-ir", 1),
    ("Zeta", 2),
    ("Alpha", 2),
    ("Beta", 2),
  ])
}

///|
test "a chapter in site.json without a page is a problem" {
  let ordered = {
    ..config,
    chapters: [{ name: "morphir-ir", chapters: ["json", "gone"], }],
  }
  let problems = problems_of(() => {
    ignore(
      @site.prepare(
        ordered,
        [
          text("pkgs/morphir-ir/README.mbt.md", "# morphir-ir\n"),
          text("pkgs/morphir-ir/json/README.mbt.md", "# JSON\n"),
        ],
        main_build=true,
      ),
    )
  })
  assert_eq(problems, [
    "site/site.json: chapter `gone` of package `morphir-ir` in site/site.json has no README.md or README.mbt.md",
  ])
}

///|
test "README.md and README.mbt.md in one directory is refused" {
  let problems = problems_of(() => {
    ignore(
      @site.prepare(
        config,
        [
          text("pkgs/morphir-ir/README.md", "# A\n"),
          text("pkgs/morphir-ir/README.mbt.md", "# B\n"),
        ],
        main_build=true,
      ),
    )
  })
  @expect.expect(problems).to_any_satisfy(p => {
    p.contains("pkgs/morphir-ir has both README.md and README.mbt.md")
  })
}

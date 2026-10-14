///|
let config : @model.SiteConfig = {
  title: "T",
  description: "D",
  base_path: "/m/",
  site_url: "https://x.io/m/",
  repo_url: "https://github.com/finos/morphir-moonbit",
  packages: ["morphir-ir"],
}

///|
fn ctx() -> @site.LinkContext {
  @site.LinkContext::new(
    config,
    {
      "docs/ARCHITECTURE.md": "/docs/architecture/",
      "docs/adr/README.md": "/docs/adr/",
      "pkgs/morphir-ir/README.md": "/docs/packages/morphir-ir/",
    },
    [
      "docs/ARCHITECTURE.md", "docs/adr/README.md", "docs/images/flow.png", "site/blog/2026-10-13-hello.png",
      "pkgs/morphir-ir/diagram.PNG", "pkgs/morphir-ir/README.md", "pkgs/morphir-ir/moon.mod",
      "AGENTS.md",
    ],
    ["/", "/docs/", "/docs/architecture/", "/docs/adr/", "/blog/"],
  )
}

///|
test "classify sources" {
  assert_eq(@site.classify("docs/adr/x.md", config), Doc("adr/x.md"))
  assert_eq(@site.classify("docs/x.mbt.md", config), Other)
  assert_eq(@site.classify("docs/superpowers/plans/p.md", config), Forbidden)
  assert_eq(@site.classify("docs/superpowers/x.png", config), Forbidden)
  assert_eq(
    @site.classify("site/blog/2026-10-13-a.md", config),
    Post("2026-10-13-a.md"),
  )
  assert_eq(@site.classify("site/pages/index.html", config), Landing)
  assert_eq(
    @site.classify("pkgs/morphir-ir/README.md", config),
    Package("morphir-ir"),
  )
  assert_eq(@site.classify("pkgs/morphir-elm/README.md", config), Other)
  assert_true(@site.needs_text("docs/a.md", config))
  assert_false(@site.needs_text("docs/a.png", config))
}

///|
test "normalize" {
  assert_eq(
    @site.normalize("docs/./adr/../ARCHITECTURE.md"),
    "docs/ARCHITECTURE.md",
  )
  assert_eq(@site.normalize("docs/adr/"), "docs/adr")
  assert_eq(@site.normalize("../x"), "../x")
}

///|
test "published targets become routes and keep anchors" {
  let r = @site.resolve(
    ctx(),
    "docs/QUICK_START.md",
    "../docs/ARCHITECTURE.md#layers",
  )
  assert_eq(r.url, "/m/docs/architecture/#layers")
  assert_eq(r.anchor, Some(("/docs/architecture/", "layers")))
  assert_eq(r.problem, None)
  let readme = @site.resolve(ctx(), "docs/ARCHITECTURE.md", "./adr/README.md")
  assert_eq(readme.url, "/m/docs/adr/")
}

///|
test "other repository files and directories go to GitHub" {
  assert_eq(
    @site.resolve(ctx(), "docs/MISE_TASKS.md", "../AGENTS.md").url,
    "https://github.com/finos/morphir-moonbit/blob/main/AGENTS.md",
  )
  assert_eq(
    @site.resolve(ctx(), "docs/ARCHITECTURE.md", "../pkgs/morphir-ir/").url,
    "https://github.com/finos/morphir-moonbit/tree/main/pkgs/morphir-ir",
  )
}

///|
test "docs assets are copied" {
  let r = @site.resolve(ctx(), "docs/ARCHITECTURE.md", "images/flow.png")
  assert_eq(r.url, "/m/docs/images/flow.png")
  assert_eq(r.copy, Some("docs/images/flow.png"))
}

///|
test "site routes, same-page anchors and external links" {
  assert_eq(
    @site.resolve(ctx(), "site/pages/index.html", "/docs/").url,
    "/m/docs/",
  )
  assert_eq(
    @site.resolve(ctx(), "site/pages/index.html", "/try/").url,
    "/m/try/",
  )
  let same = @site.resolve(ctx(), "docs/ARCHITECTURE.md", "#layers")
  assert_eq(same.url, "#layers")
  assert_eq(same.anchor, Some(("/docs/architecture/", "layers")))
  assert_eq(
    @site.resolve(ctx(), "docs/a.md", "https://e.com/x").url,
    "https://e.com/x",
  )
  assert_eq(
    @site.resolve(ctx(), "docs/a.md", "mailto:a@b.c").url,
    "mailto:a@b.c",
  )
}

///|
test "broken links are problems" {
  assert_eq(
    @site.resolve(ctx(), "docs/a.md", "missing.md").problem,
    Some("broken link `missing.md`: `docs/missing.md` does not exist"),
  )
  assert_eq(
    @site.resolve(ctx(), "docs/a.md", "../../outside.md").problem,
    Some("link `../../outside.md` leaves the repository"),
  )
  assert_eq(
    @site.resolve(ctx(), "site/pages/index.html", "/nowhere/").problem,
    Some("no page at site route `/nowhere/`"),
  )
}

///|
test "images outside docs are copied to their own path" {
  let post = @site.resolve(
    ctx(),
    "site/blog/2026-10-13-hello.md",
    "2026-10-13-hello.png",
  )
  assert_eq(post.url, "/m/site/blog/2026-10-13-hello.png")
  assert_eq(post.copy, Some("site/blog/2026-10-13-hello.png"))
  let readme_image = @site.resolve(
    ctx(),
    "pkgs/morphir-ir/README.md",
    "./diagram.PNG",
  )
  assert_eq(readme_image.url, "/m/pkgs/morphir-ir/diagram.PNG")
  assert_eq(readme_image.copy, Some("pkgs/morphir-ir/diagram.PNG"))
  // Other files outside docs stay GitHub links without a copy.
  let other = @site.resolve(ctx(), "pkgs/morphir-ir/README.md", "moon.mod")
  assert_eq(other.copy, None)
}

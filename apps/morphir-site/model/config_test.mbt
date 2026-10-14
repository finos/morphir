///|
let config_json : String =
  #|{
  #|  "title": "Morphir MoonBit",
  #|  "description": "Morphir in MoonBit",
  #|  "base_path": "/morphir-moonbit/",
  #|  "site_url": "https://finos.github.io/morphir-moonbit/",
  #|  "repo_url": "https://github.com/finos/morphir-moonbit",
  #|  "packages": ["morphir-ir"]
  #|}

///|
test "parse config and build links" {
  let config = @model.SiteConfig::parse("site/site.json", config_json)
  assert_eq(config.title, "Morphir MoonBit")
  assert_eq(config.packages, ["morphir-ir"])
  assert_eq(config.href("/docs/"), "/morphir-moonbit/docs/")
  assert_eq(config.href("/"), "/morphir-moonbit/")
  assert_eq(
    config.absolute("/blog/x/"),
    "https://finos.github.io/morphir-moonbit/blog/x/",
  )
}

///|
test "config problems name the missing fields" {
  let problems = try {
    ignore(@model.SiteConfig::parse("site/site.json", "{\"title\": \"x\"}"))
    []
  } catch {
    @model.Invalid(problems) => problems
  }
  assert_eq(problems.map(p => p.message), [
    "missing string field `description`", "missing string field `base_path`", "missing string field `site_url`",
    "missing string field `repo_url`",
  ])
}

///|
test "base path must start and end with a slash" {
  let text = config_json.replace(old="\"/morphir-moonbit/\"", new="\"morphir\"")
  let failed = try {
    ignore(@model.SiteConfig::parse("site/site.json", text))
    false
  } catch {
    @model.Invalid(_) => true
  }
  assert_true(failed)
}

///|
fn with_nav(nav : String) -> String {
  config_json[:config_json.length() - 2].to_owned() + ",\n  \"nav\": \{nav}\n}"
}

///|
fn nav_problems(nav : String) -> Array[String] {
  try {
    ignore(@model.SiteConfig::parse("site/site.json", with_nav(nav)))
    []
  } catch {
    @model.Invalid(problems) => problems.map(p => p.message)
  }
}

///|
test "nav is optional" {
  let config = @model.SiteConfig::parse("site/site.json", config_json)
  assert_eq(config.nav, None)
}

///|
test "nav groups keep their order and items" {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    with_nav(
      "[{\"group\": \"Start\", \"items\": [\"QUICK_START.md\", \"adr/\"]}, {\"group\": \"More\", \"items\": [\"*.md\", \"*/\"]}]",
    ),
  )
  assert_eq(
    config.nav,
    Some([
      { group: "Start", items: ["QUICK_START.md", "adr/"], },
      { group: "More", items: ["*.md", "*/"], },
    ]),
  )
}

///|
test "nav problems are reported together" {
  assert_eq(nav_problems("{}"), ["`nav` must be an array of groups"])
  assert_eq(
    nav_problems(
      "[{\"group\": \"\", \"items\": [\"A.md\"]}, {\"group\": \"B\", \"items\": []}, {\"group\": \"C\", \"items\": [1, \"adr/0001.md\", \"notes.txt\", \"A.md\", \"x/y/\"]}, \"D\"]",
    ),
    [
      "`nav` group 1 needs a non-empty `group` label", "`nav` group `B` has no items",
      "`nav` group `C`: every item must be a string", "`nav` item `adr/0001.md` must be a top-level page (`NAME.md` or `NAME.html`) or directory (`NAME/`)",
      "`nav` item `notes.txt` must be a top-level page (`NAME.md` or `NAME.html`) or directory (`NAME/`)",
      "`nav` item `A.md` is listed more than once", "`nav` item `x/y/` must be a top-level page (`NAME.md` or `NAME.html`) or directory (`NAME/`)",
      "`nav` group 4 must be an object with `group` and `items`",
    ],
  )
}

///|
test "nav items can name HTML pages" {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    with_nav(
      "[{\"group\": \"Pages\", \"items\": [\"GUIDE.html\", \"*.html\"]}]",
    ),
  )
  assert_eq(
    config.nav,
    Some([{ group: "Pages", items: ["GUIDE.html", "*.html"], }]),
  )
}

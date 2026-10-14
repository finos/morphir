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

///|
/// Order by code unit: the pinned `String::compare` orders by length first.
fn compare_units(a : String, b : String) -> Int32 {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
async fn list_files(root : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let dir = if prefix == "" { root } else { "\{root}/\{prefix}" }
  let names = @fs.readdir(dir)
  names.sort_by(compare_units)
  for name in names {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{root}/\{rel}") {
      Directory => out.append(list_files(root, prefix=rel))
      Regular => out.push(rel)
      _ => ()
    }
  }
  out
}

///|
fn option(args : Array[String], name : String, default : String) -> String {
  for i in 0..<(args.length() - 1) {
    if args[i] == name {
      return args[i + 1]
    }
  }
  default
}

///|
async fn main {
  let args = @env.args()
  let dir = option(args, "--dir", "../../_site")
  let config_path = option(args, "--config", "../../site/site.json")
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file(config_path).text(),
  ) catch {
    @model.Invalid(found) => {
      for p in found {
        println("error: \{p.render()}")
      }
      @sys.exit(1)
      abort("unreachable")
    }
    error => {
      println("error: \{error}")
      @sys.exit(1)
      abort("unreachable")
    }
  }
  // `--base` overrides the base path from `site/site.json`.
  let base = option(args, "--base", config.base_path)
  let all = list_files(dir)
  // The workbench at try/ is checked by its own tests and the browser smoke test.
  let files = all.filter(f => !f.has_prefix("try/"))
  let html = []
  for f in files {
    if f.has_suffix(".html") {
      html.push((f, @fs.read_file("\{dir}/\{f}").text()))
    }
  }
  let feed = if files.contains("blog/atom.xml") {
    Some(@fs.read_file("\{dir}/blog/atom.xml").text())
  } else {
    None
  }
  let problems = @site.check_site(base, all, html, feed)
  for p in problems {
    println("error: \{p.render()}")
  }
  if problems.length() > 0 {
    @sys.exit(1)
  }
  println("check:site: \{html.length()} pages OK")
}

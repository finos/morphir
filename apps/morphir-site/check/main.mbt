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
/// Encode every token identically so only exact option names have CLI meaning.
/// In particular, raw `--`, equals forms and help remain literal data.
fn encoded_argument(token : String) -> String {
  "--token-" + @hex.encode(@utf8.encode(token))
}

///|
fn ignored_arguments() -> @argparse.PositionArg {
  @argparse.PositionArg(
    "ignored",
    num_args=@argparse.ValueRange(lower=0),
    allow_hyphen_values=true,
  )
}

///|
/// Each old option lookup was independent: another option can be both a value
/// here and a recognized name in its own parser. Append retains the first value.
fn first_option(argv : Array[String], name : String) -> String? raise {
  let command = @argparse.Command(
    "morphir-site check",
    disable_help_flag=true,
    disable_help_subcommand=true,
    options=[
      @argparse.OptionArg(
        "value",
        long=encoded_argument(name)[2:],
        action=Append,
        allow_hyphen_values=true,
      ),
    ],
    positionals=[ignored_arguments()],
  )
  // No original token encodes to this sentinel. Appending it gives a terminal
  // option a value without scanning argv or losing an earlier duplicate value.
  let normalized = [..argv.map(encoded_argument), "missing-value"]
  let parsed = command.parse(argv=normalized)
  match parsed.values.get("value") {
    Some([value, ..]) if value != "missing-value" =>
      Some(@utf8.decode(@hex.decode(value[8:])))
    _ => None
  }
}

///|
fn check_options(argv : Array[String]) -> (String, String, String?) raise {
  (
    first_option(argv, "--dir").unwrap_or("../../_site"),
    first_option(argv, "--config").unwrap_or("../../site/site.json"),
    first_option(argv, "--base"),
  )
}

///|
async fn main {
  let (dir, config_path, base_override) = check_options(@env.args()) catch {
    error => {
      println("error: \{error}")
      @sys.exit(1)
      return
    }
  }
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
  let base = base_override.unwrap_or(config.base_path)
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

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
  let argv = @env.args()
  match argv[1:] {
    ["--json", ..] => {
      json_main(argv[1:])
      return
    }
    ["--forward-argv", "--", .. raw] => {
      // Validate the bounded owned prefix; the raw segment stays untouched.
      let prefix = @argparse.Command(
        "morphir-site check",
        disable_help_flag=true,
        disable_help_subcommand=true,
        flags=[@argparse.FlagArg("forward-argv", required=true)],
      )
      ignore(prefix.parse(argv=argv[1:2], env=Map([]))) catch {
        e => {
          println("error: \{e}")
          @sys.exit(1)
          return
        }
      }
      legacy_main(raw.to_owned())
      return
    }
    _ => legacy_main(argv)
  }
}

///|
async fn legacy_main(argv : Array[String]) -> Unit {
  let (dir, config_path, base_override) = check_options(argv) catch {
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

///|
enum SitePresentation {
  Help
  Run(Array[String])
}

///|
fn json_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-site check",
    about="Use --json -- LEGACY_ARGS for machine output. The legacy segment retains exact option lookup, first duplicates, missing values and ignored tokens. Use --forward-argv -- RAW for an entirely literal legacy invocation.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json", required=true),
      @argparse.FlagArg("help", short='h'),
    ],
  )
}

///|
/// The reserved delimiter is unwrapped once. The library never consumes the raw tail.
fn json_presentation(argv : ArrayView[String]) -> SitePresentation raise {
  match argv {
    ["--json", "--", .. raw] => {
      ignore(json_command().parse(argv=argv[:1], env=Map([])))
      Run(raw.to_owned())
    }
    _ => {
      let parsed = json_command().parse(argv~, env=Map([]))
      if parsed.flags.get("help").unwrap_or(false) {
        Help
      } else {
        Run([])
      }
    }
  }
}

///|
fn success(result : Json, diagnostics~ : Array[Json] = []) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.check",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": diagnostics,
  }
}

///|
fn failure(
  code : String,
  message : String,
  diagnostics~ : Array[Json] = [],
) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir.site.check",
    "state": "failed",
    "exitCode": 1,
    "error": { "code": code, "message": message },
    "diagnostics": diagnostics,
  }
}

///|
async fn json_write(text : String) -> Unit {
  @stdio.stdout.write(text + "\n")
}

///|
async fn json_main(argv : ArrayView[String]) -> Unit {
  let presentation = json_presentation(argv) catch {
    e => {
      json_write(failure("syntax", e.to_string()).stringify())
      @sys.exit(1)
      return
    }
  }
  match presentation {
    Help =>
      json_write(success({ "help": json_command().render_help() }).stringify())
    Run(raw) =>
      try {
        let (dir, config_path, base_override) = check_options(raw)
        let config = @model.SiteConfig::parse(
          "site/site.json",
          @fs.read_file(config_path).text(),
        )
        let base = base_override.unwrap_or(config.base_path)
        let all = list_files(dir)
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
        if !problems.is_empty() {
          let diagnostics : Array[Json] = problems.map(p => {
            "severity": "error",
            "message": p.render(),
          })
          json_write(
            failure(
              "site.invalid",
              "site: \{problems.length()} problem(s)",
              diagnostics~,
            ).stringify(),
          )
          @sys.exit(1)
          return
        }
        json_write(
          success({
            "directory": dir,
            "configPath": config_path,
            "basePath": base,
            "pageCount": html.length(),
            "fileCount": all.length(),
            "passed": true,
          }).stringify(),
        )
      } catch {
        @model.Invalid(problems) => {
          let diagnostics : Array[Json] = problems.map(p => {
            "severity": "error",
            "message": p.render(),
          })
          json_write(
            failure(
              "site.invalid",
              "site: \{problems.length()} problem(s)",
              diagnostics~,
            ).stringify(),
          )
          @sys.exit(1)
        }
        e => {
          json_write(failure("site.check_failed", e.to_string()).stringify())
          @sys.exit(1)
        }
      }
  }
}

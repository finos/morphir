///|
enum DocCommand {
  Generate
  Check
} derive(Eq)

///|
fn docs_command() -> @argparse.Command {
  @argparse.Command(
    "schemedocs",
    about="Generate and check Scheme documentation examples",
    disable_help_flag=true,
    disable_help_subcommand=true,
    subcommand_required=true,
    subcommands=[
      @argparse.Command("generate", disable_help_flag=true),
      @argparse.Command("check", disable_help_flag=true),
    ],
  )
}

///|
/// Keep the command boundary fixed and every following token literal. The
/// synthetic delimiter belongs to the adapter; user-supplied delimiters are data.
fn parse_docs_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let normalized = match argv {
    [command, .. data] => [command, "--", ..data]
    [] => []
  }
  docs_command().parse(argv=normalized, env=Map([]))
}

///|
fn docs_invocation(matches : @argparse.Matches) -> DocCommand {
  match matches.subcommand {
    Some(("generate", _)) => Generate
    Some(("check", _)) => Check
    _ => abort("schemedocs command selection invariant")
  }
}

///|
/// The entries of a directory on disk, each with whether it is a directory.
fn list_dir(dir : String) -> Array[(String, Bool)] raise {
  let entries = []
  for name in @fs.read_dir(dir) {
    entries.push((name, @fs.is_dir(dir + "/" + name)))
  }
  entries
}

///|
/// The plan for every chapter under `pkgs/morphir-scheme`.
fn current_plan() -> Plan raise {
  let files = find_files(scheme_root, list_dir) catch {
    e => raise DocError("\{scheme_root}: cannot list the chapters: \{e}")
  }
  plan(files, path => @fs.read_file_to_string(path))
}

///|
fn main {
  // This native filesystem tool owns the program-path prefix, as before.
  let matches = parse_docs_arguments(@env.args()[1:]) catch {
    _ => {
      println("usage: schemedocs generate | check")
      @sys.exit(2)
      return
    }
  }
  try {
    match docs_invocation(matches) {
      Generate => {
        let p = current_plan()
        for output in p.outputs {
          @fs.write_string_to_file(output.1, output.2)
          println("wrote \{output.1}")
        }
        for path in p.stale {
          @fs.remove_file(path)
          println("removed \{path}, which no chapter generates")
        }
      }
      Check => {
        let p = current_plan()
        let problems = []
        for output in p.outputs {
          let current = @fs.read_file_to_string(output.1) catch { _ => "" }
          if check_message(output.0, output.1, output.2, current) is Some(d) {
            problems.push(d)
          }
        }
        for path in p.stale {
          problems.push(stale_message(path))
        }
        if problems.is_empty() {
          println("scheme docs examples are current")
        } else {
          for p in problems {
            println(p)
          }
          println("schemedocs: run `mise run scheme-docs:generate`")
          @sys.exit(1)
        }
      }
    }
  } catch {
    DocError(message) => {
      println("schemedocs: \{message}")
      @sys.exit(1)
    }
    e => {
      println("schemedocs: \{e}")
      @sys.exit(1)
    }
  }
}

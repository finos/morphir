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
  let args = @env.args()
  // The first entry is the program path; the command follows it.
  let rest = args[1:].to_owned()
  try {
    match rest {
      ["generate"] => {
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
      ["check"] => {
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
      _ => {
        println("usage: schemedocs generate | check")
        @sys.exit(2)
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

///|
/// The directory searched for chapters, relative to the repository root.
let scheme_root : String = "pkgs/morphir-scheme"

///|
/// Directories that hold no chapter: build output, dependencies and test fixtures.
let skipped_dirs : Array[String] = [
  "_build", ".mooncakes", "node_modules", "target", "fixtures",
]

///|
let chapter_file : String = "README.mbt.md"

///|
let examples_file : String = "docs_examples_test.mbt"

///|
let procedures_file : String = "docs_procedures_generated_wbtest.mbt"

///|
/// The test file of a chapter's package that defines `run_example`, which the generated tests call.
let harness_file : String = "docs_run_test.mbt"

///|
/// Orders text by code unit, so the order does not depend on the platform.
fn compare_text(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// Every file under `root`, outside the skipped directories, in code-unit order of its path.
/// `list` gives the entries of a directory, each with whether it is a directory.
fn find_files(
  root : String,
  list : (String) -> Array[(String, Bool)] raise,
) -> Array[String] raise {
  let files = []
  let pending = [root]
  while pending.pop() is Some(dir) {
    for entry in list(dir) {
      let (name, is_dir) = entry
      let path = dir + "/" + name
      if !is_dir {
        files.push(path)
      } else if !skipped_dirs.contains(name) {
        pending.push(path)
      }
    }
  }
  files.sort_by(compare_text)
  files
}

///|
/// The last part of a path.
fn base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
/// What `generate` writes and removes.
struct Plan {
  /// Each generated file: (chapter path, generated file path, text).
  outputs : Array[(String, String, String)]
  /// Generated files that no chapter writes any more.
  stale : Array[String]
}

///|
/// The plan for `files`, the paths `find_files` returns. Every `README.mbt.md` among them is a chapter, and its
/// package must have a `docs_run_test.mbt`. `read` gives a chapter's text.
fn plan(
  files : Array[String],
  read : (String) -> String raise,
) -> Plan raise DocError {
  let outputs = []
  for path in files {
    if base_name(path) != chapter_file {
      continue
    }
    let dir = path[:path.length() - chapter_file.length() - 1].to_owned()
    if !files.contains(dir + "/" + harness_file) {
      raise DocError(
        "\{path}: the package has no \{harness_file}, which must define run_example for the chapter's examples",
      )
    }
    let text = read(path) catch {
      _ => raise DocError("\{path}: cannot read the chapter")
    }
    let chapter = parse_chapter(text) catch {
      DocError(message) => raise DocError("\{path}: \{message}")
    }
    outputs.push(
      (path, dir + "/" + examples_file, render_examples(path, chapter)),
    )
    if render_procedures(path, chapter) is Some(text) {
      outputs.push((path, dir + "/" + procedures_file, text))
    }
  }
  let stale = []
  for path in files {
    let name = base_name(path)
    if (name == examples_file || name == procedures_file) &&
      !outputs.iter().any(o => o.1 == path) {
      stale.push(path)
    }
  }
  { outputs, stale, }
}

///|
/// The message `check` prints for a generated file that no chapter writes.
fn stale_message(path : String) -> String {
  "\{path}: no chapter generates this file; `generate` removes it"
}

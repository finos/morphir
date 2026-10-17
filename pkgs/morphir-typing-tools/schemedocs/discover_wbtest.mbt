///|
/// A file tree in memory: each directory path maps to its entries, each with whether it is a directory.
fn tree_lister(
  tree : Map[String, Array[(String, Bool)]],
) -> (String) -> Array[(String, Bool)] raise {
  fn(dir) raise {
    match tree.get(dir) {
      Some(entries) => entries
      None => fail("no directory \{dir}")
    }
  }
}

///|
test "files are found in a stable order, skipping build output, dependencies and fixtures" {
  let tree : Map[String, Array[(String, Bool)]] = {
    "root": [
      ("spec", true),
      ("README.mbt.md", false),
      ("_build", true),
      ("backend", true),
      (".mooncakes", true),
      ("node_modules", true),
      ("target", true),
      ("fixtures", true),
      ("docs_run_test.mbt", false),
    ],
    "root/spec": [("README.mbt.md", false), ("docs_run_test.mbt", false)],
    "root/backend": [("modules", true), ("README.mbt.md", false)],
    "root/backend/modules": [("README.mbt.md", false)],
  }
  assert_eq(find_files("root", tree_lister(tree)), [
    "root/README.mbt.md", "root/backend/README.mbt.md", "root/backend/modules/README.mbt.md",
    "root/docs_run_test.mbt", "root/spec/README.mbt.md", "root/spec/docs_run_test.mbt",
  ])
}

///|
test "text compares by code unit, so shorter prefixes and capitals come first" {
  let names = ["b/x", "README.mbt.md", "a", "ab", "B"]
  names.sort_by(compare_text)
  assert_eq(names, ["B", "README.mbt.md", "a", "ab", "b/x"])
}

///|
/// Chapter sources by path, read the way `plan` reads them.
fn reader(texts : Map[String, String]) -> (String) -> String raise {
  fn(path) raise {
    match texts.get(path) {
      Some(text) => text
      None => fail("no file \{path}")
    }
  }
}

///|
test "every chapter found is generated, with the procedures file only where it has a procedure table" {
  let files = [
    "r/README.mbt.md", "r/docs_run_test.mbt", "r/x/README.mbt.md", "r/x/docs_run_test.mbt",
  ]
  let texts = {
    "r/README.mbt.md": "## Built-in procedures\n| `car` | first |\n",
    "r/x/README.mbt.md": "```scheme\n1\n;; => 1\n```\n",
  }
  let p = plan(files, reader(texts))
  assert_eq(p.outputs.map(o => (o.0, o.1)), [
    ("r/README.mbt.md", "r/docs_examples_test.mbt"),
    ("r/README.mbt.md", "r/docs_procedures_generated_wbtest.mbt"),
    ("r/x/README.mbt.md", "r/x/docs_examples_test.mbt"),
  ])
  assert_eq(
    p.outputs[2].2,
    render_examples(
      "r/x/README.mbt.md",
      parse_chapter(texts["r/x/README.mbt.md"]),
    ),
  )
  assert_eq(p.stale, [])
}

///|
test "a chapter whose package has no docs_run_test.mbt is refused" {
  let files = [
    "r/README.mbt.md", "r/docs_run_test.mbt", "r/modules/README.mbt.md",
  ]
  let texts = { "r/README.mbt.md": "", "r/modules/README.mbt.md": "" }
  let got = try {
    ignore(plan(files, reader(texts)))
    ""
  } catch {
    DocError(m) => m
  }
  assert_eq(
    got, "r/modules/README.mbt.md: the package has no docs_run_test.mbt, which must define run_example for the chapter's examples",
  )
}

///|
test "generated files that no chapter writes are stale" {
  let files = [
    "r/README.mbt.md", "r/docs_examples_test.mbt", "r/docs_procedures_generated_wbtest.mbt",
    "r/docs_run_test.mbt", "r/gone/docs_examples_test.mbt", "r/gone/docs_run_test.mbt",
    "r/other_test.mbt",
  ]
  let p = plan(files, reader({ "r/README.mbt.md": "```scheme\n1\n```\n" }))
  assert_eq(p.outputs.map(o => o.1), ["r/docs_examples_test.mbt"])
  assert_eq(p.stale, [
    "r/docs_procedures_generated_wbtest.mbt", "r/gone/docs_examples_test.mbt",
  ])
  assert_eq(
    stale_message("r/gone/docs_examples_test.mbt"),
    "r/gone/docs_examples_test.mbt: no chapter generates this file; `generate` removes it",
  )
}

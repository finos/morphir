///|
fn paths(texts : Array[String]) -> Array[@ids.SourcePath] {
  texts.map(path)
}

///|
fn labels(nodes : Array[@project_files.Node]) -> Array[String] {
  nodes.map(node => {
    match node {
      Branch(_, label, _) => label + "/"
      Leaf(_, name) => name
    }
  })
}

///|
fn children(node : @project_files.Node) -> Array[@project_files.Node] {
  match node {
    Branch(_, _, kids) => kids
    Leaf(_, _) => []
  }
}

///|
test "folders come from paths, sort before files and compact single chains" {
  let tree = @project_files.build_tree(
    paths([
      "src/Shop/Orders/Util.elm", "src/Shop/Main.elm", "src/Shop/Orders/Api.elm",
      "src/b.elm", "src/B.elm", "README.md",
    ]),
  )
  let single = @project_files.build_tree(paths(["src/Workbench/Main.elm"]))
  let plain = @project_files.build_tree(
    paths(["src/Workbench/Main.elm"]),
    compact=false,
  )
  @expect.expect_all(s => {
    s.expect(labels(tree), label="root").to_equal(["src/", "README.md"])
    s
    .expect(labels(children(tree[0])), label="src")
    .to_equal(["Shop/", "B.elm", "b.elm"])
    s
    .expect(labels(children(children(tree[0])[0])), label="Shop")
    .to_equal(["Orders/", "Main.elm"])
    s
    .expect(labels(children(children(children(tree[0])[0])[0])), label="Orders")
    .to_equal(["Api.elm", "Util.elm"])
    s.expect(labels(single), label="compacted").to_equal(["src/Workbench/"])
    s
    .expect(single[0], label="compacted path")
    .to_satisfy(node => {
      node is Branch(p, _, _) && p.to_string() == "src/Workbench"
    })
    s.expect(labels(plain), label="not compacted").to_equal(["src/"])
  })
}

///|
test "rows hide collapsed folders and roll problems up to folders" {
  let tree = @project_files.build_tree(
    paths(["src/Shop/Api.elm", "src/Shop/Util.elm", "src/Main.elm"]),
  )
  let counts = Map([("src/Shop/Api.elm", 2), ("src/Main.elm", 1)])
  let open = @project_files.rows(tree, [], counts)
  let closed = @project_files.rows(tree, [path("src/Shop")], counts)
  @expect.expect_all(s => {
    s
    .expect(open.map(r => (r.label, r.depth, r.problems)), label="open")
    .to_equal([
      ("src", 0, 3),
      ("Shop", 1, 2),
      ("Api.elm", 2, 2),
      ("Util.elm", 2, 0),
      ("Main.elm", 1, 1),
    ])
    s
    .expect(closed.map(r => r.label), label="closed")
    .to_equal(["src", "Shop", "Main.elm"])
    s.expect(closed[1].expanded, label="Shop closed").to_be_false()
    s
    .expect(open[2].parent.map(p => p.to_string()), label="parent")
    .to_equal(Some("src/Shop"))
    s
    .expect(open.map(r => (r.position, r.siblings)), label="positions")
    .to_equal([(1, 1), (1, 2), (1, 2), (2, 2), (2, 2)])
  })
}

///|
test "keys move through the tree as the WAI-ARIA tree pattern says" {
  let tree = @project_files.build_tree(
    paths(["src/Shop/Api.elm", "src/Shop/Util.elm", "src/Main.elm"]),
  )
  let open = @project_files.rows(tree, [], Map([]))
  let closed = @project_files.rows(tree, [path("src/Shop")], Map([]))
  let api = Some(@project_files.File(path("src/Shop/Api.elm")))
  let shop = Some(@project_files.Dir(path("src/Shop")))
  @expect.expect_all(s => {
    s
    .expect(@project_files.step(open, None, Down), label="down from nothing")
    .to_equal(FocusOn(Dir(path("src"))))
    s
    .expect(@project_files.step(open, api, Down), label="down")
    .to_equal(FocusOn(File(path("src/Shop/Util.elm"))))
    s
    .expect(@project_files.step(open, api, Up), label="up")
    .to_equal(FocusOn(Dir(path("src/Shop"))))
    s
    .expect(@project_files.step(open, api, Left), label="left to parent")
    .to_equal(FocusOn(Dir(path("src/Shop"))))
    s
    .expect(@project_files.step(open, shop, Left), label="left closes")
    .to_equal(Collapse(path("src/Shop")))
    s
    .expect(@project_files.step(closed, shop, Right), label="right opens")
    .to_equal(Expand(path("src/Shop")))
    s
    .expect(@project_files.step(open, shop, Right), label="right enters")
    .to_equal(FocusOn(File(path("src/Shop/Api.elm"))))
    s
    .expect(@project_files.step(open, api, Activate), label="enter opens")
    .to_equal(OpenFile(path("src/Shop/Api.elm")))
    s
    .expect(@project_files.step(open, api, Last), label="end")
    .to_equal(FocusOn(File(path("src/Main.elm"))))
    s
    .expect(@project_files.step(open, api, First), label="home")
    .to_equal(FocusOn(Dir(path("src"))))
    s
    .expect(@project_files.step(open, api, Typeahead("m")), label="typeahead")
    .to_equal(FocusOn(File(path("src/Main.elm"))))
    s
    .expect(@project_files.step(open, api, Typeahead("a")), label="wraps")
    .to_equal(FocusOn(File(path("src/Shop/Api.elm"))))
  })
}

///|
let segment_names : Array[String] = ["a", "B", "b", "Ab", "_x", "1", "ä"]

///|
/// A path from a generated number: one to four segments from a small alphabet, so folders repeat.
fn generated_path(seed : UInt32) -> @ids.SourcePath {
  let mut rest = seed
  let count = (rest % 4).reinterpret_as_int() + 1
  rest = rest / 4
  let parts : Array[String] = []
  for _ in 0..<count {
    parts.push(
      segment_names[(rest % segment_names.length().reinterpret_as_uint()).reinterpret_as_int()],
    )
    rest = rest / segment_names.length().reinterpret_as_uint()
  }
  path(parts.join("/"))
}

///|
fn leaves(nodes : Array[@project_files.Node]) -> Array[@ids.SourcePath] {
  nodes.fold(init=[], (found, node) => {
    match node {
      Leaf(p, _) => found + [p]
      Branch(_, _, kids) => found + leaves(kids)
    }
  })
}

///|
fn sorted_levels(nodes : Array[@project_files.Node]) -> Bool {
  let names = labels(nodes)
  let folders = names.filter(n => n.has_suffix("/"))
  let files = names.filter(n => !n.has_suffix("/"))
  // A compacted label sorts by its first segment, the folder name at this level.
  let first = fn(label : String) {
    match label.find("/") {
      Some(slash) => label.unsafe_substring(start=0, end=slash)
      None => label
    }
  }
  let ordered = fn(list : Array[String]) {
    let mut ok = true
    for i in 1..<list.length() {
      ok = ok && first(list[i - 1]).lexical_compare(first(list[i])) < 0
    }
    ok
  }
  names == folders + files &&
  ordered(folders) &&
  ordered(files) &&
  nodes.iter().all(node => sorted_levels(children(node)))
}

///|
/// Property: every distinct file path appears exactly once in the tree, compacted or not.
test "every file appears exactly once in the tree" {
  @expect.for_all((seeds : Array[UInt32]) => {
    let input = seeds.map(generated_path)
    let distinct : Array[@ids.SourcePath] = []
    for p in input {
      if !distinct.contains(p) {
        distinct.push(p)
      }
    }
    for compact in [true, false] {
      let found = leaves(@project_files.build_tree(input, compact~))
      @expect.expect(found.length(), label="count").to_equal(distinct.length())
      @expect.expect(found, label="files").to_equal_ignoring_order(distinct)
    }
  })
}

///|
/// Property: at every level folders come before files, and each group is in code-unit order.
test "folders sort before files and by code unit" {
  @expect.for_all((seeds : Array[UInt32]) => {
    let input = seeds.map(generated_path)
    for compact in [true, false] {
      @expect.expect(
        sorted_levels(@project_files.build_tree(input, compact~)),
        label="sorted",
      ).to_be_true()
    }
  })
}

///|
/// Property: with nothing collapsed, the rows list every file once, and each row is one level below its parent.
test "expanded rows show every file once under its parent" {
  @expect.for_all((seeds : Array[UInt32]) => {
    let input = seeds.map(generated_path)
    let all_rows = @project_files.rows(
      @project_files.build_tree(input),
      [],
      Map([]),
    )
    let files = all_rows.filter_map(row => {
      match row.item {
        File(p) => Some(p)
        Dir(_) => None
      }
    })
    @expect.expect(files, label="files").to_have_no_duplicates()
    @expect.expect(files.length(), label="every file").to_equal(
      leaves(@project_files.build_tree(input)).length(),
    )
    for row in all_rows {
      match row.parent {
        None => @expect.expect(row.depth, label="root").to_equal(0)
        Some(parent) => {
          let above = all_rows.iter().find_first(r => r.item == Dir(parent))
          @expect.expect(above.map(r => r.depth + 1), label="depth").to_equal(
            Some(row.depth),
          )
        }
      }
    }
  })
}

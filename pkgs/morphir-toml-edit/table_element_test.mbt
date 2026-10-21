///|
test "indexed table edits preserve both other elements and surrounding bytes" {
  let source = "title = 'keep'\r\n# first\r\n[[products]] # header one\r\n  name = 'One' # name one\r\n  options = { keep = 1, nested.key=2 }\r\n# second\r\n[[products]] # header two\r\nname = 'Two' # name two\r\n[other]\r\nx=3\r\n"
  let doc = @edit.parse(source)
  assert_eq(doc.element(["products"], 0).get(["name"]), Some("'One'"))
  assert_eq(doc.element(["products"], 1).get(["name"]), Some("'Two'"))
  assert_eq(
    doc.element(["products"], 1).set(["name"], "'Changed'").encode(),
    source.replace(old="'Two'", new="'Changed'"),
  )
  assert_eq(
    doc.element(["products"], 0).set(["options", "nested", "key"], "4").encode(),
    source.replace(old="nested.key=2", new="nested.key=4"),
  )
  assert_eq(
    doc.element(["products"], 0).set(["price"], "12").encode(),
    source.replace(
      old="nested.key=2 }\r\n",
      new="nested.key=2 }\r\nprice = 12\r\n",
    ),
  )
  assert_eq(
    doc.element(["products"], 1).remove(["name"]).encode(),
    source.replace(old="name = 'Two'", new=""),
  )
  assert_eq(doc.encode(), source)
}

///|
test "nested array selections retain all ancestor indices and parent table scopes" {
  let source = "[[fruits]]\nname='apple'\n[[fruits.varieties]]\nname='red'\n[fruits.varieties.details]\ncolor='red'\n[[fruits.varieties]]\nname='green'\n[[fruits]]\nname='pear'\n[[fruits.varieties]]\nname='yellow'\n"
  let doc = @edit.parse(source)
  let apple = doc.element(["fruits"], 0)
  let pear = doc.element(["fruits"], 1)
  assert_eq(apple.element(["varieties"], 1).get(["name"]), Some("'green'"))
  assert_eq(pear.element(["varieties"], 0).get(["name"]), Some("'yellow'"))
  assert_eq(
    apple
    .element(["varieties"], 0)
    .set(["details", "color"], "'bright red'")
    .encode(),
    source.replace(old="color='red'", new="color='bright red'"),
  )
  assert_eq(
    pear.element(["varieties"], 0).set(["name"], "'gold'").encode(),
    source.replace(old="'yellow'", new="'gold'"),
  )
  assert_eq(
    apple.element(["varieties"], 0).set(["size"], "1").encode(),
    source.replace(old="name='red'\n", new="name='red'\nsize = 1\n"),
  )
  assert_eq(apple.get(["varieties", "name"]), None)
}

///|
test "append an element after the last element and its descendants before unrelated comments" {
  let source = "# first\n[[products]]\nname='One'\n[products.details]\nx=1\n# second\n[[products]]\nname='Two'\n[products.details]\nx=2\n\n# other stays\n[other]\ny=3\n"
  let appended = @edit.parse(source).append_table(["products"], [
    (["name"], "'Three'"),
    (["flags", "enabled"], "true"),
  ])
  assert_eq(
    appended.encode(),
    source.replace(
      old="\n# other stays",
      new="[[products]]\nname = 'Three'\nflags.enabled = true\n\n# other stays",
    ),
  )
  assert_eq(appended.element(["products"], 2).get(["name"]), Some("'Three'"))
  assert_eq(appended.element(["products"], 1).get(["name"]), Some("'Two'"))
  assert_eq(
    @edit.parse("# empty").append_table(["quoted.key"], []).encode(),
    "# empty\n[[\"quoted.key\"]]\n",
  )
}

///|
test "append nested arrays within the selected parent including an empty nested array" {
  let source = "[[a]]\nname='one'\n[[a.b]]\nx=1\n\n# next parent\n[[a]]\nname='two'\n"
  let doc = @edit.parse(source)
  let first = doc.element(["a"], 0).append_table(["b"], [(["x"], "2")])
  assert_eq(
    first.encode(),
    source.replace(old="\n# next parent", new="[[a.b]]\nx = 2\n\n# next parent"),
  )
  assert_eq(first.element(["a"], 0).element(["b"], 1).get(["x"]), Some("2"))
  let second = doc.element(["a"], 1).append_table(["b"], [(["x"], "3")])
  assert_eq(second.encode(), source + "[[a.b]]\nx = 3\n")
  assert_eq(second.element(["a"], 1).element(["b"], 0).get(["x"]), Some("3"))
}

///|
test "deleting an element removes owned comments and noncontiguous descendants only" {
  let source = "root=0\n\n# first owned\n[[a]] # first header\nx=1 # inline\n\n# other comment\n[other]\nz=9\n\n# child owned\n[a.child]\ny=2\n\n# second owned\n[[a]] # second header\nx=3\n# trailing owned\n"
  let doc = @edit.parse(source)
  assert_eq(
    doc.element(["a"], 0).delete().encode(),
    "root=0\n\n# other comment\n[other]\nz=9\n\n# second owned\n[[a]] # second header\nx=3\n# trailing owned\n",
  )
  let removed = doc.element(["a"], 1).delete()
  assert_eq(
    removed.encode(),
    "root=0\n\n# first owned\n[[a]] # first header\nx=1 # inline\n\n# other comment\n[other]\nz=9\n\n# child owned\n[a.child]\ny=2\n",
  )
  assert_eq(removed.element(["a"], 0).get(["x"]), Some("1"))
}

///|
test "deleting a nested element leaves its parent and sibling parent intact" {
  let source = "[[a]]\nname='one'\n# b zero\n[[a.b]]\nx=1\n# b one\n[[a.b]]\nx=2\n# a one\n[[a]]\nname='two'\n[[a.b]]\nx=3\n"
  let removed = @edit.parse(source).element(["a"], 0).element(["b"], 0).delete()
  assert_eq(
    removed.encode(),
    source.replace(old="# b zero\n[[a.b]]\nx=1\n", new=""),
  )
  assert_eq(removed.element(["a"], 0).element(["b"], 0).get(["x"]), Some("2"))
  assert_eq(removed.element(["a"], 1).element(["b"], 0).get(["x"]), Some("3"))
}

///|
test "implicit and new standard sub-tables are inserted before the next enclosing element" {
  let source = "[[a]]\nx=1\n[a.child.grand]\ny=2\n# next\n[[a]]\nx=3\n"
  let doc = @edit.parse(source)
  let changed = doc.element(["a"], 0).set(["child", "new"], "4")
  assert_eq(
    changed.encode(),
    source.replace(old="# next", new="[a.child]\nnew = 4\n# next"),
  )
  assert_eq(changed.element(["a"], 0).get(["child", "new"]), Some("4"))
  assert_eq(changed.element(["a"], 1).get(["child", "new"]), None)
  let added = doc.element(["a"], 0).add_table(["options"])
  assert_eq(
    added.encode(),
    source.replace(old="# next", new="[a.options]\n# next"),
  )
}

///|
test "ordinary array and dotted-key edits work within a selected element" {
  let source = "[[a]]\nopts.enabled=true # keep\nvalues = [1, 2]\n[[a]]\nopts.enabled=false\n"
  let doc = @edit.parse(source)
  assert_eq(
    doc.element(["a"], 0).set(["opts", "size"], "3").encode(),
    source.replace(
      old="values = [1, 2]\n",
      new="values = [1, 2]\nopts.size = 3\n",
    ),
  )
  assert_eq(
    doc.element(["a"], 0).append(["values"], "3").encode(),
    source.replace(old="[1, 2]", new="[1, 2,3]"),
  )
  assert_eq(
    doc.element(["a"], 0).remove_item(["values"], 0).encode(),
    source.replace(old="[1, 2]", new="[ 2]"),
  )
}

///|
fn element_failure(
  action : () -> Unit raise @edit.Diagnostic,
) -> @edit.DiagnosticKind? {
  try {
    action()
    None
  } catch {
    @edit.Diagnostic(kind, _, _) => Some(kind)
  }
}

///|
test "ambiguous indices missing elements conflicts and injected values are refused" {
  let source = "[[a]]\nx=1\n[[a.b]]\ny=2\n"
  let doc = @edit.parse(source)
  for index in [-1, 1] {
    assert_eq(
      element_failure(fn() raise @edit.Diagnostic {
        ignore(doc.element(["a"], index))
      }),
      Some(@edit.InvalidIndex),
    )
  }
  assert_eq(
    element_failure(fn() raise @edit.Diagnostic {
      ignore(doc.element(["a", "b"], 0))
    }),
    Some(@edit.UnsupportedArrayOfTables),
  )
  assert_eq(
    element_failure(fn() raise @edit.Diagnostic {
      ignore(doc.append_table(["a", "b"], []))
    }),
    Some(@edit.UnsupportedArrayOfTables),
  )
  assert_eq(
    element_failure(fn() raise @edit.Diagnostic {
      ignore(doc.element(["missing"], 0))
    }),
    Some(@edit.MissingPath),
  )
  for value in ["1\nx=2", "1 # comment", "{a=1,a=2}"] {
    assert_eq(
      element_failure(fn() raise @edit.Diagnostic {
        ignore(doc.append_table(["a"], [(["x"], value)]))
      }),
      Some(@edit.InvalidToml),
    )
  }
  assert_eq(
    element_failure(fn() raise @edit.Diagnostic {
      ignore(@edit.parse("[a]\nx=1\n").append_table(["a"], []))
    }),
    Some(@edit.InvalidToml),
  )
  assert_eq(doc.encode(), source)
}

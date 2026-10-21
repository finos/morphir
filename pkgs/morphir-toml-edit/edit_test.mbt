///|
test "localized set and insert retain quoted keys, CRLF and comments" {
  let source = "# 😀 workspace\r\n[workspace] # keep\r\n  members  = [ 'a' ]  # members\r\n\r\n[project]\r\n'name.dot' = '''original'''\r\n"
  let first = @edit.parse(source)
  assert_eq(
    first.set(["workspace", "members"], "['a', 'b']").encode(),
    source.replace(old="[ 'a' ]", new="['a', 'b']"),
  )
  let next = first.set(["project", "name.dot"], "\"changed\"")
  assert_eq(
    next.encode(),
    source.replace(old="'''original'''", new="\"changed\""),
  )
  let inserted = next.set(["workspace", "default_member"], "'a'")
  assert_eq(
    inserted.encode(),
    next
    .encode()
    .replace(
      old="  # members\r\n",
      new="  # members\r\ndefault_member = 'a'\r\n",
    ),
  )
  assert_eq(first.encode(), source)
}

///|
test "inline tables support nested set insert and remove" {
  let source = "options = { keep = 'literal', nested = { n = 1 }, last=2 } # end\n"
  let first = @edit.parse(source)
  let next = first.set(["options", "nested", "n"], "2")
  assert_eq(next.encode(), source.replace(old="n = 1", new="n = 2"))
  let added = next.set(["options", "nested", "new.key"], "true")
  assert_eq(
    added.encode(),
    next.encode().replace(old="n = 2", new="n = 2, \"new.key\" = true"),
  )
  let removed = added.remove(["options", "keep"])
  assert_eq(
    removed.encode(),
    added.encode().replace(old="keep = 'literal',", new=""),
  )
  assert_eq(
    first.remove(["options", "last"]).encode(),
    source.replace(old=", last=2", new=" "),
  )
  assert_eq(
    @edit.parse("x = { a = 1 }").remove(["x", "a"]).encode(),
    "x = {  }",
  )
  assert_eq(@edit.parse("x={}").set(["x", ""], "1").encode(), "x={\"\" = 1}")
}

///|
test "array edits preserve comments, CRLF, whitespace and trailing separators" {
  let source = "[workspace]\r\nmembers = [\r\n 'a', # alpha\r\n 'b' # beta\r\n] # done\r\n"
  let first = @edit.parse(source)
  assert_eq(
    first.append(["workspace", "members"], "'c'").encode(),
    source
    .replace(old="'b' # beta", new="'b', # beta")
    .replace(old="] # done", new="'c'] # done"),
  )
  assert_eq(
    first.remove_item(["workspace", "members"], 0).encode(),
    source.replace(old="'a',", new=""),
  )
  assert_eq(
    first.remove_item(["workspace", "members"], 1).encode(),
    source.replace(old="'a',", new="'a'").replace(old="'b'", new=""),
  )
  assert_eq(@edit.parse("x=[1]").append(["x"], "2").encode(), "x=[1,2]")
  assert_eq(@edit.parse("x=[1, ]").append(["x"], "2").encode(), "x=[1, 2]")
  assert_eq(@edit.parse("x=[ ]").append(["x"], "2").encode(), "x=[ 2]")
  assert_eq(@edit.parse("x=[1,]").remove_item(["x"], 0).encode(), "x=[]")
  assert_eq(@edit.parse("x=[1,2,]").remove_item(["x"], 1).encode(), "x=[1,]")
}

///|
test "table removal handles noncontiguous descendants and retains comments" {
  let source = "# lead\n[a] # a\nx=1 # x\n[b]\ny=2\n[a.child]\nz=3\n[c]\nk=4\n"
  let expected = "# lead\n # a\n # x\n[b]\ny=2\n\n\n[c]\nk=4\n"
  assert_eq(@edit.parse(source).remove_table(["a"]).encode(), expected)
  assert_eq(@edit.parse("[a.b]\nx=1\n").remove_table(["a"]).encode(), "\n\n")
  assert_eq(
    @edit.parse("x=1 # retained\n").remove(["x"]).encode(),
    " # retained\n",
  )
}

///|
test "table and key creation escape arbitrary path segments" {
  let source = "# no newline"
  let added = @edit.parse(source).add_table(["a.b", "quote\"", ""])
  assert_eq(added.encode(), source + "\n[\"a.b\".\"quote\\\"\".\"\"]\n")
  let set = added.set(["a.b", "quote\"", "", "\n\u{0001}"], "'x'")
  assert_eq(set.get(["a.b", "quote\"", "", "\n\u{0001}"]), Some("'x'"))
  assert_eq(
    @edit.parse("[a.b]\nx=1").add_table(["a"]).set(["a", "y"], "2").encode(),
    "[a.b]\nx=1\n[a]\ny = 2\n",
  )
  assert_eq(@edit.parse("[a]").set(["a", "x"], "1").encode(), "[a]\nx = 1\n")
}

///|
fn kind(
  action : () -> @edit.Document raise @edit.Diagnostic,
) -> @edit.DiagnosticKind? {
  try {
    ignore(action())
    None
  } catch {
    @edit.Diagnostic(k, _, _) => Some(k)
  }
}

///|
test "dotted keys retain their form at root inside tables and inline tables" {
  let source = "# keep\r\nfrontend . 'language' = 'elm' # language\r\nfrontend.profile='stable'\r\n[t]\r\n  a.b=1 # one\r\nz = { a.b = 1, sibling=2 } # inline\r\n"
  let doc = @edit.parse(source)
  assert_eq(
    doc.set(["frontend", "language"], "'scheme'").encode(),
    source.replace(old="'elm'", new="'scheme'"),
  )
  let added = doc.set(["frontend", "provider"], "'portable'")
  assert_eq(
    added.encode(),
    source.replace(
      old="frontend.profile='stable'\r\n",
      new="frontend.profile='stable'\r\nfrontend.provider = 'portable'\r\n",
    ),
  )
  assert_eq(
    doc.set(["t", "a", "c"], "2").encode(),
    source.replace(old=" # inline\r\n", new=" # inline\r\na.c = 2\r\n"),
  )
  assert_eq(
    doc.remove(["t", "a", "b"]).encode(),
    source.replace(old="a.b=1", new=""),
  )
  assert_eq(
    doc.set(["t", "z", "a", "c"], "3").encode(),
    source.replace(old="sibling=2", new="sibling=2, a.c = 3"),
  )
  assert_eq(
    doc.remove(["t", "z", "a", "b"]).encode(),
    source.replace(old="a.b = 1,", new=""),
  )
  assert_eq(doc.encode(), source)
}

///|
test "removing the last dotted key or its implicit table leaves surrounding trivia" {
  let source = "# lead\na.b=1 # keep\n[other]\nx=2\n"
  assert_eq(
    @edit.parse(source).remove(["a", "b"]).encode(),
    "# lead\n # keep\n[other]\nx=2\n",
  )
  assert_eq(
    @edit.parse(source).remove_table(["a"]).encode(),
    "# lead\n # keep\n[other]\nx=2\n",
  )
  assert_eq(
    @edit.parse("[t]\na.b=1\na.c=2\nx=3\n").remove_table(["t", "a"]).encode(),
    "[t]\n\n\nx=3\n",
  )
}

///|
test "dotted edits follow TOML table redefinition rules" {
  let source = "[a]\nx=1\n[a.child]\ny=2\n[other]\na.x=3\n"
  let doc = @edit.parse(source)
  assert_eq(
    doc.set(["a", "x"], "4").encode(),
    source.replace(old="x=1", new="x=4"),
  )
  assert_eq(
    doc.set(["other", "a", "y"], "5").get(["other", "a", "y"]),
    Some("5"),
  )
  for
    invalid in [
      "a.b=1\n[a]\nx=2", "[a]\nx=1\n[a.child]\nx=2\n[a]", "a.b=1\na.b=2",
    ] {
    assert_eq(
      kind(fn() raise @edit.Diagnostic { @edit.parse(invalid) }),
      Some(@edit.InvalidToml),
    )
  }
  assert_eq(
    kind(fn() raise @edit.Diagnostic { @edit.parse("a.b=1").add_table(["a"]) }),
    Some(@edit.InvalidToml),
  )
  assert_eq(
    kind(fn() raise @edit.Diagnostic { @edit.parse("a.b=1").set(["a"], "2") }),
    Some(@edit.InvalidToml),
  )
}

///|
test "array-of-tables ancestors and descendants refuse every edit operation" {
  let doc = @edit.parse(
    "x=1\n[[a]]\nx=2\n[a.child]\ny=[1]\n[[a]]\nx=3\n[other]\nz=4\n",
  )
  for path in [["a"], ["a", "x"], ["a", "child", "y"]] {
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.set(path, "1") }),
      Some(@edit.UnsupportedArrayOfTables),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.remove(path) }),
      Some(@edit.UnsupportedArrayOfTables),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.append(path, "1") }),
      Some(@edit.UnsupportedArrayOfTables),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.remove_item(path, 0) }),
      Some(@edit.UnsupportedArrayOfTables),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.add_table(path) }),
      Some(@edit.UnsupportedArrayOfTables),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.remove_table(path) }),
      Some(@edit.UnsupportedArrayOfTables),
    )
  }
  assert_eq(doc.set(["other", "z"], "5").get(["other", "z"]), Some("5"))
  assert_eq(doc.set(["x"], "2").get(["x"]), Some("2"))
}

///|
test "invalid edits leave source intact and reject injected statements" {
  let doc = @edit.parse("x=1\na=[1]\n")
  for
    value in ["", "1\nx=2", "1 # comment", "{a=1,a=2}", "[1,", "'unterminated"] {
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.set(["x"], value) }),
      Some(@edit.InvalidToml),
    )
  }
  assert_eq(
    kind(fn() raise @edit.Diagnostic { doc.set(["x", "child"], "1") }),
    Some(@edit.WrongKind),
  )
  assert_eq(
    kind(fn() raise @edit.Diagnostic { doc.set(["missing", "child"], "1") }),
    Some(@edit.MissingPath),
  )
  assert_eq(
    kind(fn() raise @edit.Diagnostic { doc.remove(["missing"]) }),
    Some(@edit.MissingPath),
  )
  assert_eq(
    kind(fn() raise @edit.Diagnostic { doc.append(["x"], "1") }),
    Some(@edit.WrongKind),
  )
  for index in [-1, 1] {
    assert_eq(
      kind(fn() raise @edit.Diagnostic { doc.remove_item(["a"], index) }),
      Some(@edit.InvalidIndex),
    )
  }
  assert_eq(doc.encode(), "x=1\na=[1]\n")
}

///|
test "diagnostics give a bounded position and reason" {
  try {
    ignore(@edit.parse("# 😀\r\nx=\"bad\\"))
    fail("accepted invalid string")
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, at) => {
      assert_eq(at.line, 2)
      assert_true(at.column >= 3)
      assert_true(at.offset <= "# 😀\r\nx=\"bad\\".length())
    }
    e => fail(e.to_string())
  }
}

///|
test "dotted inline values can be supplied without changing their spelling" {
  let doc = @edit.parse("x=1\na=[]")
  assert_eq(doc.set(["x"], "{ a.b=1 }").get(["x", "a", "b"]), Some("1"))
  assert_eq(doc.append(["a"], "{a.b=1}").get(["a"]), Some("[{a.b=1}]"))
}

///|
test "UTF-8 round trips retain astral characters and reject a leading BOM" {
  let bytes = b"# \xf0\x9f\x98\x80\r\nx='\xf0\x9f\x98\x80'\r\n"
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
  assert_eq(
    kind(fn() raise @edit.Diagnostic { @edit.parse_bytes(b"\xef\xbb\xbfx=1") }),
    Some(@edit.InvalidToml),
  )
  try {
    ignore(@edit.parse_bytes(b"# ok\nx='\xff'"))
    fail("accepted invalid UTF-8")
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, at) => {
      assert_eq(at.line, 2)
      assert_eq(at.column, 4)
      assert_eq(at.offset, 8)
    }
    e => fail(e.to_string())
  }
}

///|
test "deep valid arrays round trip without an artificial grammar limit" {
  let mut source = "x="
  for i = 0; i < 300; i = i + 1 {
    source += "["
  }
  source += "1"
  for i = 0; i < 300; i = i + 1 {
    source += "]"
  }
  assert_eq(@edit.parse(source).encode(), source)
}

///|
test "get does not choose an arbitrary array-of-tables element" {
  let doc = @edit.parse("root=1\n[[a]]\nx=2\n[[a]]\nx=3\n")
  assert_eq(doc.get(["a", "x"]), None)
  assert_eq(doc.get(["root"]), Some("1"))
}

///|
test "offset leap seconds refer to the same recorded UTC instant" {
  for
    value in [
      "1990-12-31T23:59:60Z", "1990-12-31T15:59:60-08:00", "2006-01-01T00:59:60+01:00",
      "2015-07-01T00:29:60.5+00:30", "2017-01-01t23:58:60.999+23:59", "2016-12-31T00:00:60-23:59",
      "2016-12-31T23:59:60-00:00",
    ] {
    let source = "x=" + value
    assert_eq(@edit.parse(source).encode(), source)
    assert_eq(@edit.parse("x=1").set(["x"], value).get(["x"]), Some(value))
  }
  // Local values cannot identify a UTC instant without an offset.
  ignore(@edit.parse("x=00:00:60\ny=2016-12-31T00:00:60"))
}

///|
test "invalid offset leap seconds fail parsing and value edits" {
  for
    value in [
      "2006-01-01T00:00:60Z", "2016-12-31T23:58:60Z", "2016-12-31T22:59:60Z", "2014-12-31T23:59:60Z",
      "2017-01-01T00:59:60+02:00", "2017-01-01T23:59:60+23:59", "1972-01-01T00:00:60Z",
    ] {
    assert_eq(
      kind(fn() raise @edit.Diagnostic { @edit.parse("x=" + value) }),
      Some(@edit.InvalidToml),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic { @edit.parse("x=1").set(["x"], value) }),
      Some(@edit.InvalidToml),
    )
    assert_eq(
      kind(fn() raise @edit.Diagnostic {
        @edit.parse("x=[]").append(["x"], value)
      }),
      Some(@edit.InvalidToml),
    )
  }
}

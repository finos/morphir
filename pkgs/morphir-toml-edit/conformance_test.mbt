// TOML 1.0 corpus, toml-lang/toml-test ff49d109861c1ad25af53f687f2aef19ab650600.
// MIT license in TOML-TEST-LICENSE. Inputs are verbatim, including CRLF.

///|
test "invalid/array/double-comma-01.toml" {
  let source = "double-comma-01 = [1,,2]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/double-comma-02.toml" {
  let source = "double-comma-02 = [1,2,,]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/extend-defined-aot.toml" {
  let source = "[[tab.arr]]\n[tab]\narr.val1=1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/extending-table.toml" {
  let source = "a = [{ b = 1 }]\n\n# Cannot extend tables within static arrays\n# https://github.com/toml-lang/toml/issues/908\n[a.c]\nfoo = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/missing-separator-01.toml" {
  let source = "arrr = [true false]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/missing-separator-02.toml" {
  let source = "wrong = [ 1 2 3 ]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-01.toml" {
  let source = "no-close-01 = [ 1, 2, 3\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-02.toml" {
  let source = "no-close-02 = [1,\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-03.toml" {
  let source = "no-close-03 = [42 #]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-04.toml" {
  let source = "no-close-04 = [{ key = 42\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-05.toml" {
  let source = "no-close-05 = [{ key = 42}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-06.toml" {
  let source = "no-close-06 = [{ key = 42 #}]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-07.toml" {
  let source = "no-close-07 = [{ key = 42} #]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-08.toml" {
  let source = "no-close-08 = [\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-table-01.toml" {
  let source = "no-close-table-01 = [{ key = 42\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-table-02.toml" {
  let source = "no-close-table-02 = [{ key = 42 #\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-table-03.toml" {
  let source = "no-close-table-03 = [1,{a=1]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-close-table-04.toml" {
  let source = "no-close-table-04 = [1,{2]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-comma-01.toml" {
  let source = "no-comma-01 = [true false]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-comma-02.toml" {
  let source = "no-comma-02 = [ 1 2 3 ]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/no-comma-03.toml" {
  let source = "no-comma-03 = [ 1 #,]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/only-comma-01.toml" {
  let source = "only-comma-01 = [,]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/only-comma-02.toml" {
  let source = "only-comma-02 = [,,]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/tables-01.toml" {
  let source = "# INVALID TOML DOC\nfruit = []\n\n[[fruit]] # Not allowed\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/tables-02.toml" {
  let source = "# INVALID TOML DOC\n[[fruit]]\n  name = \"apple\"\n\n  [[fruit.variety]]\n    name = \"red delicious\"\n\n  # This table conflicts with the previous table\n  [fruit.variety]\n    name = \"granny smith\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/text-after-array-entries.toml" {
  let source = "array = [\n  \"Is there life after an array separator?\", No\n  \"Entry\"\n]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/text-before-array-separator.toml" {
  let source = "array = [\n  \"Is there life before an array separator?\" No,\n  \"Entry\"\n]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/array/text-in-array.toml" {
  let source = "array = [\n  \"Entry 1\",\n  I don't belong,\n  \"Entry 2\",\n]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/almost-false.toml" {
  let source = "almost-false            = fals\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/almost-false-with-extra.toml" {
  let source = "almost-false-with-extra = falsify\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/almost-true.toml" {
  let source = "almost-true             = tru\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/almost-true-with-extra.toml" {
  let source = "almost-true-with-extra  = truthy\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/capitalized-false.toml" {
  let source = "capitalized-false        = False\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/capitalized-true.toml" {
  let source = "capitalized-true         = True\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/just-f.toml" {
  let source = "just-f                  = f\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/just-t.toml" {
  let source = "just-t                  = t\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/mixed-case.toml" {
  let source = "mixed-case              = valid   = False\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/mixed-case-false.toml" {
  let source = "mixed-case-false        = falsE\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/mixed-case-true.toml" {
  let source = "mixed-case-true         = trUe\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/starting-same-false.toml" {
  let source = "starting-same-false     = falsey\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/starting-same-true.toml" {
  let source = "starting-same-true      = truer\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/wrong-case-false.toml" {
  let source = "wrong-case-false        = FALSE\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/bool/wrong-case-true.toml" {
  let source = "wrong-case-true         = TRUE\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/bare-cr.toml" {
  let source = "# The following line contains a single carriage return control character\r\n\r"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/bare-formfeed.toml" {
  let source = "bare-formfeed     = \u{c}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/bare-null.toml" {
  let source = "bare-null         = \"some value\" \u{0}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/bare-vertical-tab.toml" {
  let source = "bare-vertical-tab = \u{b}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-cr.toml" {
  let source = "comment-cr   = \"Carriage return in comment\" # \ra=1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-del.toml" {
  let source = "comment-del  = \"0x7f\"   # \u{7f}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-ff.toml" {
  let source = "comment-ff   = \"0x7f\"   # \u{c}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-lf.toml" {
  let source = "comment-lf   = \"ctrl-P\" # \u{10}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-null.toml" {
  let source = "comment-null = \"null\"   # \u{0}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/comment-us.toml" {
  let source = "comment-us   = \"ctrl-_\" # \u{1f}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/linetab-number-01.toml" {
  let source = "linetab-number-01 = 1\u{b}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/linetab-number-02.toml" {
  let source = "linetab-number-02 = 1.5\u{b}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/linetab-number-03.toml" {
  let source = "linetab-number-03 = 0xff\u{b}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/linetab-number-04.toml" {
  let source = "linetab-number-04 = +inf\u{b}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/multi-del.toml" {
  let source = "multi-del  = \"\"\"null\u{7f}\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/multi-lf.toml" {
  let source = "multi-lf   = \"\"\"null\u{10}\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/multi-null.toml" {
  let source = "multi-null = \"\"\"null\u{0}\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/multi-us.toml" {
  let source = "multi-us   = \"\"\"null\u{1f}\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/only-ff.toml" {
  let source = "\u{c}"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/only-null.toml" {
  let source = "\u{0}"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/only-vt.toml" {
  let source = "\u{b}"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawmulti-del.toml" {
  let source = "rawmulti-del  = '''null\u{7f}'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawmulti-lf.toml" {
  let source = "rawmulti-lf   = '''null\u{10}'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawmulti-null.toml" {
  let source = "rawmulti-null = '''null\u{0}'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawmulti-us.toml" {
  let source = "rawmulti-us   = '''null\u{1f}'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawstring-cr.toml" {
  let source = "rawstring-cr   = 'null\r'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawstring-del.toml" {
  let source = "rawstring-del  = 'null\u{7f}'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawstring-lf.toml" {
  let source = "rawstring-lf   = 'null\u{10}'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawstring-null.toml" {
  let source = "rawstring-null = 'null\u{0}'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/rawstring-us.toml" {
  let source = "rawstring-us   = 'null\u{1f}'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-bs.toml" {
  let source = "string-bs   = \"backspace\u{8}\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-cr.toml" {
  let source = "string-cr   = \"null\r\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-del.toml" {
  let source = "string-del  = \"null\u{7f}\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-lf.toml" {
  let source = "string-lf   = \"null\u{10}\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-null.toml" {
  let source = "string-null = \"null\u{0}\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/control/string-us.toml" {
  let source = "string-us   = \"null\u{1f}\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/day-zero.toml" {
  let source = "foo = 1997-09-00T09:09:09.09Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/feb-29.toml" {
  let source = "\"not a leap year\" = 2100-02-29T15:15:15Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/feb-30.toml" {
  let source = "\"only 28 or 29 days in february\" = 1988-02-30T15:15:15Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/hour-over.toml" {
  let source = "# time-hour       = 2DIGIT  ; 00-23\nd = 2006-01-01T24:00:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/leading-zero-date.toml" {
  let source = "# No leading zero on year allowed.\nd = 02026-05-07\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/leading-zero-datetime.toml" {
  let source = "# No leading zero on year allowed.\nd = 02026-05-07T14:15:16Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/mday-over.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-32T00:00:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/mday-under.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-00T00:00:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/minute-over.toml" {
  let source = "# time-minute     = 2DIGIT  ; 00-59\nd = 2006-01-01T00:60:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/month-over.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2006-13-01T00:00:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/month-under.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2007-00-01T00:00:00-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-date-time-sep.toml" {
  let source = "foo = 1997-09-0909:09:09\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-leads.toml" {
  let source = "# Month \"7\" instead of \"07\"; the leading zero is required.\nno-leads = 1987-7-05T17:45:00Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-leads-month.toml" {
  let source = "# Month \"7\" instead of \"07\"; the leading zero is required.\nno-leads = 1987-7-05T17:45:00Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-leads-with-milli.toml" {
  let source = "# Day \"5\" instead of \"05\"; the leading zero is required.\nwith-milli = 1987-07-5T17:45:00.12Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-secs.toml" {
  let source = "# No seconds in time.\nno-secs = 1987-07-05T17:45Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-t.toml" {
  let source = "# No \"t\" or \"T\" between the date and time.\nno-t = 1987-07-0517:45:00Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/no-year-month-sep.toml" {
  let source = "foo = 199709-09\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-minus-minute-1digit.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+09:9\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-minus-no-hour-minute.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-minus-no-hour-minute-sep.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+0909\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-minus-no-minute.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+09\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-overflow-hour.toml" {
  let source = "# Hour must be 00-24\nd = 1985-06-18 17:04:07+25:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-overflow-minute.toml" {
  let source = "d = 1985-06-18 17:04:07+12:60\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-plus-minute-1digit.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+09:9\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-plus-no-hour-minute.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-plus-no-hour-minute-sep.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+0909\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/offset-plus-no-minute.toml" {
  let source = "foo = 1997-09-09T09:09:09.09+09\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/only-T.toml" {
  let source = "foo = T\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/only-TZ.toml" {
  let source = "foo = TZ\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/only-Tdot.toml" {
  let source = "foo = T.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/second-over.toml" {
  let source = "# time-second     = 2DIGIT  ; 00-58, 00-59, 00-60 based on leap second\n#                           ; rules\nd = 2006-01-01T00:00:61-00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/second-trailing-dot.toml" {
  let source = "foo = 1997-09-09T09:09:09.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/second-trailing-dotz.toml" {
  let source = "foo = 2016-09-09T09:09:09.Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/time-no-leads.toml" {
  let source = "# Leading 0 is always required.\nd = 2023-10-01T1:32:00Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/trailing-x.toml" {
  let source = "sign=2020-01-01x\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/y10k-date.toml" {
  let source = "# Maximum RFC3399 year is 9999.\nd = 10000-01-01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/datetime/y10k-datetime.toml" {
  let source = "# Maximum RFC3399 year is 9999.\nd = 10000-01-01 00:00:00z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/bom-not-at-start-01.toml" {
  let source = "# Contains UTF-8 BOM between = and 1\na=﻿1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/bom-not-at-start-02.toml" {
  let source = "﻿﻿# Contains two UTF-8 BOMS at the start\na=1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/bom-not-at-start-03.toml" {
  let source = "﻿﻿a=1\n# Contains two UTF-8 BOMS at the start\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/ideographic-space.toml" {
  let source = "# First on next line is U+3000 IDEOGRAPHIC SPACE\n　foo = \"bar\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/utf16-comment.toml" {
  let source = "\u{0}#\u{0} \u{0}U\u{0}T\u{0}F\u{0}-\u{0}1\u{0}6\u{0} \u{0}w\u{0}i\u{0}t\u{0}h\u{0}o\u{0}u\u{0}t\u{0} \u{0}B\u{0}O\u{0}M\u{0}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/encoding/utf16-key.toml" {
  let source = "\u{0}k\u{0} \u{0}=\u{0} \u{0}\"\u{0}v\u{0}\"\u{0}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/arabic-zero-01.toml" {
  let source = "arabic-zero-01 = 1.٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/arabic-zero-02.toml" {
  let source = "arabic-zero-02 = ٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/arabic-zero-03.toml" {
  let source = "arabic-zero-03 = 1e٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/arabic-zero-04.toml" {
  let source = "arabic-zero-04 = +٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/double-dot-01.toml" {
  let source = "double-dot-01 = 0..1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/double-dot-02.toml" {
  let source = "double-dot-02 = 0.1.2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-dot-01.toml" {
  let source = "exp-dot-01 = 1e2.3\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-dot-02.toml" {
  let source = "exp-dot-02 = 1.e2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-dot-03.toml" {
  let source = "exp-dot-03 = 3.e+20\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-double-e-01.toml" {
  let source = "exp-double-e-01 = 1ee2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-double-e-02.toml" {
  let source = "exp-double-e-02 = 1e2e3\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-double-us.toml" {
  let source = "exp-double-us = 1e__23\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-leading-us.toml" {
  let source = "exp-leading-us = 1e_23\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-trailing-us.toml" {
  let source = "exp-trailing-us = 1e23_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-trailing-us-01.toml" {
  let source = "exp-trailing-us-01 = 1_e2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/exp-trailing-us-02.toml" {
  let source = "exp-trailing-us-02 = 1.2_e2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/inf-capital.toml" {
  let source = "v = Inf\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/inf-incomplete-01.toml" {
  let source = "inf-incomplete-01 = in\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/inf-incomplete-02.toml" {
  let source = "inf-incomplete-02 = +in\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/inf-incomplete-03.toml" {
  let source = "inf-incomplete-03 = -in\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/inf_underscore.toml" {
  let source = "inf_underscore = in_f\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-dot.toml" {
  let source = "leading-dot = .12345\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-dot-neg.toml" {
  let source = "leading-dot-neg = -.12345\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-dot-plus.toml" {
  let source = "leading-dot-plus = +.12345\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-us.toml" {
  let source = "leading-us = _1.2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-zero.toml" {
  let source = "leading-zero = 03.14\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-zero-neg.toml" {
  let source = "leading-zero-neg = -03.14\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/leading-zero-plus.toml" {
  let source = "leading-zero-plus = +03.14\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/nan-capital.toml" {
  let source = "v = NaN\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/nan-incomplete-01.toml" {
  let source = "nan-incomplete-01 = na\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/nan-incomplete-02.toml" {
  let source = "nan-incomplete-02 = +na\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/nan-incomplete-03.toml" {
  let source = "nan-incomplete-03 = -na\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/nan_underscore.toml" {
  let source = "nan_underscore = na_n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-dot.toml" {
  let source = "trailing-dot = 1.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-dot-01.toml" {
  let source = "trailing-point = 1.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-dot-02.toml" {
  let source = "a = 1.\nb = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-dot-min.toml" {
  let source = "trailing-dot-min = -1.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-dot-plus.toml" {
  let source = "trailing-dot-plus = +1.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-exp.toml" {
  let source = "trailing-exp = 0.0E\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-exp-dot.toml" {
  let source = "trailing-exp-dot =  0.e\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-exp-minus.toml" {
  let source = "trailing-exp-minus = 0.0e-\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-exp-plus.toml" {
  let source = "trailing-exp-plus = 0.0e+\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-us.toml" {
  let source = "trailing-us = 1.2_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-us-exp-01.toml" {
  let source = "trailing-us-exp-1 = 1_e2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/trailing-us-exp-02.toml" {
  let source = "trailing-us-exp-2 = 1.2_e2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/us-after-dot.toml" {
  let source = "us-after-dot = 1._2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/float/us-before-dot.toml" {
  let source = "us-before-dot = 1_.2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/bad-key-syntax.toml" {
  let source = "tbl = { a = 1, [b] }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/double-comma.toml" {
  let source = "t = {x=3,,y=4}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/duplicate-key-01.toml" {
  let source = "# Duplicate keys within an inline table are invalid\na={b=1, b=2}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/duplicate-key-02.toml" {
  let source = "table1 = { table2.dupe = 1, table2.dupe = 2 }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/duplicate-key-03.toml" {
  let source = "tbl = { fruit = { apple.color = \"red\" }, fruit.apple.texture = { smooth = true } }\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/duplicate-key-04.toml" {
  let source = "tbl = { a.b = \"a_b\", a.b.c = \"a_b_c\" }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/empty-01.toml" {
  let source = "t = {,}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/empty-02.toml" {
  let source = "t = {,\n}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/empty-03.toml" {
  let source = "t = {\n,\n}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/linebreak-01.toml" {
  let source = "# No newlines are allowed between the curly braces unless they are valid within\n# a value.\nsimple = { a = 1 \n}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/linebreak-02.toml" {
  let source = "t = {a=1,\nb=2}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/linebreak-03.toml" {
  let source = "t = {a=1\n,b=2}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/linebreak-04.toml" {
  let source = "json_like = {\n          first = \"Tom\",\n          last = \"Preston-Werner\"\n}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/no-close-01.toml" {
  let source = "a={\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/no-close-02.toml" {
  let source = "a={b=1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/no-comma-01.toml" {
  let source = "t = {x = 3 y = 4}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/no-comma-02.toml" {
  let source = "arrr = { comma-missing = true valid-toml = false }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-01.toml" {
  let source = "a.b=0\n# Since table \"a\" is already defined, it can't be replaced by an inline table.\na={}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-02.toml" {
  let source = "a={}\n# Inline tables are immutable and can't be extended\n[a.b]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-03.toml" {
  let source = "a = { b = 1 }\na.b = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-04.toml" {
  let source = "inline-t = { nest = {} }\n\n[[inline-t.nest]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-05.toml" {
  let source = "inline-t = { nest = {} }\n\n[inline-t.nest]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-06.toml" {
  let source = "a = { b = 1, b.c = 2 }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-07.toml" {
  let source = "tab = { inner.table = [{}], inner.table.val = \"bad\" }"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-08.toml" {
  let source = "tab = { inner = { dog = \"best\" }, inner.cat = \"worst\" }"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-09.toml" {
  let source = "[tab.nested]\ninline-t = { nest = {} }\n\n[tab]\nnested.inline-t.nest = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/overwrite-10.toml" {
  let source = "# Set implicit \"b\", overwrite \"b\" (illegal!) and then set another implicit.\n#\n# Caused panic: https://github.com/BurntSushi/toml/issues/403\na = {b.a = 1, b = 2, b.c = 3}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/inline-table/trailing-comma.toml" {
  let source = "# A terminating comma (also called trailing comma) is not permitted after the\n# last key/value pair in an inline table\nabc = { abc = 123, }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/arabic-zero-01.toml" {
  let source = "arabic-zero-01 = 1٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/arabic-zero-02.toml" {
  let source = "arabic-zero-02 = 1_0٠\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/arabic-zero-03.toml" {
  let source = "arabic-zero-03 = ٠.1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/arabic-zero-04.toml" {
  let source = "arabic-zero-04 = ٠e0\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/capital-bin.toml" {
  let source = "capital-bin = 0B0\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/capital-hex.toml" {
  let source = "capital-hex = 0X1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/capital-oct.toml" {
  let source = "capital-oct = 0O0\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/double-sign-nex.toml" {
  let source = "double-sign-nex = --99\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/double-sign-plus.toml" {
  let source = "double-sign-plus = ++99\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/double-us.toml" {
  let source = "double-us = 1__23\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/incomplete-bin.toml" {
  let source = "incomplete-bin = 0b\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/incomplete-hex.toml" {
  let source = "incomplete-hex = 0x\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/incomplete-oct.toml" {
  let source = "incomplete-oct = 0o\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/invalid-bin.toml" {
  let source = "invalid-bin = 0b0012\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/invalid-hex-01.toml" {
  let source = "invalid-hex-01 = 0xaafz\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/invalid-hex-02.toml" {
  let source = "invalid-hex-02 = 0xgabba00f1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/invalid-hex-03.toml" {
  let source = "a = 0x-1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/invalid-oct.toml" {
  let source = "invalid-oct = 0o778\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-us.toml" {
  let source = "leading-us = _123\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-us-bin.toml" {
  let source = "leading-us-bin = _0b1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-us-hex.toml" {
  let source = "leading-us-hex = _0x1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-us-oct.toml" {
  let source = "leading-us-oct = _0o1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-01.toml" {
  let source = "leading-zero-01 = 01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-02.toml" {
  let source = "leading-zero-02 = 00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-03.toml" {
  let source = "leading-zero-03 = 0_0\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-sign-01.toml" {
  let source = "leading-zero-sign-01 = -01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-sign-02.toml" {
  let source = "leading-zero-sign-02 = +01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/leading-zero-sign-03.toml" {
  let source = "leading-zero-sign-03 = +0_1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/negative-bin.toml" {
  let source = "negative-bin = -0b11010110\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/negative-hex.toml" {
  let source = "negative-hex = -0xff\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/negative-oct.toml" {
  let source = "negative-oct = -0o755\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/positive-bin.toml" {
  let source = "positive-bin = +0b11010110\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/positive-hex.toml" {
  let source = "positive-hex = +0xff\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/positive-oct.toml" {
  let source = "positive-oct = +0o755\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/text-after-integer.toml" {
  let source = "answer = 42 the ultimate answer?\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/trailing-us.toml" {
  let source = "trailing-us = 123_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/trailing-us-bin.toml" {
  let source = "trailing-us-bin = 0b1_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/trailing-us-hex.toml" {
  let source = "trailing-us-hex = 0x1_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/trailing-us-oct.toml" {
  let source = "trailing-us-oct = 0o1_\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/us-after-bin.toml" {
  let source = "us-after-bin = 0b_1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/us-after-hex.toml" {
  let source = "us-after-hex = 0x_1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/integer/us-after-oct.toml" {
  let source = "us-after-oct = 0o_1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/after-array.toml" {
  let source = "[[agencies]] owner = \"S Cjelli\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/after-table.toml" {
  let source = "[error] this = \"should not be here\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/after-value.toml" {
  let source = "first = \"Tom\" last = \"Preston-Werner\" # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/bare-invalid-character-01.toml" {
  let source = "! = 123\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/bare-invalid-character-02.toml" {
  let source = "bare!key = 123\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/dot.toml" {
  let source = ". = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/dotdot.toml" {
  let source = ".. = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/dotted-redefine-table-01.toml" {
  let source = "a = false\na.b = true\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/dotted-redefine-table-02.toml" {
  let source = "# Defined a.b as int\na.b = 1\n# Tries to access it as table: error\na.b.c = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-01.toml" {
  let source = "name = \"Tom\"\nname = \"Pradyun\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-02.toml" {
  let source = "dupe = false\ndupe = true\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-03.toml" {
  let source = "spelling   = \"favorite\"\n\"spelling\" = \"favourite\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-04.toml" {
  let source = "spelling   = \"favorite\"\n'spelling' = \"favourite\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-05.toml" {
  let source = "a        = 1\n\"\\u0061\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-06.toml" {
  let source = "\"a'b\"      = 1\n\"a\\u0027b\" = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-07.toml" {
  let source = "\"\" = 1\n\"\" = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-08.toml" {
  let source = "arr = [1]\narr = [2]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/duplicate-keys-09.toml" {
  let source = "tbl = {k=1}\ntbl = {kk=2}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/empty.toml" {
  let source = " = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/end-in-escape.toml" {
  let source = "\"backslash is the last char\\\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/escape.toml" {
  let source = "\\u00c0 = \"latin capital letter A with grave\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/hash.toml" {
  let source = "a# = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/multiline-key-01.toml" {
  let source = "\"\"\"key\"\"\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/multiline-key-02.toml" {
  let source = "'''key''' = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/multiline-key-03.toml" {
  let source = "\"\"\"key\"\"\" = \"\"\"v\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/multiline-key-04.toml" {
  let source = "'''key''' = '''v'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-01.toml" {
  let source = "barekey\n   = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-02.toml" {
  let source = "\"quoted\nkey\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-03.toml" {
  let source = "'quoted\nkey' = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-04.toml" {
  let source = "\"\"\"long\nkey\"\"\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-05.toml" {
  let source = "'''long\nkey''' = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/newline-06.toml" {
  let source = "key =\n1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-01.toml" {
  let source = "a = 1 b = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-02.toml" {
  let source = "0=0r=false\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-03.toml" {
  let source = "0=\"\"o=\"\"m=\"\"r=\"\"00=\"0\"q=\"\"\"0\"\"\"e=\"\"\"0\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-04.toml" {
  let source = "[[0000l0]]\n0=\"0\"[[0000l0]]\n0=\"0\"[[0000l0]]\n0=\"0\"l=\"0\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-05.toml" {
  let source = "0=[0]00=[0,0,0]t=[\"0\",\"0\",\"0\"]s=[1000-00-00T00:00:00Z,2000-00-00T00:00:00Z]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-06.toml" {
  let source = "0=0r0=0r=false\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/no-eol-07.toml" {
  let source = "0=0r0=0r=falsefal=false\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/only-float.toml" {
  let source = "1.1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/only-int.toml" {
  let source = "1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/only-str.toml" {
  let source = "\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/open-bracket.toml" {
  let source = "[abc = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/partial-quoted.toml" {
  let source = "partial\"quoted\" = 5\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/quoted-unclosed-01.toml" {
  let source = "\"key = x\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/quoted-unclosed-02.toml" {
  let source = "\"key\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/single-open-bracket.toml" {
  let source = "[\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/space.toml" {
  let source = "a b = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/space-quoted.toml" {
  let source = "# Tab literal between a and b below.\n\"a\" \"b\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/special-character.toml" {
  let source = "μ = \"greek small letter mu\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/start-bracket.toml" {
  let source = "[a]\n[xyz = 5\n[b]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/start-dot.toml" {
  let source = ".key = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/tab.toml" {
  let source = "# Tab literal between a and b below.\na\tb = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/tab-quoted.toml" {
  let source = "# Tab literal between a and b below.\n\"a\"\t\"b\" = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/two-equals-01.toml" {
  let source = "key= = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/two-equals-02.toml" {
  let source = "a==1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/two-equals-03.toml" {
  let source = "a=b=1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-01.toml" {
  let source = "key\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-02.toml" {
  let source = "key = \n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-03.toml" {
  let source = "\"key\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-04.toml" {
  let source = "\"key\" = \n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-05.toml" {
  let source = "fs.fw\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-06.toml" {
  let source = "fs.fw =\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/key/without-value-07.toml" {
  let source = "fs.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/day-1digit.toml" {
  let source = "foo = 1997-09-9\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/feb-29.toml" {
  let source = "\"not a leap year\" = 2100-02-29\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/feb-30.toml" {
  let source = "\"only 28 or 29 days in february\" = 1988-02-30\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/mday-over.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-32\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/mday-under.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/month-over.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2006-13-01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/month-under.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2007-00-01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/no-leads.toml" {
  let source = "# Month \"7\" instead of \"07\"; the leading zero is required.\nno-leads = 1987-7-05\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/no-leads-with-milli.toml" {
  let source = "# Day \"5\" instead of \"05\"; the leading zero is required.\nwith-milli = 1987-07-5\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/trailing-t.toml" {
  let source = "# Date cannot end with trailing T\nd = 2006-01-30T\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/y10k.toml" {
  let source = "# Maximum RFC3399 year is 9999.\nd = 10000-01-01\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-date/year-3digits.toml" {
  let source = "foo = 199-09-09\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/feb-29.toml" {
  let source = "\"not a leap year\" = 2100-02-29T15:15:15\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/feb-30.toml" {
  let source = "\"only 28 or 29 days in february\" = 1988-02-30T15:15:15\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/hour-over.toml" {
  let source = "# time-hour       = 2DIGIT  ; 00-23\nd = 2006-01-01T24:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/mday-over.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-32T00:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/mday-under.toml" {
  let source = "# date-mday       = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on\n#                           ; month/year\nd = 2006-01-00T00:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/minute-over.toml" {
  let source = "# time-minute     = 2DIGIT  ; 00-59\nd = 2006-01-01T00:60:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/month-over.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2006-13-01T00:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/month-under.toml" {
  let source = "# date-month      = 2DIGIT  ; 01-12\nd = 2007-00-01T00:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/no-leads.toml" {
  let source = "# Month \"7\" instead of \"07\"; the leading zero is required.\nno-leads = 1987-7-05T17:45:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/no-leads-with-milli.toml" {
  let source = "# Day \"5\" instead of \"05\"; the leading zero is required.\nwith-milli = 1987-07-5T17:45:00.12\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/no-secs.toml" {
  let source = "# No seconds in time.\nno-secs = 1987-07-05T17:45\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/no-t.toml" {
  let source = "# No \"t\" or \"T\" between the date and time.\nno-t = 1987-07-0517:45:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/second-over.toml" {
  let source = "# time-second     = 2DIGIT  ; 00-58, 00-59, 00-60 based on leap second\n#                           ; rules\nd = 2006-01-01T00:00:61\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/time-no-leads.toml" {
  let source = "# Leading 0 is always required.\nd = 2023-10-01T1:32:00Z\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-datetime/y10k.toml" {
  let source = "# Maximum RFC3399 year is 9999.\nd = 10000-01-01 00:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/hour-over.toml" {
  let source = "# time-hour       = 2DIGIT  ; 00-23\nd = 24:00:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/minute-over.toml" {
  let source = "# time-minute     = 2DIGIT  ; 00-59\nd = 00:60:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/no-secs.toml" {
  let source = "# No seconds in time.\nno-secs = 17:45\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/second-over.toml" {
  let source = "# time-second     = 2DIGIT  ; 00-58, 00-59, 00-60 based on leap second\n#                           ; rules\nd = 00:00:61\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/time-no-leads-01.toml" {
  let source = "# Leading 0 is always required.\nd = 1:32:00\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/time-no-leads-02.toml" {
  let source = "# Leading 0 is always required.\nd = 01:32:0\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/trailing-dot.toml" {
  let source = "t = 12:13:14.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/local-time/trailing-dotdot.toml" {
  let source = "t = 12:13:14..\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/inline-table-2-0.toml" {
  let source = "[product]\ntype = { name = \"Nail\" }\ntype.edible = false  # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/inline-table-3-0.toml" {
  let source = "[product]\ntype.name = \"Nail\"\ntype = { edible = false }  # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/key-value-pair-1.toml" {
  let source = "key = # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/keys-2.toml" {
  let source = "= \"no key name\"  # INVALID\n\"\" = \"blank\"     # VALID but discouraged\n'' = 'blank'     # VALID but discouraged\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/string-4-0.toml" {
  let source = "str4 = \"\"\"Here are two quotation marks: \"\". Simple enough.\"\"\"\nstr5 = \"\"\"Here are three quotation marks: \"\"\".\"\"\"  # INVALID\nstr5 = \"\"\"Here are three quotation marks: \"\"\\\".\"\"\"\nstr6 = \"\"\"Here are fifteen quotation marks: \"\"\\\"\"\"\\\"\"\"\\\"\"\"\\\"\"\"\\\".\"\"\"\n\n# \"This,\" she said, \"is just a pointless statement.\"\nstr7 = \"\"\"\"This,\" she said, \"is just a pointless statement.\"\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/string-7-0.toml" {
  let source = "quot15 = '''Here are fifteen quotation marks: \"\"\"\"\"\"\"\"\"\"\"\"\"\"\"'''\n\napos15 = '''Here are fifteen apostrophes: ''''''''''''''''''  # INVALID\napos15 = \"Here are fifteen apostrophes: '''''''''''''''\"\n\n# 'That,' she said, 'is still pointless.'\nstr = ''''That,' she said, 'is still pointless.''''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/table-9-0.toml" {
  let source = "[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n\n[fruit.apple]  # INVALID\n# [fruit.apple.taste]  # INVALID\n\n[fruit.apple.texture]  # you can add sub-tables\nsmooth = true\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/spec-1.0.0/table-9-1.toml" {
  let source = "[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n\n# [fruit.apple]  # INVALID\n[fruit.apple.taste]  # INVALID\n\n[fruit.apple.texture]  # you can add sub-tables\nsmooth = true\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-byte-escape.toml" {
  let source = "naughty = \"\\xAg\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-concat.toml" {
  let source = "no_concat = \"first\" \"second\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-escape-01.toml" {
  let source = "invalid-escape = \"This string has a bad \\a escape character.\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-escape-02.toml" {
  let source = "invalid-escape = \"This string has a bad \\  escape character.\"\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-escape-03.toml" {
  let source = "backslash = \"\\\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-escape-04.toml" {
  let source = "a = \"a \\\\\\ b\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-escape-05.toml" {
  let source = "a = \"a \\\\\\\\\\ b\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-hex-esc-01.toml" {
  let source = "bad-hex-esc-01 = \"\\x0g\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-hex-esc-02.toml" {
  let source = "bad-hex-esc-02 = \"\\xG0\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-hex-esc-03.toml" {
  let source = "bad-hex-esc-03 = \"\\x\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-hex-esc-04.toml" {
  let source = "bad-hex-esc-04 = \"\\x 50\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-hex-esc-05.toml" {
  let source = "bad-hex-esc-5 = \"\\x 50\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-multiline.toml" {
  let source = "multi = \"first line\nsecond line\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-slash-escape.toml" {
  let source = "invalid-escape = \"This string has a bad \\/ escape character.\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-01.toml" {
  let source = "bad-uni-esc-01 = \"val\\ue\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-02.toml" {
  let source = "bad-uni-esc-02 = \"val\\Ux\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-03.toml" {
  let source = "bad-uni-esc-03 = \"val\\U0000000\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-04.toml" {
  let source = "bad-uni-esc-04 = \"val\\U0000\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-05.toml" {
  let source = "bad-uni-esc-05 = \"val\\Ugggggggg\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-06.toml" {
  let source = "bad-uni-esc-06 = \"This string contains a non scalar unicode codepoint \\uD801\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-07.toml" {
  let source = "bad-uni-esc-07 = \"\\uabag\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-01.toml" {
  let source = "bad-uni-esc-ml-01 = \"\"\"val\\ue\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-02.toml" {
  let source = "bad-uni-esc-ml-02 = \"\"\"val\\Ux\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-03.toml" {
  let source = "bad-uni-esc-ml-03 = \"\"\"val\\U0000000\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-04.toml" {
  let source = "bad-uni-esc-ml-04 = \"\"\"val\\U0000\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-05.toml" {
  let source = "bad-uni-esc-ml-05 = \"\"\"val\\Ugggggggg\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-06.toml" {
  let source = "bad-uni-esc-ml-06 = \"\"\"This string contains a non scalar unicode codepoint \\uD801\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/bad-uni-esc-ml-07.toml" {
  let source = "bad-uni-esc-ml-07 = \"\"\"\\uabag\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-byte-escapes.toml" {
  let source = "answer = \"\\x33\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-multiline-out-of-range-unicode-escape-01.toml" {
  let source = "a = \"\"\"\\UFFFFFFFF\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-multiline-out-of-range-unicode-escape-02.toml" {
  let source = "a = \"\"\"\\U00D80000\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-multiline-quotes.toml" {
  let source = "str5 = \"\"\"Here are three quotation marks: \"\"\".\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-multiline-unknown-escape.toml" {
  let source = "a = \"\"\"\\@\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-out-of-range-unicode-escape-01.toml" {
  let source = "a = \"\\UFFFFFFFF\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-out-of-range-unicode-escape-02.toml" {
  let source = "a = \"\\U00D80000\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/basic-unknown-escape.toml" {
  let source = "a = \"\\@\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/literal-multiline-quotes-01.toml" {
  let source = "a = '''6 apostrophes: ''''''\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/literal-multiline-quotes-02.toml" {
  let source = "a = '''15 apostrophes: ''''''''''''''''''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/missing-quotes.toml" {
  let source = "name = value\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/missing-quotes-array.toml" {
  let source = "name = [value]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/missing-quotes-inline-table.toml" {
  let source = "name = { key = value }\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-bad-escape-01.toml" {
  let source = "k = \"\"\"t\\a\"\"\"\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-bad-escape-02.toml" {
  let source = "# \\<Space> is not a valid escape.\nk = \"\"\"t\\ t\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-bad-escape-03.toml" {
  let source = "# \\<Space> is not a valid escape.\nk = \"\"\"t\\ \"\"\"\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-bad-escape-04.toml" {
  let source = "backslash = \"\"\"\\\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-escape-space-01.toml" {
  let source = "a = \"\"\"\n  foo \\ \\n\n  bar\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-escape-space-02.toml" {
  let source = "bee = \"\"\"\nhee \\\n\ngee \\   \"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-lit-no-close-01.toml" {
  let source = "invalid = '''\n    this will fail\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-lit-no-close-02.toml" {
  let source = "x='''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-lit-no-close-03.toml" {
  let source = "not-closed= '''\ndiibaa\nblibae ete\neteta\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-lit-no-close-04.toml" {
  let source = "bee = '''\nhee\ngee ''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-no-close-01.toml" {
  let source = "invalid = \"\"\"\n    this will fail\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-no-close-02.toml" {
  let source = "x=\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-no-close-03.toml" {
  let source = "not-closed= \"\"\"\ndiibaa\nblibae ete\neteta\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-no-close-04.toml" {
  let source = "bee = \"\"\"\nhee\ngee \"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-no-close-05.toml" {
  let source = "bee = \"\"\"\nhee\ngee\\\t \n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/multiline-quotes-01.toml" {
  let source = "a = \"\"\"6 quotes: \"\"\"\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-01.toml" {
  let source = "no-ending-quote = \"One time, at band camp\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-02.toml" {
  let source = "\"a-string\".must-be = \"closed\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-03.toml" {
  let source = "no-ending-quote = 'One time, at band camp\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-04.toml" {
  let source = "'a-string'.must-be = 'closed\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-05.toml" {
  let source = "# No newline at end\nno-ending-quote = \"One time, at band camp"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-06.toml" {
  let source = "# No newline at end\n\"a-string\".must-be = \"closed"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-07.toml" {
  let source = "# No newline at end\nno-ending-quote = 'One time, at band camp"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-08.toml" {
  let source = "# No newline at end\n'a-string'.must-be = 'closed"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-09.toml" {
  let source = "# Newlines are not allowed in \"-strings.\na = \"\n\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-close-10.toml" {
  let source = "# Newlines are not allowed in '-strings.\na = '\n'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-01.toml" {
  let source = "s = a\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-02.toml" {
  let source = "a = [a\"]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-03.toml" {
  let source = "s = a'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-04.toml" {
  let source = "a = [a']\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-05.toml" {
  let source = "a = a\"\"\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-06.toml" {
  let source = "a = [a\"\"\"]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-07.toml" {
  let source = "a = a'''\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/no-open-08.toml" {
  let source = "a = [a''']\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/text-after-string.toml" {
  let source = "string = \"Is there life after strings?\" No.\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/string/wrong-close.toml" {
  let source = "bad-ending-quote = \"double and single'\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-01.toml" {
  let source = "# First a.b.c defines a table: a.b.c = {z=9}\n#\n# Then we define a.b.c.t = \"str\" to add a str to the above table, making it:\n#\n#   a.b.c = {z=9, t=\"...\"}\n#\n# While this makes sense, logically, it was decided this is not valid TOML as\n# it's too confusing/convoluted.\n# \n# See: https://github.com/toml-lang/toml/issues/846\n#      https://github.com/toml-lang/toml/pull/859\n\n[a.b.c]\n  z = 9\n\n[a]\n  b.c.t = \"Using dotted keys to add to [a.b.c] after explicitly defining it above is not allowed\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-02.toml" {
  let source = "# This is the same issue as in injection-1.toml, except that nests one level\n# deeper. See that file for a more complete description.\n\n[a.b.c.d]\n  z = 9\n\n[a]\n  b.c.d.k.t = \"Using dotted keys to add to [a.b.c.d] after explicitly defining it above is not allowed\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-03.toml" {
  let source = "[[a.b]]\n\n[a]\nb.y = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-04.toml" {
  let source = "[dependencies.foo]\nversion = \"0.16\"\n\n[dependencies]\nlibc = \"0.2\"\n\n[dependencies]\nrand = \"0.3.14\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-05.toml" {
  let source = "a.b.c = 1\na.b = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-06.toml" {
  let source = "a = 1\na.b = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-07.toml" {
  let source = "a = {k1 = 1, k1.name = \"joe\"}\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/append-with-dotted-keys-08.toml" {
  let source = "[a.b.c]\nz = 9\n\n[[totally_unrelated]]\nx = 123\n\n[a]\nb.c.t = \"this should NOT be allowed\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-empty.toml" {
  let source = "[[]]\nname = \"Born to Run\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-implicit.toml" {
  let source = "# This test is a bit tricky. It should fail because the first use of\n# `[[albums.songs]]` without first declaring `albums` implies that `albums`\n# must be a table. The alternative would be quite weird. Namely, it wouldn't\n# comply with the TOML spec: \"Each double-bracketed sub-table will belong to \n# the most *recently* defined table element *above* it.\"\n#\n# This is in contrast to the *valid* test, table-array-implicit where\n# `[[albums.songs]]` works by itself, so long as `[[albums]]` isn't declared\n# later. (Although, `[albums]` could be.)\n[[albums.songs]]\nname = \"Glory Days\"\n\n[[albums]]\nname = \"Born in the USA\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-01.toml" {
  let source = "[[albums]\nname = \"Born to Run\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-02.toml" {
  let source = "[[closing-bracket.missing]\nblaa=2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-03.toml" {
  let source = "[[a\n[[b]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-04.toml" {
  let source = "[[a\nb = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-05.toml" {
  let source = "[[a]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/array-no-close-06.toml" {
  let source = "[[a]x\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/bare-invalid-character-01.toml" {
  let source = "[!]\nk = 123\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/bare-invalid-character-02.toml" {
  let source = "[bare!key]\nk = 123\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/dot.toml" {
  let source = "[.]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/dotdot.toml" {
  let source = "[..]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-01.toml" {
  let source = "[a]\nb = 1\n\n[a]\nc = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-02.toml" {
  let source = "[fruit]\ntype = \"apple\"\n\n[fruit.type]\napple = \"yes\"\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-03.toml" {
  let source = "[fruit]\napple.color = \"red\"\n\n[[fruit.apple]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-04.toml" {
  let source = "[fruit]\napple.color = \"red\"\n\n[fruit.apple] # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-05.toml" {
  let source = "[fruit]\napple.taste.sweet = true\n\n[fruit.apple.taste] # INVALID\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-06.toml" {
  let source = "[tbl]\n[[tbl]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-07.toml" {
  let source = "[[tbl]]\n[tbl]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-08.toml" {
  let source = "[a]\nb = { c = 2, d = {} }\n[a.b]\nc = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-09.toml" {
  let source = "[a]\nfoo=\"bar\"\n[a.b]\nfoo=\"bar\"\n[a]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-10.toml" {
  let source = "a = []\n[[a.b]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-11.toml" {
  let source = "[a]\n[a.b]\n[a.b]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-12.toml" {
  let source = "[a]\n[a.b]\nc = 1\n[a.b]\nc = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-13.toml" {
  let source = "[a.b]\n[a]\n[a.b]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/duplicate-key-14.toml" {
  let source = "[a.b]\nc = 1\n[a]\n[a.b]\nc = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/empty.toml" {
  let source = "[]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/empty-implicit-table.toml" {
  let source = "[naughty..naughty]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/equals-sign.toml" {
  let source = "[name=bad]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/llbrace.toml" {
  let source = "[ [table]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/multiline-key-01.toml" {
  let source = "[\"\"\"tbl\"\"\"]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/multiline-key-02.toml" {
  let source = "['''tbl''']\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/nested-brackets-close.toml" {
  let source = "[a]b]\nzyx = 42\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/nested-brackets-open.toml" {
  let source = "[a[b]\nzyx = 42\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/newline-01.toml" {
  let source = "[tbl\n]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/newline-02.toml" {
  let source = "[\"tbl\n\"]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/newline-03.toml" {
  let source = "[\"tbl\"\n]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/newline-04.toml" {
  let source = "[tbl.\n]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/newline-05.toml" {
  let source = "[tbl\n.sub]\nk = 1\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-01.toml" {
  let source = "[where will it end\nname = value\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-02.toml" {
  let source = "[closing-bracket.missingö\nblaa=2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-03.toml" {
  let source = "[\"where will it end]\nname = value\n\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-04.toml" {
  let source = "[\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-05.toml" {
  let source = "[fwfw.wafw\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-06.toml" {
  let source = "[a\n[b]\n[c\n[d]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-07.toml" {
  let source = "[']\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-08.toml" {
  let source = "[''']\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/no-close-09.toml" {
  let source = "[\"where will it end\"\"]\nname = value\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/overwrite-array-in-parent.toml" {
  let source = "[[parent-table.arr]]\n[parent-table]\nnot-arr = 1\narr = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/overwrite-bool-with-array.toml" {
  let source = "a=true\n[[a]]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/overwrite-with-deep-table.toml" {
  let source = "a=1\n[a.b.c.d]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/redefine-01.toml" {
  let source = "# Define b as int, and try to use it as a table: error\n[a]\nb = 1\n\n[a.b]\nc = 2\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/redefine-02.toml" {
  let source = "# Define t2 as a table via dotted key in [t1] block, and then redefine [t1.t2]\n[t1]\nt2.t3.v = 0\n[t1.t2]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/redefine-03.toml" {
  let source = "# Define t2.t3 as a table via dotted key in [t1] block, and then redefine [t1.t2.t3]\n[t1]\nt2.t3.v = 0\n[t1.t2.t3]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/rrbrace.toml" {
  let source = "[[table] ]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/super-twice.toml" {
  let source = "[a.b]\n[a]\n[a]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/text-after-table.toml" {
  let source = "[error] this shouldn't be here\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/trailing-dot.toml" {
  let source = "[a.]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/whitespace.toml" {
  let source = "[invalid key]\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "invalid/table/with-pound.toml" {
  let source = "[key#group]\nanswer = 42\n"
  let rejected = try {
    ignore(@edit.parse(source))
    false
  } catch {
    @edit.Diagnostic(@edit.InvalidToml, _, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "valid/array/array.toml" {
  let source = "ints = [1, 2, 3, ]\nfloats = [1.1, 2.1, 3.1]\nstrings = [\"a\", \"b\", \"c\"]\ndates = [\n\t1987-07-05T17:45:00Z,\n\t1979-05-27T07:32:00,\n\t2006-06-01,\n\t11:00:00,\n]\ncomments = [\n         1,\n         2, #this is ok\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/array-subtables.toml" {
  let source = "[[arr]]\n[arr.subtab]\nval=1\n\n[[arr]]\n[arr.subtab]\nval=2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/bool.toml" {
  let source = "a = [true, false]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/empty.toml" {
  let source = "thevoid = [[[[[]]]]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/hetergeneous.toml" {
  let source = "mixed = [[1, 2], [\"a\", \"b\"], [1.1, 2.1]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/mixed-int-array.toml" {
  let source = "arrays-and-ints =  [1, [\"Arrays are not integers.\"]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/mixed-int-float.toml" {
  let source = "ints-and-floats = [1, 1.1]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/mixed-int-string.toml" {
  let source = "strings-and-ints = [\"hi\", 42]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/mixed-string-table.toml" {
  let source = "contributors = [\n  \"Foo Bar <foo@example.com>\",\n  { name = \"Baz Qux\", email = \"bazqux@example.com\", url = \"https://example.com/bazqux\" }\n]\n\n# Start with a table as the first element. This tests a case that some libraries\n# might have where they will check if the first entry is a table/map/hash/assoc\n# array and then encode it as a table array. This was a reasonable thing to do\n# before TOML 1.0 since arrays could only contain one type, but now it's no\n# longer.\nmixed = [{k=\"a\"}, \"b\", 1]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/nested.toml" {
  let source = "nest = [[\"a\"], [\"b\"]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/nested-double.toml" {
  let source = "nest = [\n\t[\n\t\t[\"a\"],\n\t\t[1, 2, [3]]\n\t]\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/nested-inline-table.toml" {
  let source = "a = [ { b = {} } ]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/nospaces.toml" {
  let source = "ints = [1,2,3]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/open-parent-table.toml" {
  let source = "[[parent-table.arr]]\n[[parent-table.arr]]\n[parent-table]\nnot-arr = 1\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/string-quote-comma-01.toml" {
  let source = "title = [\n\"Client: \\\"XXXX\\\", Job: XXXX\",\n\"Code: XXXX\"\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/string-quote-comma-02.toml" {
  let source = "title = [ \" \\\", \",]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/string-with-comma-01.toml" {
  let source = "title = [\n\"Client: XXXX, Job: XXXX\",\n\"Code: XXXX\"\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/string-with-comma-02.toml" {
  let source = "title = [\n\"\"\"Client: XXXX,\nJob: XXXX\"\"\",\n\"Code: XXXX\"\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/strings.toml" {
  let source = "string_array = [ \"all\", 'strings', \"\"\"are the same\"\"\", '''type''']\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/table-array-string-backslash.toml" {
  let source = "foo = [ { bar=\"\\\"{{baz}}\\\"\"} ]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/array/trailing-comma.toml" {
  let source = "arr-1 = [1,]\n\narr-2 = [2,3,]\n\narr-3 = [4,\n]\n\narr-4 = [\n\t5,\n\t6,\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/bool/bool.toml" {
  let source = "t = true\nf = false\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/after-literal-no-ws.toml" {
  let source = "inf=inf#infinity\nnan=nan#not a number\ntrue=true#true\nfalse=false#false\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/at-eof.toml" {
  let source = "# This is a full-line comment\nkey = \"value\" # This is a comment at the end of a line\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/at-eof2.toml" {
  let source = "# This is a full-line comment\nkey = \"value\" # This is a comment at the end of a line\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/everywhere.toml" {
  let source = "# Top comment.\n  # Top comment.\n# Top comment.\n\n# [no-extraneous-groups-please]\n\n[group] # Comment\nanswer = 42 # Comment\n# no-extraneous-keys-please = 999\n# Inbetween comment.\nmore = [ # Comment\n  # What about multiple # comments?\n  # Can you handle it?\n  #\n          # Evil.\n# Evil.\n  42, 42, # Comments within arrays are fun.\n  # What about multiple # comments?\n  # Can you handle it?\n  #\n          # Evil.\n# Evil.\n# ] Did I fool you?\n] # Hopefully not.\n\n# Make sure the space between the datetime and \"#\" isn't lexed.\ndt = 1979-05-27T07:32:12-07:00  # c\nd = 1979-05-27 # Comment\n\n[[aot]] # Comment\nk = 98 # Comment\n[[aot]]# Comment\nk = 99# Comment\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/noeol.toml" {
  let source = "# single comment without any eol characters"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/nonascii.toml" {
  let source = "# ~  ÿ ퟿  ￿ 𐀀 􏿿\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/comment/tricky.toml" {
  let source = "[section]#attached comment\n#[notsection]\none = \"11\"#cmt\ntwo = \"22#\"\nthree = '#'\n\nfour = \"\"\"# no comment\n# nor this\n#also not comment\"\"\"#is_comment\n\nfive = 5.5#66\nsix = 6#7\n8 = \"eight\"\n#nine = 99\nten = 10e2#1\neleven = 1.11e1#23\n\n[\"hash#tag\"]\n\"#!\" = \"hash bang\"\narr3 = [ \"#\", '#', \"\"\"###\"\"\" ]\narr4 = [ 1,# 9, 9,\n2#,9\n,#9\n3#]\n,4]\narr5 = [[[[#[\"#\"],\n[\"#\"]]]]#]\n]\ntbl1 = { \"#\" = '}#'}#}}\n\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/datetime.toml" {
  let source = "space = 1987-07-05 17:45:00Z\n\n# ABNF is case-insensitive, both \"Z\" and \"z\" must be supported.\nlower = 1987-07-05t17:45:00z\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/edge.toml" {
  let source = "first-offset = 0001-01-01 00:00:00Z\nfirst-local  = 0001-01-01 00:00:00\nfirst-date   = 0001-01-01\n\nlast-offset = 9999-12-31 23:59:59Z\nlast-local  = 9999-12-31 23:59:59\nlast-date   = 9999-12-31\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/invalid-date-in-string.toml" {
  let source = "s = '2020-01-01x'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/leap-year.toml" {
  let source = "2000-datetime       = 2000-02-29 15:15:15Z\n2000-datetime-local = 2000-02-29 15:15:15\n2000-date           = 2000-02-29\n\n2024-datetime       = 2024-02-29 15:15:15Z\n2024-datetime-local = 2024-02-29 15:15:15\n2024-date           = 2024-02-29\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/local.toml" {
  let source = "local = 1987-07-05T17:45:00\nmilli = 1977-12-21T10:32:00.555\nspace = 1987-07-05 17:45:00\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/local-date.toml" {
  let source = "bestdayever = 1987-07-05\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/local-time.toml" {
  let source = "besttimeever = 17:45:00\nmilliseconds = 10:32:00.555\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/milliseconds.toml" {
  let source = "utc1  = 1987-07-05T17:45:56.123Z\nutc2  = 1987-07-05T17:45:56.6Z\nwita1 = 1987-07-05T17:45:56.123+08:00\nwita2 = 1987-07-05T17:45:56.6+08:00\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/datetime/timezone.toml" {
  let source = "utc  = 1987-07-05T17:45:56Z\npdt  = 1987-07-05T17:45:56-05:00\nnzst = 1987-07-05T17:45:56+12:00\nnzdt = 1987-07-05T17:45:56+13:00  # DST\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/empty-crlf.toml" {
  let source = "\r\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/empty-lf.toml" {
  let source = "\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/empty-nothing.toml" {
  let source = ""
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/empty-space.toml" {
  let source = " "
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/empty-tab.toml" {
  let source = "\t"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/example.toml" {
  let source = "best-day-ever = 1987-07-05T17:45:00Z\n\n[numtheory]\nboring = false\nperfection = [6, 28, 496]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/exponent.toml" {
  let source = "# Please keep exponent-upper.toml in sync with this.\n\nexp       = 3e2\npos-exp   = 3e+2\nneg-exp   = 3e-2\nzero-exp  = 3e0\nfrac      = 3.1e2\nneg       = -1e-1\nzero      = 0e2\nzero-plus = +0e2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/exponent-upper.toml" {
  let source = "# Both upper- and lower-case \"e\" is valid, so repeat the exponent.toml test with\n# upper-case.\nexp        = 3E2\npos-exp    = 3E+2\nneg-exp    = 3E-2\nzero-exp   = 3E0\nfrac       = 3.1E2\nneg        = -1E-1\nzero       = 0E2\nzero-plus = +0E2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/float.toml" {
  let source = "pi = 3.14\npospi = +3.14\nnegpi = -3.14\nzero-intpart = 0.123\nleading-zero-fractional = 0.0123\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/inf-and-nan.toml" {
  let source = "# We don't encode +nan and -nan back with the signs; many languages don't\n# support a sign on NaN (it doesn't really make much sense).\nnan = nan\nnan_neg = -nan\nnan_plus = +nan\ninfinity = inf\ninfinity_neg = -inf\ninfinity_plus = +inf\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/long.toml" {
  let source = "longpi = 3.141592653589793\nneglongpi = -3.141592653589793\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/max-int.toml" {
  let source = "# Maximum and minimum safe natural numbers.\nmax_float =  9_007_199_254_740_991.0\nmin_float = -9_007_199_254_740_991.0\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/underscore.toml" {
  let source = "before = 3_141.5927\nafter = 3141.592_7\nexponent = 3e1_4\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/float/zero.toml" {
  let source = "zero = 0.0\nsigned-pos = +0.0\nsigned-neg = -0.0\nexponent = 0e0\nexponent-two-0 = 0e00\nexponent-signed-pos = +0e0\nexponent-signed-neg = -0e0\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/implicit-and-explicit-after.toml" {
  let source = "[a.b.c]\nanswer = 42\n\n[a]\nbetter = 43\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/implicit-and-explicit-before.toml" {
  let source = "[a]\nbetter = 43\n\n[a.b.c]\nanswer = 42\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/implicit-groups.toml" {
  let source = "[a.b.c]\nanswer = 42\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/array-01.toml" {
  let source = "arr = [ {'a'= 1}, {'a'= 2} ]\n\npeople = [{first_name = \"Bruce\", last_name = \"Springsteen\"},\n          {first_name = \"Eric\", last_name = \"Clapton\"},\n          {first_name = \"Bob\", last_name = \"Seger\"}]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/array-02.toml" {
  let source = "# \"No newlines are allowed between the curly braces unless they are valid within\n# a value\"\n\na = { a = [\n]}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/array-03.toml" {
  let source = "b = { a = [\n\t\t1,\n\t\t2,\n\t], b = [\n\t\t3,\n\t\t4,\n\t]}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/bool.toml" {
  let source = "a = {a = true, b = false}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/empty.toml" {
  let source = "empty1 = {}\nempty2 = { }\nempty_in_array = [ { not_empty = 1 }, {} ]\nempty_in_array2 = [{},{not_empty=1}]\nmany_empty = [{},{},{}]\nnested_empty = {\"empty\"={}}\nwith_cmt ={            }#nothing here\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/end-in-bool.toml" {
  let source = "black = { python=\">3.6\", version=\">=18.9b0\", allow_prereleases=true }\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/inline-table.toml" {
  let source = "name        = { first = \"Tom\", last = \"Preston-Werner\" }\npoint       = { x = 1, y = 2 }\nsimple      = { a = 1 }\nstr-key     = { \"a\" = 1 }\ntable-array = [{ \"a\" = 1 }, { \"b\" = 2 }]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-01.toml" {
  let source = "a = {   a.b  =  1   }\nb = {   \"a\".\"b\"  =  1   }\nc = {   a   .   b  =  1   }\nd = {   'a'   .   \"b\"  =  1   }\ne = {a.b=1}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-02.toml" {
  let source = "many.dots.here.dot.dot.dot = {a.b.c = 1, a.b.d = 2}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-03.toml" {
  let source = "[tbl]\na.b.c = {d.e=1}\n\n[tbl.x]\na.b.c = {d.e=1}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-04.toml" {
  let source = "[[arr]]\nt = {a.b=1}\nT = {a.b=1}\n\n[[arr]]\nt = {a.b=2}\nT = {a.b=2}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-05.toml" {
  let source = "arr-1 = [{a.b = 1}]\narr-2 = [\"str\", {a.b = 1}]\n\narr-3 = [{a.b = 1}, {a.b = 2}]\narr-4 = [\"str\", {a.b = 1}, {a.b = 2}]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-06.toml" {
  let source = "top.dot.dot = [\n\t{dot.dot.dot = 1},\n\t{dot.dot.dot = 2},\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/key-dotted-07.toml" {
  let source = "arr = [\n\t{a.b = [{c.d = 1}]}\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/multiline.toml" {
  let source = "tbl_multiline = { a = 1, b = \"\"\"\nmultiline\n\"\"\", c = \"\"\"and yet\nanother line\"\"\", d = 4 }\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/nest.toml" {
  let source = "tbl_tbl_empty = { tbl_0 = {} }\ntbl_tbl_val   = { tbl_1 = { one = 1 } }\ntbl_arr_tbl   = { arr_tbl = [ { one = 1 } ] }\narr_tbl_tbl   = [ { tbl = { one = 1 } } ]\n\n# Array-of-array-of-table is interesting because it can only\n# be represented in inline form.\narr_arr_tbl_empty = [ [ {} ] ]\narr_arr_tbl_val = [ [ { one = 1 } ] ]\narr_arr_tbls  = [ [ { one = 1 }, { two = 2 } ] ]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/inline-table/spaces.toml" {
  let source = "# https://github.com/toml-lang/toml-test/issues/146\nclap-1 = { version = \"4\"  , features = [\"derive\", \"cargo\"] }\n\n# Contains some literal tabs!\nclap-2 = { version = \"4\"\t   \t,\t  \tfeatures = [   \"derive\" \t  ,  \t  \"cargo\"   ]   , nest   =   {  \t  \"a\"   =   'x'  , \t  'b'   = [ 1.5    ,   9.0  ]  }  }\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/float64-max.toml" {
  let source = "# Maximum and minimum safe float64 natural numbers. Mainly here for\n# -int-as-float.\nmax_int =  9_007_199_254_740_991\nmin_int = -9_007_199_254_740_991\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/integer.toml" {
  let source = "answer = 42\nposanswer = +42\nneganswer = -42\nzero = 0\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/literals.toml" {
  let source = "bin1 = 0b11010110\nbin2 = 0b1_0_1\n\noct1 = 0o01234567\noct2 = 0o755\noct3 = 0o7_6_5\n\nhex1 = 0xDEADBEEF\nhex2 = 0xdeadbeef\nhex3 = 0xdead_beef\nhex4 = 0x00987\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/long.toml" {
  let source = "# int64 \"should\" be supported, but is not mandatory. It's fine to skip this\n# test.\nint64-max     = 9223372036854775807\nint64-max-neg = -9223372036854775808\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/underscore.toml" {
  let source = "kilo = 1_000\nx = 1_1_1_1\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/integer/zero.toml" {
  let source = "d1 = 0\nd2 = +0\nd3 = -0\n\nh1 = 0x0\nh2 = 0x00\nh3 = 0x00000\n\no1 = 0o0\na2 = 0o00\na3 = 0o00000\n\nb1 = 0b0\nb2 = 0b00\nb3 = 0b00000\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/alphanum.toml" {
  let source = "alpha = \"a\"\n123 = \"num\"\n000111 = \"leading\"\n10e3 = \"false float\"\none1two2 = \"mixed\"\nwith-dash = \"dashed\"\nunder_score = \"___\"\n34-11 = 23\n\n[2018_10]\n001 = 1\n\n[a-a-a]\n_ = false\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/case-sensitive.toml" {
  let source = "sectioN = \"NN\"\n\n[section]\nname = \"lower\"\nNAME = \"upper\"\nName = \"capitalized\"\n\n[Section]\nname = \"different section!!\"\n\"μ\" = \"greek small letter mu\"\n\"Μ\" = \"greek capital letter MU\"\nM = \"latin letter M\"\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/dotted-01.toml" {
  let source = "name.first = \"Arthur\"\n\"name\".'last' = \"Dent\"\n\nmany.dots.dot.dot.dot = 42\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/dotted-02.toml" {
  let source = "# Note: this file contains literal tab characters.\n\n# Space are ignored, and key parts can be quoted.\ncount.a       = 1\ncount . b     = 2\n\"count\".\"c\"   = 3\n\"count\" . \"d\" = 4\n'count'.'e'   = 5\n'count' . 'f' = 6\n\"count\".'g'   = 7\n\"count\" . 'h' = 8\ncount.'i'     = 9\ncount \t.\t 'j'\t   = 10\n\"count\".k     = 11\n\"count\" . l   = 12\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/dotted-03.toml" {
  let source = "top.key = 1\n\n[tbl]\na.b.c = 42.666\n\n[a.few.dots]\npolka.dot = \"again?\"\npolka.dance-with = \"Dot\"\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/dotted-04.toml" {
  let source = "top.key = 1\n\n[[arr]]\na.b.c=1\na.b.d=2\n\n[[arr]]\na.b.c=3\na.b.d=4\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/dotted-empty.toml" {
  let source = "''.x = \"empty.x\"\nx.\"\" = \"x.empty\"\n[a]\n\"\".'' = \"empty.empty\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/empty-01.toml" {
  let source = "\"\" = \"blank\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/empty-02.toml" {
  let source = "'' = \"blank\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/empty-03.toml" {
  let source = "''=0\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/empty-04.toml" {
  let source = "tbl-1     = {\"\" = 1}\ntbl-2     = {\"\" = {\"\" = 1}}\narr-tbl-1 = [{\"\" = 2}]\narr-tbl-2 = [[{\"\" = 2}]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/equals-nospace.toml" {
  let source = "answer=42\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/escapes.toml" {
  let source = "\"\\n\" = \"newline\"\n\"\\b\" = \"bell\"\n\"\\u00c0\" = \"latin capital letter A with grave\"\n\"\\\"\" = \"just a quote\"\n\n[\"backsp\\b\\b\"]\n\n[\"\\\"quoted\\\"\"]\nquote = true\n\n[\"a.b\".\"\\u00c0\"]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/like-date.toml" {
  let source = "# '-' is a valid character in keys: make a key that looks like a date.\n2001-02-03   = 1\n\"2001-02-04\" = 2\n'2001-02-05' = 3\n\n# Also include datetime and time for good measure; these need to be quoted as\n# ':' isn't a valid bare key.\n\"2001-02-06T15:16:17+01:00\" = 4\n\"2001-02-07T15:16:17\"       = 5\n\"15:16:17\"                  = 6\n\n# Dotted keys\na.2001-02-08 = 7\na.2001-02-09.2001-02-10 = 8\n2001-02-11.a.2001-02-12 = 9\n\n# Table names\n[2002-01-02]\nk = 10\n\n[2002-01-02.2024-01-03]\nk = 11\n\n[[2002-01-04]]\nk = 12\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-01.toml" {
  let source = "1     = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-02.toml" {
  let source = "1.2   = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-03.toml" {
  let source = "0123  = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-04.toml" {
  let source = "01.23 = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-05.toml" {
  let source = "23.01 = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-06.toml" {
  let source = "-1    = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-07.toml" {
  let source = "-01   = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/numeric-08.toml" {
  let source = "1  = 'one'\n01 = 'zero one'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/quoted-dots.toml" {
  let source = "plain = 1\n\"with.dot\" = 2\n\n[plain_table]\nplain = 3\n\"with.dot\" = 4\n\n[table.withdot]\nplain = 5\n\"key.with.dots\" = 6\n\"escaped\\u002edot\" = 7\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/quoted-unicode.toml" {
  let source = "\n\"\\u0000\" = \"null\"\n'\\u0000' = \"different key\"\n\"\\u0008 \\u000c \\U00000041 \\u007f \\u0080 \\u00ff \\ud7ff \\ue000 \\uffff \\U00010000 \\U0010ffff\" = \"escaped key\"\n\n\"~  ÿ ퟿  ￿ 𐀀 􏿿\" = \"basic key\"\n'l ~  ÿ ퟿  ￿ 𐀀 􏿿' = \"literal key\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/space.toml" {
  let source = "# Keep whitespace inside quotes keys at all positions.\n\"a b\"   = 1\n\" c d \" = 2\n\"  much \t\t  whitespace  \t\\n  \\r\\n  \" = 3\n\n[ \" tbl \" ]\n\"\\ttab\\ttab\\t\" = \"tab\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/special-chars.toml" {
  let source = "\"=~!@$^&*()_+-`1234567890[]|/?><.,;:'=\" = 1\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/special-word.toml" {
  let source = "false = false\ntrue = 1\ninf = 100000000\nnan = \"ceci n'est pas un nombre\"\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/start.toml" {
  let source = "# Table and keys can start with any character; there is no requirement for it to\n# start with a letter.\n\n[-key]\n-key = 1\n\n[_key]\n_key = 2\n\n[1key]\n1key = 3\n\n[-]\n- = 4\n\n[_]\n_ = 5\n\n[1] \n1 = 6\n\n[---] \n--- = 7\n\n[___]\n___ = 8\n\n[111]\n111 = 9\n\n[inline]\n--- = {--- = 10, ___ = 11, 111 = 12}\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/key/zero.toml" {
  let source = "0=0\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/multibyte.toml" {
  let source = "# Test multibyte throughout\n\n# Tèƨƭ ƒïℓè ƒôř TÓM£\n# Óñℓ¥ ƭλïƨ ôñè ƭřïèƨ ƭô è₥úℓáƭè á TÓM£ ƒïℓè ωřïƭƭèñ β¥ á úƨèř ôƒ ƭλè ƙïñδ ôƒ ƥářƨèř ωřïƭèřƨ ƥřôβáβℓ¥ λáƭè\n\n['𝐭𝐛𝐥']\nstring = \"𝓼𝓽𝓻𝓲𝓷𝓰 - #\"          # \" 𝓼𝓽𝓻𝓲𝓷𝓰\n\t['𝐭𝐛𝐥'.sub]\n\t'𝕒𝕣𝕣𝕒𝕪' = [ \"] \", \" # \"]      # ] 𝓪𝓻𝓻𝓪𝔂\n\t'𝕒𝕣𝕣𝕒𝕪𝟚' = [ \"Tèƨƭ #11 ]ƥřôƲèδ ƭλáƭ\", \"Éжƥèřï₥èñƭ #9 ωáƨ á ƨúççèƨƨ\" ]\n\t# Ýôú δïδñ'ƭ ƭλïñƙ ïƭ'δ áƨ èáƨ¥ áƨ çλúçƙïñϱ ôúƭ ƭλè ℓáƨƭ #, δïδ ¥ôú?\n\tanother_test_string = \"§á₥è ƭλïñϱ, βúƭ ωïƭλ á ƨƭřïñϱ #\"\n\tescapes = \" Âñδ ωλèñ \\\"'ƨ ářè ïñ ƭλè ƨƭřïñϱ, áℓôñϱ ωïƭλ # \\\"\"   # \"áñδ çô₥₥èñƭƨ ářè ƭλèřè ƭôô\"\n\t# Tλïñϱƨ ωïℓℓ ϱèƭ λářδèř\n\t\t['𝐭𝐛𝐥'.sub.\"βïƭ#\"]\n\t\t\"ωλáƭ?\" = \"Ýôú δôñ'ƭ ƭλïñƙ ƨô₥è úƨèř ωôñ'ƭ δô ƭλáƭ?\"\n\t\tmulti_line_array = [\n\t\t\t\"]\",\n\t\t\t# ] Óλ ¥èƨ Ì δïδ\n\t\t\t]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/newline-crlf.toml" {
  let source = "os = \"DOS\"\r\nnewline = \"crlf\"\r\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/newline-lf.toml" {
  let source = "os = \"unix\"\nnewline = \"lf\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/array-0.toml" {
  let source = "integers = [ 1, 2, 3 ]\ncolors = [ \"red\", \"yellow\", \"green\" ]\nnested_arrays_of_ints = [ [ 1, 2 ], [3, 4, 5] ]\nnested_mixed_array = [ [ 1, 2 ], [\"a\", \"b\", \"c\"] ]\nstring_array = [ \"all\", 'strings', \"\"\"are the same\"\"\", '''type''' ]\n\n# Mixed-type arrays are allowed\nnumbers = [ 0.1, 0.2, 0.5, 1, 2, 5 ]\ncontributors = [\n  \"Foo Bar <foo@example.com>\",\n  { name = \"Baz Qux\", email = \"bazqux@example.com\", url = \"https://example.com/bazqux\" }\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/array-1.toml" {
  let source = "integers2 = [\n  1, 2, 3\n]\n\nintegers3 = [\n  1,\n  2, # this is ok\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/array-of-tables-0.toml" {
  let source = "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]  # empty table within the array\n\n[[products]]\nname = \"Nail\"\nsku = 284758393\n\ncolor = \"gray\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/array-of-tables-1.toml" {
  let source = "[[fruits]]\nname = \"apple\"\n\n[fruits.physical]  # subtable\ncolor = \"red\"\nshape = \"round\"\n\n[[fruits.varieties]]  # nested array of tables\nname = \"red delicious\"\n\n[[fruits.varieties]]\nname = \"granny smith\"\n\n\n[[fruits]]\nname = \"banana\"\n\n[[fruits.varieties]]\nname = \"plantain\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/array-of-tables-2.toml" {
  let source = "points = [ { x = 1, y = 2, z = 3 },\n           { x = 7, y = 8, z = 9 },\n           { x = 2, y = 4, z = 8 } ]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/boolean-0.toml" {
  let source = "bool1 = true\nbool2 = false\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/comment-0.toml" {
  let source = "# This is a full-line comment\nkey = \"value\"  # This is a comment at the end of a line\nanother = \"# This is not a comment\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/float-0.toml" {
  let source = "# fractional\nflt1 = +1.0\nflt2 = 3.1415\nflt3 = -0.01\n\n# exponent\nflt4 = 5e+22\nflt5 = 1e06\nflt6 = -2E-2\n\n# both\nflt7 = 6.626e-34\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/float-1.toml" {
  let source = "flt8 = 224_617.445_991_228\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/float-2.toml" {
  let source = "# infinity\nsf1 = inf  # positive infinity\nsf2 = +inf # positive infinity\nsf3 = -inf # negative infinity\n\n# not a number\nsf4 = nan  # actual sNaN/qNaN encoding is implementation-specific\nsf5 = +nan # same as `nan`\nsf6 = -nan # valid, actual encoding is implementation-specific\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/inline-table-0.toml" {
  let source = "name = { first = \"Tom\", last = \"Preston-Werner\" }\npoint = { x = 1, y = 2 }\nanimal = { type.name = \"pug\" }\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/inline-table-1.toml" {
  let source = "[name]\nfirst = \"Tom\"\nlast = \"Preston-Werner\"\n\n[point]\nx = 1\ny = 2\n\n[animal]\ntype.name = \"pug\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/inline-table-2.toml" {
  let source = "[product]\ntype = { name = \"Nail\" }\n# type.edible = false  # INVALID\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/inline-table-3.toml" {
  let source = "[product]\ntype.name = \"Nail\"\n# type = { edible = false }  # INVALID\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/integer-0.toml" {
  let source = "int1 = +99\nint2 = 42\nint3 = 0\nint4 = -17\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/integer-1.toml" {
  let source = "int5 = 1_000\nint6 = 5_349_221\nint7 = 53_49_221  # Indian number system grouping\nint8 = 1_2_3_4_5  # VALID but discouraged\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/integer-2.toml" {
  let source = "# hexadecimal with prefix `0x`\nhex1 = 0xDEADBEEF\nhex2 = 0xdeadbeef\nhex3 = 0xdead_beef\n\n# octal with prefix `0o`\noct1 = 0o01234567\noct2 = 0o755 # useful for Unix file permissions\n\n# binary with prefix `0b`\nbin1 = 0b11010110\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/key-value-pair-0.toml" {
  let source = "key = \"value\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-0.toml" {
  let source = "key = \"value\"\nbare_key = \"value\"\nbare-key = \"value\"\n1234 = \"value\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-1.toml" {
  let source = "\"127.0.0.1\" = \"value\"\n\"character encoding\" = \"value\"\n\"ʎǝʞ\" = \"value\"\n'key2' = \"value\"\n'quoted \"value\"' = \"value\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-3.toml" {
  let source = "name = \"Orange\"\nphysical.color = \"orange\"\nphysical.shape = \"round\"\nsite.\"google.com\" = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-4.toml" {
  let source = "fruit.name = \"banana\"     # this is best practice\nfruit. color = \"yellow\"    # same as fruit.color\nfruit . flavor = \"banana\"   # same as fruit.flavor\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-5.toml" {
  let source = "# VALID BUT DISCOURAGED\n\napple.type = \"fruit\"\norange.type = \"fruit\"\n\napple.skin = \"thin\"\norange.skin = \"thick\"\n\napple.color = \"red\"\norange.color = \"orange\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-6.toml" {
  let source = "# RECOMMENDED\n\napple.type = \"fruit\"\napple.skin = \"thin\"\napple.color = \"red\"\n\norange.type = \"fruit\"\norange.skin = \"thick\"\norange.color = \"orange\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/keys-7.toml" {
  let source = "3.14159 = \"pi\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/local-date-0.toml" {
  let source = "ld1 = 1979-05-27\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/local-date-time-0.toml" {
  let source = "ldt1 = 1979-05-27T07:32:00\nldt2 = 1979-05-27T00:32:00.999\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/local-time-0.toml" {
  let source = "lt1 = 07:32:00\nlt2 = 00:32:00.999\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/offset-date-time-0.toml" {
  let source = "odt1 = 1979-05-27T07:32:00Z\nodt2 = 1979-05-27T00:32:00-07:00\nodt3 = 1979-05-27T00:32:00.999-07:00\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/offset-date-time-1.toml" {
  let source = "odt4 = 1979-05-27 07:32:00Z\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-0.toml" {
  let source = "str = \"I'm a string. \\\"You can quote me\\\". Name\\tJos\\u00E9\\nLocation\\tSF.\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-1.toml" {
  let source = "str1 = \"\"\"\nRoses are red\nViolets are blue\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-2.toml" {
  let source = "# On a Unix system, the above multi-line string will most likely be the same as:\nstr2 = \"Roses are red\\nViolets are blue\"\n\n# On a Windows system, it will most likely be equivalent to:\nstr3 = \"Roses are red\\r\\nViolets are blue\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-3.toml" {
  let source = "# The following strings are byte-for-byte equivalent:\nstr1 = \"The quick brown fox jumps over the lazy dog.\"\n\nstr2 = \"\"\"\nThe quick brown \\\n\n\n  fox jumps over \\\n    the lazy dog.\"\"\"\n\nstr3 = \"\"\"\\\n       The quick brown \\\n       fox jumps over \\\n       the lazy dog.\\\n       \"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-4.toml" {
  let source = "str4 = \"\"\"Here are two quotation marks: \"\". Simple enough.\"\"\"\n# str5 = \"\"\"Here are three quotation marks: \"\"\".\"\"\"  # INVALID\nstr5 = \"\"\"Here are three quotation marks: \"\"\\\".\"\"\"\nstr6 = \"\"\"Here are fifteen quotation marks: \"\"\\\"\"\"\\\"\"\"\\\"\"\"\\\"\"\"\\\".\"\"\"\n\n# \"This,\" she said, \"is just a pointless statement.\"\nstr7 = \"\"\"\"This,\" she said, \"is just a pointless statement.\"\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-5.toml" {
  let source = "# What you see is what you get.\nwinpath  = 'C:\\Users\\nodejs\\templates'\nwinpath2 = '\\\\ServerX\\admin$\\system32\\'\nquoted   = 'Tom \"Dubs\" Preston-Werner'\nregex    = '<\\i\\c*\\s*>'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-6.toml" {
  let source = "regex2 = '''I [dw]on't need \\d{2} apples'''\nlines  = '''\nThe first newline is\ntrimmed in raw strings.\n   All other whitespace\n   is preserved.\n'''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/string-7.toml" {
  let source = "quot15 = '''Here are fifteen quotation marks: \"\"\"\"\"\"\"\"\"\"\"\"\"\"\"'''\n\n# apos15 = '''Here are fifteen apostrophes: ''''''''''''''''''  # INVALID\napos15 = \"Here are fifteen apostrophes: '''''''''''''''\"\n\n# 'That,' she said, 'is still pointless.'\nstr = ''''That,' she said, 'is still pointless.''''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-0.toml" {
  let source = "[table]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-1.toml" {
  let source = "[table-1]\nkey1 = \"some string\"\nkey2 = 123\n\n[table-2]\nkey1 = \"another string\"\nkey2 = 456\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-2.toml" {
  let source = "[dog.\"tater.man\"]\ntype.name = \"pug\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-3.toml" {
  let source = "[a.b.c]            # this is best practice\n[ d.e.f ]          # same as [d.e.f]\n[ g .  h  . i ]    # same as [g.h.i]\n[ j . \"ʞ\" . 'l' ]  # same as [j.\"ʞ\".'l']\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-4.toml" {
  let source = "# [x] you\n# [x.y] don't\n# [x.y.z] need these\n[x.y.z.w] # for this to work\n\n[x] # defining a super-table afterward is ok\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-5.toml" {
  let source = "# VALID BUT DISCOURAGED\n[fruit.apple]\n[animal]\n[fruit.orange]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-6.toml" {
  let source = "# RECOMMENDED\n[fruit.apple]\n[fruit.orange]\n[animal]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-7.toml" {
  let source = "# Top-level table begins.\nname = \"Fido\"\nbreed = \"pug\"\n\n# Top-level table ends.\n[owner]\nname = \"Regina Dogman\"\nmember_since = 1999-08-04\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-8.toml" {
  let source = "fruit.apple.color = \"red\"\n# Defines a table named fruit\n# Defines a table named fruit.apple\n\nfruit.apple.taste.sweet = true\n# Defines a table named fruit.apple.taste\n# fruit and fruit.apple were already created\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-1.0.0/table-9.toml" {
  let source = "[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n\n# [fruit.apple]  # INVALID\n# [fruit.apple.taste]  # INVALID\n\n[fruit.apple.texture]  # you can add sub-tables\nsmooth = true\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-example-1.toml" {
  let source = "# This is a TOML document. Boom.\n\ntitle = \"TOML Example\"\n\n[owner]\nname = \"Lance Uppercut\"\ndob = 1979-05-27T07:32:00-08:00 # First class dates? Why not?\n\n[database]\nserver = \"192.168.1.1\"\nports = [ 8001, 8001, 8002 ]\nconnection_max = 5000\nenabled = true\n\n[servers]\n\n  # You can indent as you please. Tabs or spaces. TOML don't care.\n  [servers.alpha]\n  ip = \"10.0.0.1\"\n  dc = \"eqdc10\"\n\n  [servers.beta]\n  ip = \"10.0.0.2\"\n  dc = \"eqdc10\"\n\n[clients]\ndata = [ [\"gamma\", \"delta\"], [1, 2] ]\n\n# Line breaks are OK when inside arrays\nhosts = [\n  \"alpha\",\n  \"omega\"\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/spec-example-1-compact.toml" {
  let source = "#Useless spaces eliminated.\ntitle=\"TOML Example\"\n[owner]\nname=\"Lance Uppercut\"\ndob=1979-05-27T07:32:00-08:00#First class dates\n[database]\nserver=\"192.168.1.1\"\nports=[8001,8001,8002]\nconnection_max=5000\nenabled=true\n[servers]\n[servers.alpha]\nip=\"10.0.0.1\"\ndc=\"eqdc10\"\n[servers.beta]\nip=\"10.0.0.2\"\ndc=\"eqdc10\"\n[clients]\ndata=[[\"gamma\",\"delta\"],[1,2]]\nhosts=[\n\"alpha\",\n\"omega\"\n]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/basic-escape-01.toml" {
  let source = "# Escape \"\ntest = \"\\\"one\\\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/basic-escape-02.toml" {
  let source = "# Escape \\ and then \"\ntest = \"\\\\\\\"one\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/basic-escape-03.toml" {
  let source = "# Escape \\ four times and then \"\ntest = \"\\\\\\\\\\\\\\\\\\\"one\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/empty.toml" {
  let source = "answer = \"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/ends-in-whitespace-escape.toml" {
  let source = "beee = \"\"\"\nheeee\ngeeee\\  \n\n\n      \"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/escape-tricky.toml" {
  let source = "end_esc = \"String does not end here\\\" but ends here\\\\\"\nlit_end_esc = 'String ends here\\'\n\nmultiline_unicode = \"\"\"\n\\u00a0\"\"\"\n\nmultiline_not_unicode = \"\"\"\n\\\\u0041\"\"\"\n\nmultiline_end_esc = \"\"\"When will it end? \\\"\"\"...\"\"\\\" should be here\\\"\"\"\"\n\nlit_multiline_not_unicode = '''\n\\u007f'''\n\nlit_multiline_end = '''There is no escape\\'''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/escaped-escape.toml" {
  let source = "answer = \"\\\\x64\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/escapes.toml" {
  let source = "backspace     = \"|\\b.\"\ntab           = \"|\\t.\"\nnewline       = \"|\\n.\"\nformfeed      = \"|\\f.\"\ncarriage      = \"|\\r.\"\nquote         = \"|\\\".\"\nbackslash     = \"|\\\\.\"\ndelete        = \"|\\u007F.\"\nunitseparator = \"|\\u001F.\"\n\n# \\u is escaped, so should NOT be interperted as a \\u escape.\nnotunicode1   = \"|\\\\u.\"\nnotunicode2   = \"|\\u005Cu.\"\nnotunicode3   = \"|\\\\u0075.\"\nnotunicode4   = \"|\\\\\\u0075.\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multibyte.toml" {
  let source = "# Test each multibyte length: 2, 3, and 4 bytes:\n# ɑ € 𐫱\n\nbasic    = \"ɑ € 𐫱 ɑ€𐫱\"\nraw      = 'ɑ € 𐫱 ɑ€𐫱'\nml-basic = \"\"\"ɑ € 𐫱 ɑ€𐫱\"\"\"\nml-raw   = '''ɑ € 𐫱 ɑ€𐫱'''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multibyte-escape.toml" {
  let source = "# Test each multibyte length: 2, 3, and 4 bytes:\n# ɑ € 𐫱\n\nbasic-1    = \"\\u0251 \\u20ac \\U00010AF1 \\u0251\\u20ac\\U00010AF1\"\nml-basic-1 = \"\"\"\\u0251 \\u20ac \\U00010AF1 \\u0251\\u20ac\\U00010AF1\"\"\"\n\n# Again, but only using \\U\nbasic-2    = \"\\U00000251 \\U000020ac \\U00010AF1 \\U00000251\\U000020ac\\U00010AF1\"\nml-basic-2 = \"\"\"\\U00000251 \\U000020ac \\U00010AF1 \\U00000251\\U000020ac\\U00010AF1\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multiline.toml" {
  let source = "# NOTE: this file includes some literal tab characters.\n\nequivalent_one = \"The quick brown fox jumps over the lazy dog.\"\nequivalent_two = \"\"\"\nThe quick brown \\\n\n\n  fox jumps over \\\n    the lazy dog.\"\"\"\n\nequivalent_three = \"\"\"\\\n       The quick brown \\\n       fox jumps over \\\n       the lazy dog.\\\n       \"\"\"\n\nwhitespace-after-bs = \"\"\"\\\n       The quick brown \\\n       fox jumps over \\   \n       the lazy dog.\\\t\n       \"\"\"\n\nno-space = \"\"\"a\\\n    b\"\"\"\n\n# Has tab character.\nkeep-ws-before = \"\"\"a   \t\\\n   b\"\"\"\n\nescape-bs-1 = \"\"\"a \\\\\nb\"\"\"\n\nescape-bs-2 = \"\"\"a \\\\\\\nb\"\"\"\n\nescape-bs-3 = \"\"\"a \\\\\\\\\n  b\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multiline-empty.toml" {
  let source = "empty-1 = \"\"\"\"\"\"\n\n# A newline immediately following the opening delimiter will be trimmed.\nempty-2 = \"\"\"\n\"\"\"\n\n# \\ at the end of line trims newlines as well; note that last \\ is followed by\n# two spaces, which are ignored.\nempty-3 = \"\"\"\\\n    \"\"\"\nempty-4 = \"\"\"\\\n   \\\n   \\  \n   \"\"\"\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multiline-escaped-crlf.toml" {
  let source = "# The following line should be an unescaped backslash followed by a Windows\r\n# newline sequence (\"\\r\\n\")\r\n0=\"\"\"\\\r\n\"\"\"\r\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/multiline-quotes.toml" {
  let source = "# Make sure that quotes inside multiline strings are allowed, including right\n# after the opening '''/\"\"\" and before the closing '''/\"\"\"\n\nlit_one = ''''one quote''''\nlit_two = '''''two quotes'''''\nlit_one_space = ''' 'one quote' '''\nlit_two_space = ''' ''two quotes'' '''\n\none = \"\"\"\"one quote\"\"\"\"\ntwo = \"\"\"\"\"two quotes\"\"\"\"\"\none_space = \"\"\" \"one quote\" \"\"\"\ntwo_space = \"\"\" \"\"two quotes\"\" \"\"\"\n\nmismatch1 = \"\"\"aaa'''bbb\"\"\"\nmismatch2 = '''aaa\"\"\"bbb'''\n\n# Three opening \"\"\", then one escaped \", then two \"\" (allowed), and then three\n# closing \"\"\"\nescaped = \"\"\"lol\\\"\"\"\"\"\"\n\nfive-quotes = \"\"\"\nClosing with five quotes\n\"\"\"\"\"\nfour-quotes = \"\"\"\nClosing with four quotes\n\"\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/nl.toml" {
  let source = "nl_mid = \"val\\nue\"\nnl_end = \"\"\"value\\n\"\"\"\n\nlit_nl_end = '''value\\n'''\nlit_nl_mid = 'val\\nue'\nlit_nl_uni = 'val\\ue'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/quoted-unicode.toml" {
  let source = "\nescaped_string = \"\\u0000 \\u0008 \\u000c \\U00000041 \\u007f \\u0080 \\u00ff \\ud7ff \\ue000 \\uffff \\U00010000 \\U0010ffff\"\nnot_escaped_string = '\\u0000 \\u0008 \\u000c \\U00000041 \\u007f \\u0080 \\u00ff \\ud7ff \\ue000 \\uffff \\U00010000 \\U0010ffff'\n\nbasic_string = \"~  ÿ ퟿  ￿ 𐀀 􏿿\"\nliteral_string = '~  ÿ ퟿  ￿ 𐀀 􏿿'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/raw.toml" {
  let source = "backspace = 'This string has a \\b backspace character.'\ntab = 'This string has a \\t tab character.'\nunescaped_tab = 'This string has an \t unescaped tab character.'\nnewline = 'This string has a \\n new line character.'\nformfeed = 'This string has a \\f form feed character.'\ncarriage = 'This string has a \\r carriage return character.'\nslash = 'This string has a \\/ slash character.'\nbackslash = 'This string has a \\\\ backslash character.'\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/raw-empty.toml" {
  let source = "empty = ''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/raw-multiline.toml" {
  let source = "# Single ' should be allowed.\noneline = '''This string has a ' quote character.'''\n\n# A newline immediately following the opening delimiter will be trimmed.\nfirstnl = '''\nThis string has a ' quote character.'''\n\n# All other whitespace and newline characters remain intact.\nmultiline = '''\nThis string\nhas ' a quote character\nand more than\none newline\nin it.'''\n\n# Tab character in literal string does not need to be escaped\nmultiline_with_tab = '''First line\n\t Followed by a tab'''\n\nthis-str-has-apostrophes='''' there's one already\n'' two more\n'''''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/simple.toml" {
  let source = "answer = \"You are not drinking enough whisky.\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/start-mb.toml" {
  let source = "# Start first line with a multibyte character.\n#\n# https://github.com/marzer/tomlplusplus/issues/190\ns1 = \"§\"\ns2 = '§'\ns3 = \"\"\"\\\n§\"\"\"\ns4 = \"\"\"\n§\"\"\"\ns5 = \"\"\"§\"\"\"\ns6 = '''\n§'''\ns7 = '''§'''\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/unicode-escape.toml" {
  let source = "delta-1 = \"\\u03B4\"\ndelta-2 = \"\\U000003B4\"\na       = \"\\u0061\"\nb       = \"\\u0062\"\nc       = \"\\U00000063\"\nnull-1  = \"\\u0000\"\nnull-2  = \"\\U00000000\"\n\nml-delta-1 = \"\"\"\\u03B4\"\"\"\nml-delta-2 = \"\"\"\\U000003B4\"\"\"\nml-a       = \"\"\"\\u0061\"\"\"\nml-b       = \"\"\"\\u0062\"\"\"\nml-c       = \"\"\"\\U00000063\"\"\"\nml-null-1  = \"\"\"\\u0000\"\"\"\nml-null-2  = \"\"\"\\U00000000\"\"\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/string/with-pound.toml" {
  let source = "pound = \"We see no # comments here.\"\npoundcomment = \"But there are # some comments here.\" # Did I # mess you up?\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-empty.toml" {
  let source = "[[a]]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-empty-name.toml" {
  let source = "# Silly thing to do, but valid.\n\n[['']]\na = 1\n[['']]\na = 2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-implicit.toml" {
  let source = "[[albums.songs]]\nname = \"Glory Days\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-implicit-and-explicit-after.toml" {
  let source = "[[a.b]]\nx = 1\n\n[a]\ny = 2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-many.toml" {
  let source = "[[people]]\nfirst_name = \"Bruce\"\nlast_name = \"Springsteen\"\n\n[[people]]\nfirst_name = \"Eric\"\nlast_name = \"Clapton\"\n\n[[people]]\nfirst_name = \"Bob\"\nlast_name = \"Seger\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-nest.toml" {
  let source = "[[albums]]\nname = \"Born to Run\"\n\n  [[albums.songs]]\n  name = \"Jungleland\"\n\n  [[albums.songs]]\n  name = \"Meeting Across the River\"\n\n[[albums]]\nname = \"Born in the USA\"\n  \n  [[albums.songs]]\n  name = \"Glory Days\"\n\n  [[albums.songs]]\n  name = \"Dancing in the Dark\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-one.toml" {
  let source = "[[people]]\nfirst_name = \"Bruce\"\nlast_name = \"Springsteen\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-table-array.toml" {
  let source = "[[a]]\n    [[a.b]]\n        [a.b.c]\n            d = \"val0\"\n    [[a.b]]\n        [a.b.c]\n            d = \"val1\"\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/array-within-dotted.toml" {
  let source = "[fruit]\napple.color = \"red\"\n\n[[fruit.apple.seeds]]\nsize = 2\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/empty.toml" {
  let source = "[a]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/empty-name.toml" {
  let source = "['']\nx = 1\n\n[\"\".a]\nx = 2\n\n[a.'']\nx = 3\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/keyword.toml" {
  let source = "[true]\n\n[false]\n\n[inf]\n\n[nan]\n\n\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/keyword-with-values.toml" {
  let source = "[true]\nk = 1\n\n[false]\nk = 2\n\n[inf]\nk = 3\n\n[nan]\nk = 4\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/names.toml" {
  let source = "[a.b.c]\n[a.\"b.c\"]\n[a.'d.e']\n[a.' x ']\n[ d.e.f ]\n[ g . h . i ]\n[ j . \"ʞ\" . 'l' ]\n\n[x.1.2]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/names-with-values.toml" {
  let source = "[a.b.c]\nkey = 1\n\n[a.\"b.c\"]\nkey = 2\n\n[a.'d.e']\nkey = 3\n\n[a.' x ']\nkey = 4\n\n[ d.e.f ]\nkey = 5\n\n[ g . h . i ]\nkey = 6\n\n[ j . \"ʞ\" . 'l' ]\nkey = 7\n\n[x.1.2]\nkey = 8\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/no-eol-01.toml" {
  let source = "# No newline at end of file.\n[table]"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/no-eol-02.toml" {
  let source = "# No newline at end of file.\n[table]\na=1"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/sub.toml" {
  let source = "[a]\nkey = 1\n\n# a.extend is a key inside the \"a\" table.\n[a.extend]\nkey = 2\n\n[a.extend.more]\nkey = 3\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/sub-empty.toml" {
  let source = "[a]\n[a.b]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/whitespace.toml" {
  let source = "[\"valid key\"]\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/with-literal-string.toml" {
  let source = "['a']\n[a.'\"b\"']\n[a.'\"b\"'.c]\nanswer = 42 \n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/with-pound.toml" {
  let source = "[\"key#group\"]\nanswer = 42\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/with-single-quotes.toml" {
  let source = "['a']\n[a.'b']\n[a.'b'.c]\nanswer = 42 \n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/without-super.toml" {
  let source = "# [x] you\n# [x.y] don't\n# [x.y.z] need these\n[x.y.z.w] # for this to work\n[x] # defining a super-table afterwards is ok\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

///|
test "valid/table/without-super-with-values.toml" {
  let source = "# [x] you\n# [x.y] don't\n# [x.y.z] need these\n[x.y.z.w] # for this to work\na = 1\nb = 2\n[x] # defining a super-table afterwards is ok\nc = 3\nd = 4\n"
  assert_eq(@edit.parse(source).encode(), source)
  let bytes = @utf8.encode(source)
  assert_eq(@edit.parse_bytes(bytes).encode_bytes(), bytes)
}

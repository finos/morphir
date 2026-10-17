///|
fn chapter(lines : Array[String]) -> Chapter raise {
  parse_chapter(lines.join("\n"))
}

///|
test "examples carry their expectation and the line of their fence" {
  let c = chapter([
    "# Core", "", "```scheme", "(+ 1 2)", ";; => 3", "```", "", "```scheme", "(car '())",
    ";; error: car", "```", "", "```scheme", "(define x 1)", "```", "", "```scheme notest",
    "(lambda …)", "```", "", "```mbt check", "test {}", "```",
  ])
  assert_eq(c.examples.map(e => (e.line, e.expect)), [
    (3, Value("3")),
    (8, Fails("car")),
    (13, Runs),
  ])
  assert_eq(c.examples[0].files, [("", "(+ 1 2)\n;; => 3")])
  assert_eq(c.skipped, 1)
}

///|
test "CRLF chapters give the same examples as LF chapters" {
  let lf = "```scheme\n(+ 1 2)\n;; => 3\n```\n"
  assert_eq(
    parse_chapter(lf).examples,
    parse_chapter(lf.replace_all(old="\n", new="\r\n")).examples,
  )
}

///|
test "consecutive file blocks form one project checked by the last block" {
  let c = chapter([
    "```scheme", ";; file: src/a.scm", "(define a 1)", "```", "text", "```scheme",
    ";; file: src/b.scm", "(define b 2)", "b", ";; => 2", "```", "```scheme", "(+ 1 1)",
    "```",
  ])
  assert_eq(c.examples.length(), 2)
  assert_eq(c.examples[0].files.map(f => f.0), ["src/a.scm", "src/b.scm"])
  assert_eq(c.examples[0].expect, Value("2"))
  assert_eq(c.examples[0].line, 1)
  assert_eq(c.examples[1].expect, Runs)
}

///|
test "malformed chapters are refused with their line" {
  for
    (lines, message) in [
      (["```scheme", "(+ 1 2)"], "line 1: unclosed code block"),
      (
        ["- item", "  ```scheme", "  (+ 1 2)", "  ```"],
        "line 2: indented scheme block",
      ),
      (
        [
          "```scheme", ";; file: a.scm", "1", ";; => 1", "```", "```scheme", ";; file: b.scm",
          "2", "```",
        ],
        "line 1: only the last file: block of a project may state an expectation",
      ),
    ] {
    let got = try {
      ignore(chapter(lines))
      ""
    } catch {
      DocError(m) => m
      e => raise e
    }
    assert_eq(got, message)
  }
}

///|
test "documented procedures are the first-column code of tables under Built-in procedures" {
  let c = chapter([
    "## Values", "| `x` | no |", "## Built-in procedures", "| Procedure | Meaning |",
    "|---|---|", "| `car` | first |", "| `string->symbol` | convert |", "## Errors",
    "| `y` | no |",
  ])
  assert_eq(c.procedures, ["car", "string->symbol"])
}

///|
test "a procedure documented twice is refused with both lines" {
  let got = try {
    ignore(
      chapter([
        "## Built-in procedures", "| Procedure | Meaning |", "|---|---|", "| `car` | first |",
        "| `cdr` | rest |", "### Errors", "| `car` or `cdr` fails | `Expected pair` |",
      ]),
    )
    ""
  } catch {
    DocError(m) => m
    e => raise e
  }
  assert_eq(got, "line 7: procedure `car` is already documented on line 4")
}

///|
test "scheme fences take no words except notest, and no other spelling" {
  for
    (lines, message) in [
      (
        ["```scheme title=x", "1", "```"],
        "line 1: unexpected text after `scheme`: `title=x`; use `scheme` or `scheme notest`",
      ),
      (
        ["text", "```scheme  notest extra", "x", "```"],
        "line 2: unexpected text after `scheme`: `notest extra`; use `scheme` or `scheme notest`",
      ),
      (
        ["```Scheme", "1", "```"],
        "line 1: scheme fence must be spelled `scheme`, found `Scheme`",
      ),
      (
        ["```SCHEME notest", "1", "```"],
        "line 1: scheme fence must be spelled `scheme`, found `SCHEME`",
      ),
    ] {
    let got = try {
      ignore(chapter(lines))
      ""
    } catch {
      DocError(m) => m
      e => raise e
    }
    assert_eq(got, message)
  }
}

///|
test "scheme fences indented with tabs or a mix of tabs and spaces are refused" {
  for
    (lines, message) in [
      (
        ["- item", "\t```scheme", "\t1", "\t```"],
        "line 2: indented scheme block",
      ),
      (["- item", " \t ```scheme", "1", "```"], "line 2: indented scheme block"),
      (["\t```Scheme", "1", "```"], "line 1: indented scheme block"),
    ] {
    let got = try {
      ignore(chapter(lines))
      ""
    } catch {
      DocError(m) => m
      e => raise e
    }
    assert_eq(got, message)
  }
}

///|
/// The message `parse_chapter` refuses `lines` with, or "" when it accepts them.
fn refusal(lines : Array[String]) -> String raise {
  try {
    ignore(chapter(lines))
    ""
  } catch {
    DocError(m) => m
    e => raise e
  }
}

///|
test "an expectation line that is not spelled exactly is refused with its line" {
  for
    near_miss in [
      ";=> 3", ";;=> 3", "; => 3", ";;error: x", ";; =>3", ";; =>", ";;; => 3", "; error: x",
    ] {
    assert_eq(
      refusal(["text", "```scheme", "(+ 1 2)", near_miss, "", "```"]),
      "line 4: an expectation must start with `;; => ` or `;; error: `, found `\{near_miss}`",
    )
  }
  // A near miss earlier in the block is an ordinary comment.
  assert_eq(refusal(["```scheme", ";=> 3", "(+ 1 2)", "```"]), "")
  // A comment without `=>` or `error:` is not an expectation, so the block only has to run.
  let c = chapter(["```scheme", "(+ 1 2)", ";; three", "```"])
  assert_eq(c.examples[0].expect, Runs)
  // In a project, the line is the line of the last block's expectation.
  assert_eq(
    refusal([
      "```scheme", ";; file: a.scm", "(define a 1)", "```", "```scheme", ";; file: b.scm",
      "a", ";=> 1", "```",
    ]),
    "line 8: an expectation must start with `;; => ` or `;; error: `, found `;=> 1`",
  )
}

///|
test "a closing fence indented by up to three spaces closes the block, as in CommonMark" {
  let c = chapter([
    "```scheme", "(+ 1 2)", ";; => 3", " ```", "text", "```scheme", "(+ 2 2)", ";; => 4",
    "   ```", "", "```scheme", "1", "    ```", "```",
  ])
  assert_eq(c.examples.map(e => (e.line, e.expect)), [
    (1, Value("3")),
    (6, Value("4")),
    (11, Runs),
  ])
  assert_eq(c.examples[0].files, [("", "(+ 1 2)\n;; => 3")])
  // Four spaces make the line part of the block.
  assert_eq(c.examples[2].files, [("", "1\n    ```")])
}

///|
test "scheme fences of tildes or more than three backticks are refused with their line" {
  for
    (lines, message) in [
      (
        ["~~~scheme", "1", "~~~"],
        "line 1: a scheme fence must be three backticks, found `~~~scheme`",
      ),
      (
        ["text", "````scheme", "1", "````"],
        "line 2: a scheme fence must be three backticks, found `````scheme`",
      ),
      (
        ["text", "", "~~~ scheme notest", "1", "~~~"],
        "line 3: a scheme fence must be three backticks, found `~~~ scheme notest`",
      ),
      (
        ["- item", "  ~~~Scheme", "1", "~~~"],
        "line 2: a scheme fence must be three backticks, found `  ~~~Scheme`",
      ),
    ] {
    assert_eq(refusal(lines), message)
  }
  // Other languages may use any fence.
  assert_eq(refusal(["~~~mbt", "x", "~~~", "````text", "y", "````"]), "")
}

///|
test "extra spaces between the scheme fence and notest are allowed" {
  let c = chapter(["```scheme   notest", "x", "```", "```scheme", "1", "```"])
  assert_eq(c.skipped, 1)
  assert_eq(c.examples.length(), 1)
}

///|
test "a scheme example quoted inside a longer or tilde fence is literal text, as in CommonMark" {
  let c = chapter([
    "````markdown", "```scheme", "(+ 1 2)", ";; => 3", "```", "````", "", "~~~text",
    "```scheme", "(car '())", "```", "~~~", "", "```scheme", "(+ 2 2)", ";; => 4",
    "```",
  ])
  assert_eq(c.examples.map(e => (e.line, e.expect)), [(14, Value("4"))])
}

///|
test "a closing fence needs the opening character, at least as many markers and no other text" {
  let c = chapter([
    "```text", "```scheme", "not an example", "````", "", "```scheme", "1", ";; => 1",
    "``` ", "", "  ~~~~", "```", "~~~", "~~~~~", "", "```scheme", "2", ";; => 2",
    "```",
  ])
  assert_eq(c.examples.map(e => (e.line, e.expect)), [
    (6, Value("1")),
    (16, Value("2")),
  ])
  assert_eq(c.examples[0].files, [("", "1\n;; => 1")])
}

///|
test "the file: lookahead skips scheme examples quoted inside another block" {
  let c = chapter([
    "```scheme", ";; file: src/a.scm", "(define (main) 1)", ";; => 1", "```", "",
    "````markdown", "```scheme", ";; file: src/b.scm", "```", "````",
  ])
  assert_eq(c.examples.map(e => (e.line, e.expect)), [(1, Value("1"))])
}

///|
fn score(query : String, text : String) -> Int32? {
  @palette.fuzzy(query, text).map(m => m.score)
}

///|
test "letters match in order, ignoring case and spaces in the query" {
  @expect.expect_all(s => {
    s
    .expect(
      @palette.fuzzy("api", "src/Shop/Api.elm").map(m => m.positions),
      label="word",
    )
    .to_equal(Some([9, 10, 11]))
    s.expect(score("ssa", "src/Shop/Api.elm"), label="initials").to_be_some()
    s.expect(score("new file", "New file…"), label="spaces").to_be_some()
    s
    .expect(score("ipa", "src/Shop/Api.elm"), label="out of order")
    .to_be_none()
    s.expect(score("", "anything"), label="empty").to_equal(Some(0))
    s.expect(score("longer", "long"), label="too long").to_be_none()
  })
}

///|
test "word starts, runs and short texts rank first" {
  let rank = fn(query : String, texts : Array[String]) {
    let scored = texts.filter_map(text => score(query, text).map(n => (n, text)))
    scored.sort_by((a, b) => b.0 - a.0)
    scored.map(pair => pair.1)
  }
  @expect.expect_all(s => {
    s
    .expect(
      rank("comp", ["Toggle panel", "Compile & run", "Compile"]),
      label="prefix",
    )
    .to_equal(["Compile", "Compile & run"])
    s
    .expect(
      rank("api", ["src/Shop/Rapid.elm", "src/Shop/Api.elm"]),
      label="word start",
    )
    .to_equal(["src/Shop/Api.elm", "src/Shop/Rapid.elm"])
    s
    .expect(rank("sp", ["switchPanel", "spaces"]), label="run")
    .to_equal(["spaces", "switchPanel"])
    s
    .expect(rank("tp", ["Set target path", "Toggle panel"]), label="initials")
    .to_equal(["Toggle panel", "Set target path"])
  })
}

///|
test "matched characters split into runs for drawing" {
  @expect.expect(@palette.segments("Compile", [0, 1, 2, 5])).to_equal([
    ("Com", true),
    ("pi", false),
    ("l", true),
    ("e", false),
  ])
}

///|
fn without_spaces(text : String) -> String {
  text
  .to_array()
  .filter(c => c != ' ')
  .fold(init="", (out, c) => out + c.to_string())
}

///|
/// Property: a string matched against itself scores at least as high as against any other string it matches.
test "a string scores highest against itself" {
  @expect.for_all((pair : (String, String)) => {
    let query = without_spaces(pair.0)
    let own = score(query, query)
    @expect.expect(own, label="self match").to_be_some()
    match score(query, pair.1) {
      Some(other) =>
        @expect.expect(other, label="other text").to_be_less_than_or_equal(
          own.unwrap_or(0),
        )
      None => ()
    }
  })
}

///|
/// Property: a subsequence of a text always matches it, and the positions spell the query.
test "a subsequence always matches" {
  @expect.for_all((pair : (String, Array[Bool])) => {
    let chars = pair.0.to_array()
    let keep = pair.1
    let picked : Array[String] = []
    for index, c in chars {
      if keep.get(index).unwrap_or(false) && c != ' ' {
        picked.push(c.to_string())
      }
    }
    let query = picked.join("")
    let found = @palette.fuzzy(query, pair.0)
    @expect.expect(found, label="matches").to_be_some()
    let positions = found.map(m => m.positions).unwrap_or([])
    let spelled = positions.map(p => chars[p].to_string()).join("")
    @expect.expect(spelled.to_lower(), label="spelled").to_equal(
      query.to_lower(),
    )
    @expect.expect(positions, label="in order").to_be_sorted()
  })
}

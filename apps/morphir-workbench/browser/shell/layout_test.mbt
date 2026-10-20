///|
let all : Array[@shell.View] = [Files, Models, Ideas, Generated]

///|
test "the default layout puts Generated on the right and opens only the left sidebar" {
  let layout = @shell.Layout::default()
  @expect.expect_all(s => {
    s.expect(layout.views_in(Primary, all)).to_equal([Files, Models, Ideas])
    s.expect(layout.views_in(Secondary, all)).to_equal([Generated])
    s.expect(layout.is_open(Primary)).to_equal(true)
    s.expect(layout.is_open(Secondary)).to_equal(false)
    s
    .expect(
      @shell.Layout::default(narrow=true).is_open(Primary),
      label="narrow",
    )
    .to_equal(false)
  })
}

///|
test "sidebars open and close independently" {
  let layout = @shell.Layout::default()
    .apply(Toggle(Secondary))
    .apply(Toggle(Primary))
  @expect.expect_all(s => {
    s.expect(layout.is_open(Primary)).to_equal(false)
    s.expect(layout.is_open(Secondary)).to_equal(true)
    s
    .expect(layout.apply(SetOpen(Primary, true)).is_open(Secondary))
    .to_equal(true)
  })
}

///|
test "widths stay in range for pointer and keyboard resizing" {
  let layout = @shell.Layout::default()
  @expect.expect_all(s => {
    s
    .expect(layout.apply(Resize(Primary, 20)).primary.width)
    .to_equal(@shell.min_width)
    s
    .expect(layout.apply(Resize(Primary, 9000)).primary.width)
    .to_equal(@shell.max_width)
    s
    .expect(layout.apply(Nudge(Secondary, @shell.step)).secondary.width)
    .to_equal(@shell.default_width + @shell.step)
    s
    .expect(layout.apply(Resize(Primary, 300)).secondary.width, label="other")
    .to_equal(@shell.default_width)
  })
}

///|
test "a moved view keeps its section state and has one place" {
  let layout = @shell.Layout::default()
    .apply(ToggleSection(Files))
    .apply(Move(Files, Secondary))
  @expect.expect_all(s => {
    s.expect(layout.views_in(Primary, all)).to_equal([Models, Ideas])
    s.expect(layout.views_in(Secondary, all)).to_equal([Generated, Files])
    s.expect(layout.section_open(Files)).to_equal(false)
    s
    .expect(layout.is_open(Secondary), label="target sidebar opens")
    .to_equal(true)
    s
    .expect(layout.placement.filter(entry => entry.0 == Files).length())
    .to_equal(1)
    s
    .expect(
      layout.apply(Move(Files, Primary)).views_in(Primary, all),
      label="moved back",
    )
    .to_equal([Models, Ideas, Files])
  })
}

///|
test "views follow what the workspace contains" {
  let layout = @shell.Layout::default()
  @expect.expect_all(s => {
    s.expect(layout.views_in(Primary, [Models])).to_equal([Models])
    s.expect(layout.views_in(Secondary, [Models])).to_equal([])
  })
}

///|
test "reveal opens the view's sidebar and section where they are" {
  let layout = @shell.Layout::default()
    .apply(ToggleSection(Generated))
    .apply(Reveal(Generated))
  @expect.expect_all(s => {
    s.expect(layout.is_open(Secondary)).to_equal(true)
    s.expect(layout.shows(Generated)).to_equal(true)
    s.expect(layout.side_of(Generated)).to_equal(Secondary)
  })
}

///|
test "sections open and close without changing the sidebar" {
  let layout = @shell.Layout::default().apply(ToggleSection(Models))
  @expect.expect_all(s => {
    s.expect(layout.section_open(Models)).to_equal(false)
    s.expect(layout.section_open(Files)).to_equal(true)
    s.expect(layout.is_open(Primary)).to_equal(true)
    s.expect(layout.shows(Models)).to_equal(false)
    s
    .expect(layout.apply(ToggleSection(Models)).section_open(Models))
    .to_equal(true)
  })
}

///|
test "a saved layout round trips and refuses unknown parts" {
  let layout = @shell.Layout::default()
    .apply(Move(Models, Secondary))
    .apply(ToggleSection(Files))
    .apply(Resize(Secondary, 333))
    .apply(Toggle(Secondary))
  let fallback = @shell.Layout::default()
  let odd : Json = {
    "primary": { "open": false, "width": 9000 },
    "placement": [
      { "view": "unknown", "side": "secondary" },
      { "view": "files", "side": "middle" },
      { "view": "ideas", "side": "secondary" },
      { "view": "ideas", "side": "primary" },
    ],
    "collapsed": ["models", "models", "nope"],
  }
  let decoded = @shell.Layout::from_json(odd, fallback)
  @expect.expect_all(s => {
    s
    .expect(@shell.Layout::from_json(layout.to_json(), fallback))
    .to_equal(layout)
    s
    .expect(
      @shell.Layout::from_json(Json::null(), fallback),
      label="not a layout",
    )
    .to_equal(fallback)
    s
    .expect(decoded.primary)
    .to_equal({ open: false, width: @shell.max_width, })
    s.expect(decoded.secondary).to_equal(fallback.secondary)
    s.expect(decoded.side_of(Ideas)).to_equal(Secondary)
    s.expect(decoded.side_of(Files)).to_equal(Primary)
    s.expect(decoded.collapsed).to_equal([Models])
    s.expect(decoded.placement.length()).to_equal(4)
  })
}

///|
test "sides and views have stable ids" {
  @expect.expect_all(s => {
    s.expect(@shell.Side::from_id("secondary")).to_equal(Some(Secondary))
    s.expect(@shell.View::from_id("generated")).to_equal(Some(Generated))
    s.expect(@shell.View::from_id("Generated")).to_equal(None)
    s.expect(@shell.Side::Primary.other()).to_equal(Secondary)
    s.expect(@shell.Side::Secondary.label()).to_equal("Right sidebar")
  })
}

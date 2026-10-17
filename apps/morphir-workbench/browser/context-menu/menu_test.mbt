///|
fn item(
  label : String,
  enabled~ : Bool = true,
  group_start~ : Bool = false,
  section~ : String = "",
) -> @context_menu.Item {
  { label, shortcut: None, enabled, reason: "", group_start, section, }
}

///|
test "menu keys move, wrap, choose and close" {
  let key = fn(name : String) { @keys.Chord::plain(name) }
  @expect.expect_all(s => {
    s
    .expect(@context_menu.key_result(4, 3, key("ArrowDown")), label="wrap down")
    .to_equal(MoveTo(0))
    s
    .expect(@context_menu.key_result(4, 0, key("ArrowUp")), label="wrap up")
    .to_equal(MoveTo(3))
    s
    .expect(@context_menu.key_result(4, 2, key("Home")), label="home")
    .to_equal(MoveTo(0))
    s
    .expect(@context_menu.key_result(4, 1, key("End")), label="end")
    .to_equal(MoveTo(3))
    s
    .expect(@context_menu.key_result(4, 1, key("Enter")), label="enter")
    .to_equal(Choose(1))
    s
    .expect(@context_menu.key_result(4, 1, key(" ")), label="space")
    .to_equal(Choose(1))
    s
    .expect(@context_menu.key_result(4, 1, key("Escape")), label="escape")
    .to_equal(Close)
    s
    .expect(@context_menu.key_result(4, 1, key("Tab")), label="tab")
    .to_equal(Close)
    s
    .expect(@context_menu.key_result(0, 0, key("ArrowDown")), label="empty")
    .to_equal(Ignore)
    s
    .expect(@context_menu.key_result(4, 1, key("x")), label="other")
    .to_equal(Ignore)
  })
}

///|
test "a menu's height counts items, separators and headings" {
  let items = [
    item("Open"),
    item("Copy", group_start=true),
    item("Pricing", group_start=true, section="New from sample"),
    item("Records", section="New from sample"),
  ]
  @expect.expect_all(s => {
    s
    .expect(@context_menu.height(items), label="height")
    .to_equal(8 + 4 * 28 + 2 * 9 + 24)
    s
    .expect(
      @context_menu.first_enabled([item("a", enabled=false), item("b")]),
      label="first enabled",
    )
    .to_equal(1)
  })
}

///|
/// Property: a menu that fits the viewport is placed entirely inside it, wherever it opens.
test "a menu that fits is always inside the viewport" {
  @expect.for_all((point : (UInt32, UInt32)) => {
    let x = (point.0 % 1200).reinterpret_as_int()
    let y = (point.1 % 900).reinterpret_as_int()
    let (left, top) = @context_menu.place(x, y, 300, 1000, 700)
    @expect.expect(left >= 4 && left + @context_menu.width <= 996, label="x").to_be_true()
    @expect.expect(top >= 4 && top + 300 <= 696, label="y").to_be_true()
  })
}

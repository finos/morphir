///|
fn event(
  key : String,
  ctrl~ : Bool = false,
  meta~ : Bool = false,
  shift~ : Bool = false,
  mac~ : Bool = false,
) -> @keys.Chord {
  @keys.Chord::from_event(key, ctrl~, meta~, shift~, alt=false, mac~)
}

///|
let typing : @keys.Context = { editing: true, in_tree: false, }

///|
let on_row : @keys.Context = { editing: false, in_tree: true, }

///|
test "the primary modifier is Command on macOS and Control elsewhere" {
  let keymap = @keys.keymap()
  @expect.expect_all(s => {
    s
    .expect(
      @keys.resolve(keymap, event("p", meta=true, mac=true), typing),
      label="⌘P on macOS",
    )
    .to_equal(Some(GoToFile))
    s
    .expect(
      @keys.resolve(keymap, event("p", ctrl=true), typing),
      label="Ctrl+P",
    )
    .to_equal(Some(GoToFile))
    s
    .expect(
      @keys.resolve(keymap, event("p", ctrl=true, mac=true), typing),
      label="Control+P on macOS",
    )
    .to_equal(None)
    s
    .expect(
      @keys.resolve(keymap, event("P", ctrl=true, shift=true), typing),
      label="Ctrl+Shift+P",
    )
    .to_equal(Some(ShowCommands))
    s
    .expect(
      @keys.resolve(keymap, event("Enter", meta=true, mac=true), typing),
      label="⌘Enter",
    )
    .to_equal(Some(Compile))
  })
}

///|
test "tree shortcuts work on a row and never while typing" {
  let keymap = @keys.keymap()
  let in_rename : @keys.Context = { editing: true, in_tree: true, }
  @expect.expect_all(s => {
    s
    .expect(@keys.resolve(keymap, event("F2"), on_row), label="F2 on a row")
    .to_equal(Some(RenameFile))
    s
    .expect(@keys.resolve(keymap, event("F2"), in_rename), label="F2 typing")
    .to_equal(None)
    s
    .expect(@keys.resolve(keymap, event("F2"), typing), label="F2 in editor")
    .to_equal(None)
    s
    .expect(@keys.resolve(keymap, event("Delete"), on_row), label="Delete")
    .to_equal(Some(DeleteFile))
    s
    .expect(
      @keys.resolve(keymap, event("Backspace", meta=true, mac=true), on_row),
      label="⌘⌫",
    )
    .to_equal(Some(DeleteFile))
    s
    .expect(
      @keys.resolve(keymap, event("F10", shift=true), on_row),
      label="Shift+F10",
    )
    .to_equal(Some(ContextMenu))
    s
    .expect(@keys.resolve(keymap, event("Apps"), on_row), label="old menu key")
    .to_equal(Some(ContextMenu))
    s
    .expect(@keys.resolve(keymap, event("F1"), typing), label="F1 anywhere")
    .to_equal(Some(ShowCommands))
  })
}

///|
test "labels follow the platform and aria-keyshortcuts syntax" {
  let palette = @keys.shortcut(@keys.keymap(), ShowCommands, mac=false).unwrap()
  let delete = @keys.shortcut(@keys.keymap(), DeleteFile, mac=false).unwrap()
  let mac_delete = @keys.shortcut(@keys.keymap(), DeleteFile, mac=true).unwrap()
  let compile = @keys.shortcut(@keys.keymap(), Compile, mac=false).unwrap()
  @expect.expect_all(s => {
    s.expect(palette.label(mac=true), label="mac palette").to_equal("⇧⌘P")
    s
    .expect(palette.label(mac=false), label="pc palette")
    .to_equal("Ctrl+Shift+P")
    s
    .expect(palette.aria(mac=false), label="aria pc")
    .to_equal("Control+Shift+P")
    s.expect(palette.aria(mac=true), label="aria mac").to_equal("Meta+Shift+P")
    s.expect(delete.label(mac=false), label="delete").to_equal("Delete")
    s.expect(mac_delete.label(mac=true), label="mac delete").to_equal("⌘⌫")
    s.expect(compile.label(mac=true), label="mac compile").to_equal("⌘↩")
    s
    .expect(compile.label(mac=false), label="pc compile")
    .to_equal("Ctrl+Enter")
    s
    .expect(@keys.shortcut(@keys.keymap(), NewFile, mac=false), label="unbound")
    .to_equal(None)
  })
}

///|
test "events normalize to one spelling" {
  @expect.expect_all(s => {
    s.expect(event("a").key, label="letter").to_equal("A")
    s.expect(event(" ").key, label="space").to_equal("Space")
    s.expect(event("Esc").key, label="esc").to_equal("Escape")
    s.expect(event("a").is_character(), label="a types").to_be_true()
    s
    .expect(event("A", shift=true).is_character(), label="shift types")
    .to_be_true()
    s
    .expect(event("a", ctrl=true).is_character(), label="ctrl does not")
    .to_be_false()
    s.expect(event("F2").is_character(), label="F2 does not").to_be_false()
    s.expect(event(" ").is_character(), label="space does not").to_be_false()
  })
}

///|
/// Property: each chord runs one command, so the order of the keymap never decides a shortcut.
test "each chord has one command" {
  let keymap = @keys.keymap()
  for i, a in keymap {
    for j, b in keymap {
      if i < j {
        @expect.expect(a.chord, label="bindings \{i} and \{j}").to_not_equal(
          b.chord,
        )
      }
    }
  }
}

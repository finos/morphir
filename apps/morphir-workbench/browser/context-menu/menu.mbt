// One context menu for the workbench: the project explorer and the generated files use it. The owner keeps which
// menu is open and what each entry does; this package places the menu, moves through it with the keyboard and draws
// it with its fixed item heights.

///|
/// One entry of a context menu.
pub(all) struct Item {
  label : String
  /// The command whose shortcut the entry shows.
  shortcut : @keys.CommandId?
  enabled : Bool
  /// Why the entry is disabled.
  reason : String
  /// A separator comes before the entry.
  group_start : Bool
  /// The heading of the entry's section; a heading shows where the section starts.
  section : String
} derive(Eq, Debug)

///|
pub let width : Int32 = 240

///|
let item_height = 28

///|
let separator_height = 9

///|
let heading_height = 24

///|
let padding = 4

///|
let viewport_margin = 4

///|
/// True when the entry at `index` starts a section that has a heading.
pub fn starts_section(items : Array[Item], index : Int32) -> Bool {
  match items.get(index) {
    Some({ section, .. }) if section != "" =>
      index == 0 || items[index - 1].section != section
    _ => false
  }
}

///|
/// The height of a menu in CSS pixels. The menu styles fix each item, separator and heading height, so this is exact.
pub fn height(items : Array[Item]) -> Int32 {
  let mut separators = 0
  let mut headings = 0
  for index, item in items {
    if item.group_start && index > 0 {
      separators += 1
    }
    if starts_section(items, index) {
      headings += 1
    }
  }
  padding * 2 +
  items.length() * item_height +
  separators * separator_height +
  headings * heading_height
}

///|
fn at_least(low : Int32, value : Int32) -> Int32 {
  if value < low {
    low
  } else {
    value
  }
}

///|
fn at_most(value : Int32, high : Int32) -> Int32 {
  if value > high {
    high
  } else {
    value
  }
}

///|
/// The top-left corner of a menu opened at a point, kept inside the viewport: it shifts left at the right edge and
/// opens upward when there is no room below.
pub fn place(
  x : Int32,
  y : Int32,
  height : Int32,
  viewport_width : Int32,
  viewport_height : Int32,
) -> (Int32, Int32) {
  let left = at_least(
    viewport_margin,
    at_most(x, viewport_width - width - viewport_margin),
  )
  let below = y + height <= viewport_height - viewport_margin
  let wanted = if below || y - height < viewport_margin {
    y
  } else {
    y - height
  }
  let top = at_least(
    viewport_margin,
    at_most(wanted, viewport_height - height - viewport_margin),
  )
  (left, top)
}

///|
/// The entry that takes the focus when a menu opens: the first enabled one.
pub fn first_enabled(items : Array[Item]) -> Int32 {
  items.search_by(item => item.enabled).unwrap_or(0)
}

///|
/// What a key in an open menu does.
pub(all) enum KeyResult {
  MoveTo(Int32)
  Choose(Int32)
  Close
  Ignore
} derive(Eq, Debug)

///|
/// The WAI-ARIA menu keys: arrows move and wrap, Home and End jump, Enter and Space choose, Escape and Tab close.
pub fn key_result(
  count : Int32,
  index : Int32,
  chord : @keys.Chord,
) -> KeyResult {
  guard count > 0 && chord.is_typing() else { return Ignore }
  let wrap = fn(i : Int32) { (i % count + count) % count }
  match chord.key {
    "ArrowDown" => MoveTo(wrap(index + 1))
    "ArrowUp" => MoveTo(wrap(index - 1))
    "Home" => MoveTo(0)
    "End" => MoveTo(count - 1)
    "Enter" | "Space" => Choose(index)
    "Escape" | "Tab" => Close
    _ => Ignore
  }
}

///|
/// The DOM id of an entry, for focus.
pub fn item_id(prefix : String, index : Int32) -> String {
  prefix + "-" + index.to_string()
}

///|
pub(all) struct Props {
  items : Array[Item]
  left : Int32
  top : Int32
  /// The entry with the focus.
  index : Int32
  /// The menu's accessible name, such as `Actions for Main.elm`.
  label : String
  /// The prefix of the entries' DOM ids.
  id_prefix : String
  mac : Bool
}

///|
fn chord_of(event : @dom.KeyboardEvent, mac : Bool) -> @keys.Chord {
  @keys.Chord::from_event(
    event.key(),
    ctrl=event.ctrl_key(),
    meta=event.meta_key(),
    shift=event.shift_key(),
    alt=event.alt_key(),
    mac~,
  )
}

///|
/// The menu on a transparent backdrop that closes it on an outside click or right-click. `on_choose` gets the index
/// of a clicked entry and `on_key` each menu key; the owner checks that the entry is enabled.
pub fn view(
  props : Props,
  on_choose~ : (Int32) -> @cmd.Cmd,
  on_key~ : (@keys.Chord) -> @cmd.Cmd,
  on_close~ : @cmd.Cmd,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for index, item in props.items {
    if item.group_start && index > 0 {
      rows.push(
        @html.div(
          class="context-menu-separator",
          attrs=@html.Attrs::build().role("separator"),
          "",
        ),
      )
    }
    if starts_section(props.items, index) {
      // The heading is visual; each item's accessible name carries its section.
      rows.push(
        @html.div(
          class="context-menu-heading",
          attrs=@html.Attrs::build().role("presentation").aria_hidden("true"),
          item.section,
        ),
      )
    }
    let chord = match item.shortcut {
      Some(command) => @keys.shortcut(@keys.keymap(), command, mac=props.mac)
      None => None
    }
    let attrs = @html.Attrs::build()
      .role("menuitem")
      .aria_label(
        if item.section == "" {
          item.label
        } else {
          item.section + ": " + item.label
        },
      )
      .tabindex(-1)
      .aria_disabled((!item.enabled).to_string())
    let attrs = match chord {
      Some(chord) => attrs.aria_keyshortcuts(chord.aria(mac=props.mac))
      None => attrs
    }
    rows.push(
      @html.button(
        id=item_id(props.id_prefix, index),
        class=if index == props.index {
          "context-menu-item current"
        } else {
          "context-menu-item"
        },
        title=item.reason,
        attrs~,
        on_click=on_choose(index),
        [
          @html.span(class="context-menu-label", item.label),
          match chord {
            Some(chord) =>
              @html.kbd(class="shortcut", chord.label(mac=props.mac))
            None => @html.nothing
          },
        ],
      ),
    )
  }
  @html.div(
    class="menu-layer",
    // Right-clicks inside the layer (the backdrop or the menu) never reach the page behind it, which may open its own
    // menu at the pointer, and never show the browser's menu.
    attrs=@html.Attrs::build().on_contextmenu(event => {
      event.prevent_default()
      event.stop_propagation()
      @cmd.none
    }),
    [
      @html.div(
        class="menu-backdrop",
        attrs=@html.Attrs::build()
          .on_click(_ => on_close)
          // A right-click outside the menu only closes it.
          .on_contextmenu(event => {
            event.prevent_default()
            on_close
          }),
        "",
      ),
      @html.div(
        class="context-menu",
        style=[
          "left:" + props.left.to_string() + "px",
          "top:" + props.top.to_string() + "px",
          "width:" + width.to_string() + "px",
        ],
        attrs=@html.Attrs::build()
          .role("menu")
          .aria_label(props.label)
          .on_keydown(event => {
            let chord = chord_of(event, props.mac)
            match chord.key {
              "ArrowDown"
              | "ArrowUp"
              | "Home"
              | "End"
              | "Enter"
              | "Space"
              | "Escape" => {
                event.prevent_default()
                event.stop_propagation()
                on_key(chord)
              }
              "Tab" => {
                event.prevent_default()
                on_key(chord)
              }
              _ => @cmd.none
            }
          }),
        rows,
      ),
    ],
  )
}

///|
pub extend Item with Eq::{not_equal, equal}

///|
pub extend Item with @debug.Debug::{to_repr}

///|
pub extend KeyResult with Eq::{not_equal, equal}

///|
pub extend KeyResult with @debug.Debug::{to_repr}

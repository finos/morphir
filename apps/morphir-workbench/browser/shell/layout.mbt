// The workbench shell's layout: two sidebars that open, close and resize on their own, and the explorer views
// stacked in them. Each view has one place, and each section keeps its own open state, whichever sidebar holds it.
// These are pure decisions; the views and the workbench apply them.

///|
/// A sidebar: the primary one on the left and the secondary one on the right.
pub(all) enum Side {
  Primary
  Secondary
} derive(Eq, Debug)

///|
pub extend Side with Eq::{equal, not_equal}

///|
pub extend Side with @debug.Debug::{to_repr}

///|
/// An explorer view: a navigable presentation of one kind of workspace content.
pub(all) enum View {
  Files
  Models
  Generated
  Ideas
} derive(Eq, Debug)

///|
pub extend View with Eq::{equal, not_equal}

///|
pub extend View with @debug.Debug::{to_repr}

///|
/// One sidebar's visibility and width in CSS pixels.
pub(all) struct Sidebar {
  open : Bool
  width : Int32
} derive(Eq, Debug)

///|
pub extend Sidebar with Eq::{equal, not_equal}

///|
pub extend Sidebar with @debug.Debug::{to_repr}

///|
/// Where each view is, in section order, which sections are collapsed, and both sidebars.
pub(all) struct Layout {
  primary : Sidebar
  secondary : Sidebar
  placement : Array[(View, Side)]
  collapsed : Array[View]
} derive(Eq, Debug)

///|
pub extend Layout with Eq::{equal, not_equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
/// A change to the layout, from a button, a key, a pointer or the command palette.
pub(all) enum Action {
  Toggle(Side)
  SetOpen(Side, Bool)
  /// A new width in CSS pixels; it is kept between `min_width` and `max_width`.
  Resize(Side, Int32)
  /// A change of width by this many pixels.
  Nudge(Side, Int32)
  Move(View, Side)
  ToggleSection(View)
  /// Opens the view's sidebar and its section, where they are now.
  Reveal(View)
  /// A pointer drag on the sidebar's edge ended; the width is final.
  EndResize(Side)
} derive(Eq, Debug)

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
pub let min_width : Int32 = 200

///|
pub let max_width : Int32 = 560

///|
pub let default_width : Int32 = 280

///|
/// The keyboard resize step in CSS pixels.
pub let step : Int32 = 16

///|
/// At this window width and below, sidebars cover the documents and start closed.
pub let narrow_width : Int32 = 900

///|
pub fn Side::other(self : Side) -> Side {
  match self {
    Primary => Secondary
    Secondary => Primary
  }
}

///|
pub fn Side::id(self : Side) -> String {
  match self {
    Primary => "primary"
    Secondary => "secondary"
  }
}

///|
/// The sidebar's accessible name.
pub fn Side::label(self : Side) -> String {
  match self {
    Primary => "Left sidebar"
    Secondary => "Right sidebar"
  }
}

///|
/// The place a view moves to, as a menu or the palette names it.
pub fn Side::destination(self : Side) -> String {
  match self {
    Primary => "the left sidebar"
    Secondary => "the right sidebar"
  }
}

///|
pub fn Side::from_id(id : String) -> Side? {
  match id {
    "primary" => Some(Primary)
    "secondary" => Some(Secondary)
    _ => None
  }
}

///|
/// Every view, in the default section order.
pub let views : Array[View] = [Files, Models, Ideas, Generated]

///|
pub fn View::id(self : View) -> String {
  match self {
    Files => "files"
    Models => "models"
    Generated => "generated"
    Ideas => "ideas"
  }
}

///|
pub fn View::title(self : View) -> String {
  match self {
    Files => "Files"
    Models => "Models"
    Generated => "Generated"
    Ideas => "Ideas"
  }
}

///|
pub fn View::from_id(id : String) -> View? {
  views.iter().find_first(view => view.id() == id)
}

///|
fn clamp(width : Int32) -> Int32 {
  if width < min_width {
    min_width
  } else if width > max_width {
    max_width
  } else {
    width
  }
}

///|
/// The starting layout: Files, Models and Ideas on the left and Generated on the right. The left sidebar starts open
/// unless the window is narrow; the right one starts closed.
pub fn Layout::default(narrow~ : Bool = false) -> Layout {
  {
    primary: { open: !narrow, width: default_width, },
    secondary: { open: false, width: default_width, },
    placement: views.map(view => {
      (view, if view == Generated { Secondary } else { Primary })
    }),
    collapsed: [],
  }
}

///|
pub fn Layout::sidebar(self : Layout, side : Side) -> Sidebar {
  match side {
    Primary => self.primary
    Secondary => self.secondary
  }
}

///|
fn Layout::with_sidebar(
  self : Layout,
  side : Side,
  sidebar : Sidebar,
) -> Layout {
  match side {
    Primary => { ..self, primary: sidebar, }
    Secondary => { ..self, secondary: sidebar, }
  }
}

///|
pub fn Layout::is_open(self : Layout, side : Side) -> Bool {
  self.sidebar(side).open
}

///|
/// The sidebar that holds `view`. A view that the placement does not list is where the default layout puts it.
pub fn Layout::side_of(self : Layout, view : View) -> Side {
  match self.placement.iter().find_first(entry => entry.0 == view) {
    Some((_, side)) => side
    None => if view == Generated { Secondary } else { Primary }
  }
}

///|
/// The views of `available` in `side`, in section order.
pub fn Layout::views_in(
  self : Layout,
  side : Side,
  available : Array[View],
) -> Array[View] {
  let shown : Array[View] = []
  for entry in self.placement {
    if entry.1 == side && available.contains(entry.0) {
      shown.push(entry.0)
    }
  }
  for view in available {
    if !shown.contains(view) &&
      self.side_of(view) == side &&
      !self.placement.iter().any(entry => entry.0 == view) {
      shown.push(view)
    }
  }
  shown
}

///|
pub fn Layout::section_open(self : Layout, view : View) -> Bool {
  !self.collapsed.contains(view)
}

///|
/// True when the view is on screen: its sidebar and its section are open.
pub fn Layout::shows(self : Layout, view : View) -> Bool {
  self.is_open(self.side_of(view)) && self.section_open(view)
}

///|
/// The layout after one action. A move keeps the section's open state and puts the view after the views already
/// in its new sidebar; a view is never in two places.
pub fn Layout::apply(self : Layout, action : Action) -> Layout {
  match action {
    Toggle(side) => {
      let sidebar = self.sidebar(side)
      self.with_sidebar(side, { ..sidebar, open: !sidebar.open, })
    }
    SetOpen(side, open) =>
      self.with_sidebar(side, { ..self.sidebar(side), open, })
    Resize(side, width) =>
      self.with_sidebar(side, { ..self.sidebar(side), width: clamp(width), })
    Nudge(side, by) => {
      let sidebar = self.sidebar(side)
      self.with_sidebar(side, { ..sidebar, width: clamp(sidebar.width + by), })
    }
    // A moved view stays in sight: its new sidebar opens.
    Move(view, side) => {
      let placement = self.placement.filter(entry => entry.0 != view)
      placement.push((view, side))
      { ..self, placement, }.with_sidebar(side, {
        ..self.sidebar(side),
        open: true,
      })
    }
    EndResize(_) => self
    ToggleSection(view) =>
      if self.collapsed.contains(view) {
        { ..self, collapsed: self.collapsed.filter(v => v != view), }
      } else {
        { ..self, collapsed: [..self.collapsed, view], }
      }
    Reveal(view) => {
      let side = self.side_of(view)
      {
        ..self.with_sidebar(side, { ..self.sidebar(side), open: true, }),
        collapsed: self.collapsed.filter(v => v != view),
      }
    }
  }
}

///|
pub fn Layout::to_json(self : Layout) -> Json {
  fn sidebar(value : Sidebar) -> Json {
    {
      "open": Json::boolean(value.open),
      "width": Json::number(value.width.to_double()),
    }
  }

  {
    "primary": sidebar(self.primary),
    "secondary": sidebar(self.secondary),
    "placement": Json::array(
      self.placement.map(entry => {
        (
          {
            "view": Json::string(entry.0.id()),
            "side": Json::string(entry.1.id()),
          } : Json)
      }),
    ),
    "collapsed": Json::array(
      self.collapsed.map(view => Json::string(view.id())),
    ),
  }
}

///|
/// The layout a saved value describes. Unknown views and sides are left out, widths are kept in range, and a value
/// that is not a layout gives `fallback`.
pub fn Layout::from_json(value : Json, fallback : Layout) -> Layout {
  guard value is Object(fields) else { return fallback }
  fn sidebar(value : Json?, fallback : Sidebar) -> Sidebar {
    match value {
      Some(Object(fields)) => {
        let open = match fields.get("open") {
          Some(True) => true
          Some(False) => false
          _ => fallback.open
        }
        let width = match fields.get("width") {
          Some(Number(n, ..)) => clamp(n.to_int())
          _ => fallback.width
        }
        { open, width, }
      }
      _ => fallback
    }
  }

  let placement : Array[(View, Side)] = []
  if fields.get("placement") is Some(Array(entries)) {
    for entry in entries {
      if entry is Object(item) &&
        item.get("view") is Some(String(view)) &&
        item.get("side") is Some(String(side)) &&
        View::from_id(view) is Some(view) &&
        Side::from_id(side) is Some(side) &&
        !placement.iter().any(e => e.0 == view) {
        placement.push((view, side))
      }
    }
  }
  for entry in fallback.placement {
    if !placement.iter().any(e => e.0 == entry.0) {
      placement.push(entry)
    }
  }
  let collapsed : Array[View] = []
  if fields.get("collapsed") is Some(Array(entries)) {
    for entry in entries {
      if entry is String(id) &&
        View::from_id(id) is Some(view) &&
        !collapsed.contains(view) {
        collapsed.push(view)
      }
    }
  }
  {
    primary: sidebar(fields.get("primary"), fallback.primary),
    secondary: sidebar(fields.get("secondary"), fallback.secondary),
    placement,
    collapsed,
  }
}

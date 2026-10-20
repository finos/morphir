// Shared shell views: rail buttons, sidebars without structural headings, stacked explorer sections, the resize
// splitter and keyboard traversal of explorer trees. The workbench decides what each section contains.

///|
/// Tracks a pointer drag on a splitter and reports each new width. A secondary sidebar grows when the pointer
/// moves left. Releasing or cancelling the pointer ends the drag.
extern "js" fn drag_width(
  event : @dom.Event,
  start : Int32,
  secondary : Bool,
  report : (Int32) -> Unit,
  done : () -> Unit,
) =
  #|(event, start, secondary, report, done) => {
  #|  const handle = event.currentTarget, x = event.clientX, id = event.pointerId;
  #|  if (event.button !== 0) return;
  #|  event.preventDefault();
  #|  try { handle.setPointerCapture(id); } catch {}
  #|  let frame = 0, latest = start;
  #|  const move = (e) => {
  #|    latest = Math.round(start + (secondary ? x - e.clientX : e.clientX - x));
  #|    if (!frame) frame = requestAnimationFrame(() => { frame = 0; report(latest); });
  #|  };
  #|  const end = () => {
  #|    handle.removeEventListener('pointermove', move);
  #|    handle.removeEventListener('pointerup', end);
  #|    handle.removeEventListener('pointercancel', end);
  #|    if (frame) { cancelAnimationFrame(frame); frame = 0; report(latest); }
  #|    done();
  #|  };
  #|  handle.addEventListener('pointermove', move);
  #|  handle.addEventListener('pointerup', end);
  #|  handle.addEventListener('pointercancel', end);
  #|}

///|
/// Moves the focus through the rows of the explorer tree that holds the event's target: Up and Down move, Home and
/// End jump, Right opens a closed folder or moves into an open one, and Left closes an open folder or moves to the
/// folder that holds the row. Rows are the focusable `[data-tree-row]` elements; a folder row has `aria-expanded`.
/// Returns true when the key moved the focus or a folder.
extern "js" fn tree_key(event : @dom.Event) -> Bool =
  #|(event) => {
  #|  const row = event.target.closest?.('[data-tree-row]');
  #|  const tree = row?.closest('[data-tree]');
  #|  if (!row || !tree || event.altKey || event.ctrlKey || event.metaKey) return false;
  #|  const rows = [...tree.querySelectorAll('[data-tree-row]')].filter(r => r.offsetParent !== null && !r.disabled);
  #|  const at = rows.indexOf(row);
  #|  const expanded = row.getAttribute('aria-expanded');
  #|  const level = Number(row.dataset.level || '0');
  #|  let next = null;
  #|  switch (event.key) {
  #|    case 'ArrowDown': next = rows[at + 1]; break;
  #|    case 'ArrowUp': next = rows[at - 1]; break;
  #|    case 'Home': next = rows[0]; break;
  #|    case 'End': next = rows[rows.length - 1]; break;
  #|    case 'ArrowRight':
  #|      if (expanded === 'false') { row.click(); return true; }
  #|      if (expanded === 'true') next = rows[at + 1];
  #|      break;
  #|    case 'ArrowLeft':
  #|      if (expanded === 'true') { row.click(); return true; }
  #|      for (let i = at - 1; i >= 0; i--) if (Number(rows[i].dataset.level || '0') < level) { next = rows[i]; break; }
  #|      break;
  #|    default: return false;
  #|  }
  #|  if (next) next.focus();
  #|  return true;
  #|}

///|
fn icon(name : String) -> @html.Html {
  @html.span(
    class="nav-icon icon-" + name,
    attrs=@html.Attrs::build().aria_hidden("true"),
    "",
  )
}

///|
/// Handles tree keys on an explorer's rows; other keys do nothing here.
pub fn on_tree_key(event : @dom.KeyboardEvent) -> @cmd.Cmd {
  if tree_key(event.as_event()) {
    event.prevent_default()
  }
  @cmd.none
}

///|
/// A button of the left rail. `pressed` is its state when it toggles something, such as the explorer.
pub fn rail_button(
  id~ : String,
  label~ : String,
  icon_name~ : String,
  active~ : Bool,
  controls? : String,
  on_click~ : @cmd.Cmd,
) -> @html.Html {
  let attrs = @html.Attrs::build()
    .aria_label(label)
    .aria_pressed(active.to_string())
  @html.button(
    id~,
    class=if active { "rail-button active" } else { "rail-button" },
    title=label,
    attrs=match controls {
      Some(target) => attrs.aria_controls(target)
      None => attrs
    },
    on_click~,
    icon(icon_name),
  )
}

///|
/// The DOM id of a sidebar.
pub fn sidebar_id(side : Side) -> String {
  "sidebar-" + side.id()
}

///|
/// The DOM id of a section's toggle, for focus.
pub fn section_id(view : View) -> String {
  "section-" + view.id()
}

///|
/// The resize handle at the inner edge of a sidebar: a focusable separator that arrows, Home and End resize, and a
/// pointer drags.
fn splitter(side : Side, width : Int32, emit : @cmd.Emit[Action]) -> @html.Html {
  let toward = match side {
    Primary => 1
    Secondary => -1
  }
  @html.div(
    class="sidebar-splitter",
    attrs=@html.Attrs::build()
      .role("separator")
      .tabindex(0)
      .aria_label("Resize " + side.label().to_lower())
      .aria_orientation("vertical")
      .aria_controls(sidebar_id(side))
      .aria_valuemin(min_width.to_string())
      .aria_valuemax(max_width.to_string())
      .aria_valuenow(width.to_string())
      .on_keydown(event => {
        let by = match event.key() {
          "ArrowRight" => Some(step * toward)
          "ArrowLeft" => Some(-step * toward)
          "Home" => Some(min_width - width)
          "End" => Some(max_width - width)
          _ => None
        }
        match by {
          Some(delta) => {
            event.prevent_default()
            emit(Nudge(side, delta))
          }
          None => @cmd.none
        }
      })
      .on_pointerdown(event => {
        @cmd.custom_cmd(scheduler => {
          drag_width(
            event.as_event(),
            width,
            side == Secondary,
            next => scheduler.add(emit(Resize(side, next))),
            () => scheduler.add(emit(EndResize(side))),
          )
        })
      }),
    ([] : Array[@html.Html]),
  )
}

///|
/// A sidebar of stacked sections. Its accessible name says which sidebar it is; no visible heading repeats it. The
/// header keeps a compact collapse button; `footer` notes what the sidebar shows.
pub fn sidebar(
  side : Side,
  layout : Layout,
  sections : Array[@html.Html],
  footer : String,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let current = layout.sidebar(side)
  let hide = "Hide " + side.label().to_lower()
  @html.aside(
    id=sidebar_id(side),
    class="sidebar sidebar-" + side.id(),
    hidden=!current.open,
    attrs=@html.Attrs::build()
      .aria_label(side.label())
      .style("width", current.width.to_string() + "px"),
    [
      @html.div(class="sidebar-header", [
        @html.button(
          class="sidebar-icon-button",
          title=hide,
          attrs=@html.Attrs::build()
            .aria_label(hide)
            .aria_controls(sidebar_id(side))
            .aria_expanded("true"),
          on_click=emit(SetOpen(side, false)),
          icon(
            match side {
              Primary => "sidebar"
              Secondary => "sidebar-right"
            },
          ),
        ),
      ]),
      @html.div(
        class="sidebar-sections",
        if sections.is_empty() {
          [
            @html.p(
              class="sidebar-empty small muted",
              "No views here. Move a view to this sidebar from its section or the command palette.",
            ),
          ]
        } else {
          sections
        },
      ),
      @html.p(class="sidebar-footer small muted", hidden=footer == "", footer),
      splitter(side, current.width, emit),
    ],
  )
}

///|
/// One stacked section: a header that opens and closes it, an optional count, the section's own action buttons and
/// a button that moves the view to the other sidebar.
pub fn section(
  layout : Layout,
  view : View,
  count~ : String = "",
  actions~ : Array[@html.Html] = [],
  body : Array[@html.Html],
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let open = layout.section_open(view)
  let side = layout.side_of(view)
  let body_id = section_id(view) + "-body"
  let move_label = "Move " + view.title() + " to " + side.other().destination()
  @html.section(
    class=if open { "explorer-section open" } else { "explorer-section" },
    attrs=@html.Attrs::build()
      .aria_labelledby(section_id(view))
      .data_set("view", view.id()),
    [
      @html.div(class="section-header", [
        @html.button(
          id=section_id(view),
          class="section-toggle",
          attrs=@html.Attrs::build()
            .aria_expanded(open.to_string())
            .aria_controls(body_id),
          on_click=emit(ToggleSection(view)),
          [
            @html.span(
              class=if open {
                "section-chevron open"
              } else {
                "section-chevron"
              },
              attrs=@html.Attrs::build().aria_hidden("true"),
              "›",
            ),
            @html.span(class="section-title", view.title()),
            @html.span(class="section-count", hidden=count == "", count),
          ],
        ),
        @html.div(
          class="section-actions",
          [
            ..actions,
            @html.button(
              class="sidebar-icon-button section-move",
              title=move_label,
              attrs=@html.Attrs::build().aria_label(move_label),
              on_click=emit(Move(view, side.other())),
              icon("move"),
            ),
          ],
        ),
      ]),
      @html.div(id=body_id, class="section-body", hidden=!open, body),
    ],
  )
}

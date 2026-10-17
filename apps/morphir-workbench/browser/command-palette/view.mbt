///|
pub(all) struct Props {
  state : State
  entries : Array[Entry]
  mac : Bool
  /// Shown when files mode has no files at all, such as in the worksheet.
  no_files : String
}

///|
pub let input_id : String = "palette-input"

///|
let list_id = "palette-list"

///|
/// The DOM id of the option at `index`, for `aria-activedescendant` and scrolling.
pub fn option_id(index : Int32) -> String {
  "palette-option-" + index.to_string()
}

///|
extern "js" fn input_value(event : @dom.InputEvent) -> String =
  #|(event) => event.currentTarget.value

///|
fn marked(
  text : String,
  positions : Array[Int32],
  class : String,
) -> @html.Html {
  @html.span(
    class~,
    segments(text, positions).map(part => {
      if part.1 {
        @html.mark(class="palette-match", part.0)
      } else {
        @html.text(part.0)
      }
    }),
  )
}

///|
fn chip(state : State) -> String {
  match state.mode() {
    Files => "Go to file"
    Commands => "Run command"
    Choose(_) =>
      match state.choosing {
        Some((_, prompt)) => prompt
        None => ""
      }
  }
}

///|
fn placeholder(state : State) -> String {
  match state.mode() {
    Files => "Search files by name"
    Commands => "Type the name of a command"
    Choose(_) => "Type to filter"
  }
}

///|
fn empty_text(props : Props) -> String {
  match props.state.mode() {
    Files if props.state.query == "" => props.no_files
    Files => "No files match. Type > to search commands."
    Commands => "No commands match."
    Choose(_) => "Nothing matches."
  }
}

///|
fn option_view(
  props : Props,
  emit : @cmd.Emit[Action],
  index : Int32,
  entry : Entry,
) -> @html.Html {
  let selected = index == props.state.index
  let attrs = @html.Attrs::build()
    .role("option")
    .aria_label(entry.label)
    .aria_description(entry.detail)
    .aria_selected(selected.to_string())
    .aria_disabled((!entry.enabled).to_string())
    .on_mousemove(_ => if selected { @cmd.none } else { emit(Hover(index)) })
    // A press would move the focus out of the input before the click; keep it there.
    .on_mousedown(event => {
      event.prevent_default()
      @cmd.none
    })
    .on_click(_ => emit(Pick(index)))
  let attrs = if entry.keys == "" {
    attrs
  } else {
    attrs.aria_keyshortcuts(entry.keys)
  }
  let main : Array[@html.Html] = [
    @html.span(
      class="palette-icon " + entry.icon,
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    marked(entry.label, entry.label_marks, "palette-label"),
  ]
  if entry.detail != "" {
    main.push(marked(entry.detail, entry.detail_marks, "palette-detail"))
  }
  if entry.recent && props.state.mode() == Commands {
    main.push(@html.span(class="palette-recent", "recently used"))
  }
  if entry.hint != "" {
    main.push(
      if entry.keys == "" {
        @html.span(class="palette-note", entry.hint)
      } else {
        @html.kbd(class="shortcut", entry.hint)
      },
    )
  }
  @html.li(
    id=option_id(index),
    class=(if selected { "palette-option selected" } else { "palette-option" }) +
      (if entry.enabled { "" } else { " disabled" }),
    title=entry.reason,
    attrs~,
    main,
  )
}

///|
fn hint(keys : String, text : String) -> @html.Html {
  @html.span(class="palette-hint", [
    @html.kbd(class="shortcut", keys),
    @html.text(text),
  ])
}

///|
/// The command palette: a dialog with a combobox input and a list of options. Nothing renders while it is closed.
pub fn view(props : Props, emit : @cmd.Emit[Action]) -> @html.Html {
  guard props.state.open else { return @html.nothing }
  let state = props.state
  let index = if props.entries.is_empty() {
    -1
  } else {
    state.index.min(props.entries.length() - 1)
  }
  let input_attrs = @html.Attrs::build()
    .role("combobox")
    .aria_label(chip(state))
    .aria_expanded("true")
    .aria_controls(list_id)
    .aria_autocomplete("list")
    .value_prop(state.query)
    .spellcheck(false)
    .on_input(event => emit(Query(input_value(event))))
    .on_keydown(event => {
      let chord = @keys.Chord::from_event(
        event.key(),
        ctrl=event.ctrl_key(),
        meta=event.meta_key(),
        shift=event.shift_key(),
        alt=event.alt_key(),
        mac=props.mac,
      )
      match chord.key {
        "ArrowDown" | "ArrowUp" | "PageDown" | "PageUp" | "Enter" | "Escape" => {
          event.prevent_default()
          event.stop_propagation()
          emit(Key(chord))
        }
        // The dialog holds only the input, so Tab stays in it.
        "Tab" => {
          event.prevent_default()
          @cmd.none
        }
        _ => @cmd.none
      }
    })
  let input_attrs = if index >= 0 {
    input_attrs.aria_activedescendant(option_id(index))
  } else {
    input_attrs
  }
  let footer : Array[@html.Html] = [
    hint("↑↓", "Move"),
    hint(if props.mac { "↩" } else { "Enter" }, "Open"),
    hint("Esc", "Close"),
  ]
  if state.mode() == Files {
    footer.push(hint(">", "Commands"))
  }
  @html.div(class="palette-layer", [
    @html.div(
      class="palette-backdrop",
      attrs=@html.Attrs::build().on_click(_ => emit(Close)),
      "",
    ),
    @html.div(
      class="palette",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label("Command palette"),
      [
        @html.div(class="palette-field", [
          @html.span(class="palette-chip", chip(state)),
          @html.input(
            id=input_id,
            class="palette-input",
            value=state.query,
            placeholder=placeholder(state),
            auto_complete=Off,
            attrs=input_attrs,
          ),
        ]),
        @html.ul(
          id=list_id,
          class="palette-list",
          attrs=@html.Attrs::build().role("listbox").aria_label(chip(state)),
          props.entries.mapi((i, entry) => {
            option_view(
              { ..props, state: { ..state, index, }, },
              emit,
              i,
              entry,
            )
          }),
        ),
        if props.entries.is_empty() {
          @html.p(class="palette-empty", empty_text(props))
        } else {
          @html.nothing
        },
        @html.div(class="palette-footer", footer),
      ],
    ),
  ])
}

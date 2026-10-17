///|
/// A controlled code document. A stable key retains cursor and undo history
/// across experience navigation. Unknown language identifiers show plain text.
pub(all) struct Props {
  id : String
  document_key : String
  value : String
  language : String
  label : String
  read_only : Bool
  /// JSON `[{line, column, endLine, endColumn, message}]` with one-based display columns.
  marks : String
  /// `<line>:<column>:<nonce>` to move the cursor there; empty for none.
  reveal : String
}

///|
extern "js" fn changed_value(event : @dom.InputEvent) -> String =
  #| (event) => event.currentTarget.value

///|
/// The custom element owns CodeMirror's DOM and lifecycle inside a shadow root.
/// Rabbita owns these props and receives exactly one input event per user edit.
pub fn view(props : Props, on_change? : @cmd.Emit[String]) -> @html.Html {
  let attrs = @html.Attrs::build()
    .id(props.id)
    .data_set("document", props.document_key)
    .data_set("language", props.language)
    .data_set("readonly", props.read_only.to_string())
    .data_set("marks", props.marks)
    .data_set("reveal", props.reveal)
    .aria_label(props.label)
    .value_prop(props.value)
  let attrs = match on_change {
    Some(emit) => attrs.on_input(event => emit(changed_value(event)))
    None => attrs
  }
  @html.node("morphir-code-editor", attrs, @html.nothing)
}

///|
pub(all) enum Mode {
  Value
  Json
  Printed
} derive(Eq)

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub(all) struct Props {
  result : Json
  terminal : @outcomes.Projection
  document_key : String
  mode : Mode
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
fn items(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
extern "js" fn pretty(text : String) -> String =
  #| (text) => JSON.stringify(JSON.parse(text), null, 2)

///|
fn tree(value : Json, label : String, depth : Int32) -> @html.Html {
  let kind = text(value, "kind")
  let compound = ["record", "list", "tuple", "constructor"].contains(kind)
  let children = []
  let heading = if kind == "constructor" {
    text(value, "tag")
  } else if kind == "tuple" {
    "Tuple / vector"
  } else if kind == "list" && field(value, "tail") != Json::null() {
    "Improper list"
  } else {
    kind
  }
  let title = @html.span(class="result-node-title", [
    @html.strong(label),
    @html.span(class="muted small", heading),
  ])
  if !compound {
    return @html.div(class="result-leaf", [
      title,
      @html.pre(class="result-scalar", text(value, "text")),
    ])
  }
  if kind == "record" {
    for entry in items(field(value, "fields")) {
      children.push(tree(field(entry, "value"), text(entry, "name"), depth + 1))
    }
  } else {
    for i, child in items(field(value, "items")) {
      children.push(tree(child, "[" + (i + 1).to_string() + "]", depth + 1))
    }
    if field(value, "tail") != Json::null() {
      children.push(tree(field(value, "tail"), "tail", depth + 1))
    }
  }
  if children.is_empty() {
    children.push(
      @html.p(
        class="muted small",
        if kind == "constructor" {
          "No arguments"
        } else {
          "Empty"
        },
      ),
    )
  }
  @html.details(class="result-branch", open=depth < 2, [
    @html.summary(title),
    @html.div(class="result-children", children),
  ])
}

///|
/// Results stay separate from the argument document and source editor.
pub fn view(props : Props, on_mode : @cmd.Emit[Mode]) -> @html.Html {
  if props.terminal is Invalid(_) {
    return @html.div(hidden=true, "")
  }
  if props.terminal is Valid(summary) && !summary.has_value() {
    return @html.div(hidden=true, "")
  }
  let retained_value = props.terminal is Valid(summary) && summary.has_value()
  if !retained_value && field(props.result, "success") != Json::boolean(true) {
    return @html.pre(text(props.result, "message"))
  }
  let structured = field(props.result, "structured")
  let document_key = props.document_key +
    (if props.mode == Json { "-json" } else { "-printed" })
  let content = match props.mode {
    Value if structured != Json::null() => tree(structured, "Result", 0)
    Value => @html.pre(text(props.result, "value"))
    Json | Printed =>
      @editor.view({
        id: "evaluation-output",
        document_key,
        value: if props.mode == Json {
          pretty(
            (if field(props.result, "typed") != Json::null() {
              field(props.result, "typed")
            } else {
              structured
            }).stringify(),
          )
        } else {
          text(props.result, "value")
        },
        language: if props.mode == Json {
          "json"
        } else {
          "text"
        },
        label: if props.mode == Json {
          "Result JSON"
        } else {
          "Printed result"
        },
        read_only: true,
        marks: "",
        reveal: "",
      })
  }
  @html.div(class="result-view", [
    @html.div(
      class="view-tabs",
      attrs=@html.Attrs::build().role("group").aria_label("Result view"),
      [(Value, "Value"), (Json, "Result JSON"), (Printed, "Printed")].map(pair => {
        @html.button(
          class=if props.mode == pair.0 { "selected" } else { "" },
          disabled=pair.0 == Json && structured == Json::null(),
          attrs=@html.Attrs::build().aria_pressed(
            (props.mode == pair.0).to_string(),
          ),
          on_click=on_mode(pair.0),
          pair.1,
        )
      }),
    ),
    content,
  ])
}

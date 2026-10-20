///|
pub(all) struct Props {
  frontend : Json
  profile : String
  busy : Bool
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
    Array(items) => items
    _ => []
  }
}

///|
pub fn view(props : Props, on_change~ : @cmd.Emit[String]) -> @html.Html {
  let profiles = items(field(props.frontend, "profiles"))
  @html.label(hidden=profiles.is_empty(), [
    @html.span(class="small muted", "Source profile"),
    @html.select(
      disabled=props.busy,
      attrs=@html.Attrs::build()
        .aria_label("Source profile")
        .value_prop(props.profile),
      on_change~,
      profiles.map(profile => {
        @html.option(
          value=text(profile, "id"),
          selected=text(profile, "id") == props.profile,
          text(profile, "displayName"),
        )
      }),
    ),
  ])
}

///|
pub fn capabilities(props : Props) -> @html.Html {
  let profiles = items(field(props.frontend, "profiles"))
  let selected = profiles.filter(profile => text(profile, "id") == props.profile)
  let profile = selected.get(0).unwrap_or(Json::null())
  fn descriptions(key : String) -> Array[@html.Html] {
    items(field(profile, key)).map(value => {
      @html.li(
        match value {
          String(s) => s
          _ => ""
        },
      )
    })
  }
  @html.details(class="source-capabilities", hidden=profiles.is_empty(), [
    // The profile's name is in the selection beside it; the summary stays short so the editor header stays compact.
    @html.summary(
      attrs=@html.Attrs::build().aria_label(
        text(profile, "displayName") + " profile details",
      ),
      "Profile details",
    ),
    @html.div(class="source-capabilities-grid", [
      @html.div([@html.strong("Supported"), @html.ul(descriptions("supported"))]),
      @html.div([
        @html.strong("Outside this profile"),
        @html.ul(descriptions("excluded")),
      ]),
    ]),
  ])
}

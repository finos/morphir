///|
priv enum Index {
  NotLoaded
  Loading
  Ready(Array[@model.SearchEntry])
  Failed
} derive(Eq)

///|
priv struct SearchModel {
  index : Index
  query : String
  selected : Int
} derive(Eq)

///|
priv enum SearchMsg {
  Query(String)
  Loaded(Result[String, Error])
  Key(@common.Keyboard)
}

///|
fn parse_index(text : String) -> Index {
  let json = @json.parse(text) catch { _ => return Failed }
  match json {
    Array(items) => Ready(items.filter_map(@model.SearchEntry::from_json))
    _ => Failed
  }
}

///|
fn results(model : SearchModel) -> Array[@model.SearchEntry] {
  match model.index {
    Ready(entries) => @model.search(entries, model.query)
    _ => []
  }
}

///|
fn search_box(base : String) -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state(
    { index: NotLoaded, query: "", selected: 0, },
    update=(model, msg, emit) => {
      match msg {
        Query(q) => {
          let next = { ..model, query: q, selected: 0, }
          if model.index == NotLoaded {
            (
              { ..next, index: Loading, },
              @http.get(base + "search-index.json").expect_text(
                emit.map(r => Loaded(r)),
              ),
            )
          } else {
            (next, @rabbita.none)
          }
        }
        Loaded(Ok(text)) =>
          ({ ..model, index: parse_index(text), }, @rabbita.none)
        Loaded(Err(_)) => ({ ..model, index: Failed, }, @rabbita.none)
        Key(key) => {
          let found = results(model)
          match key.key() {
            "ArrowDown" =>
              (
                {
                  ..model,
                  selected: (model.selected + 1).min(found.length() - 1).max(0),
                },
                @rabbita.none,
              )
            "ArrowUp" =>
              (
                { ..model, selected: (model.selected - 1).max(0), },
                @rabbita.none,
              )
            "Enter" if found.length() > 0 =>
              (
                model,
                @nav.load(base + found[model.selected].route[1:].to_owned()),
              )
            "Escape" => ({ ..model, query: "", selected: 0, }, @rabbita.none)
            _ => (model, @rabbita.none)
          }
        }
      }
    },
  )
  model.view(m => {
    let found = results(m)
    let list = if m.query.trim() == "" {
      @html.nothing
    } else if found.is_empty() {
      @html.ul(class="search-results", [
        @html.li(class="search-empty", "No results"),
      ])
    } else {
      @html.ul(
        class="search-results",
        found.mapi((i, e) => {
          @html.li(class=if i == m.selected { "selected" } else { "" }, [
            // Islands have no router, and Rabbita drops captured link clicks without one.
            @html.a(
              href=base + e.route[1:].to_owned(),
              [@html.span(e.title), @html.small(e.section)],
              escape=true,
            ),
          ])
        }),
      )
    }
    @html.div(class="search", on_keydown=emit.map(k => Key(k)), [
      @html.input(
        id="search-input",
        placeholder="Search (/)",
        value=m.query,
        on_input=emit.map(q => Query(q)),
        attrs=@html.Attrs::build().aria_label("Search the site"),
      ),
      list,
    ])
  })
}

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
  Loaded(Array[@model.SearchEntry]?)
  Key(@common.Keyboard)
}

///|
/// Loads `search-index.json` with the browser's `fetch` and `JSON.parse`, and passes each
/// entry as `[route, title, section, summary, text, ...headings]`. Entries with a field of
/// the wrong type are dropped. The island does not use `rabbita/http` or `@json`: together
/// they would triple the size of `islands.js`.
extern "js" fn fetch_search_index(
  url : String,
  done : (Array[Array[String]]) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #| (url, done, failed) => {
  #|   const text = (v) => typeof v === "string";
  #|   fetch(url)
  #|     .then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
  #|     .then((items) => {
  #|       if (!Array.isArray(items)) throw new Error("not an array");
  #|       done(items
  #|         .filter((e) => e && ["route", "title", "section", "summary", "text"].every((k) => text(e[k]))
  #|           && Array.isArray(e.headings) && e.headings.every(text))
  #|         .map((e) => [e.route, e.title, e.section, e.summary, e.text, ...e.headings]));
  #|     })
  #|     .catch(() => failed());
  #| }

///|
/// Opens a page. `rabbita/nav` would do the same, but adds its runtime to `islands.js`.
extern "js" fn open_page(url : String) -> Unit = "(url) => location.assign(url)"

///|
fn entry_of(fields : Array[String]) -> @model.SearchEntry? {
  guard fields.length() >= 5 else { return None }
  Some(@model.SearchEntry::{
    route: fields[0],
    title: fields[1],
    section: fields[2],
    summary: fields[3],
    text: fields[4],
    headings: fields[5:].to_owned(),
  })
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
              @cmd.custom_cmd(scheduler => {
                fetch_search_index(
                  base + "search-index.json",
                  rows => {
                    scheduler.add(emit(Loaded(Some(rows.filter_map(entry_of)))))
                  },
                  () => scheduler.add(emit(Loaded(None))),
                )
              }),
            )
          } else {
            (next, @rabbita.none)
          }
        }
        Loaded(Some(entries)) =>
          ({ ..model, index: Ready(entries), }, @rabbita.none)
        Loaded(None) => ({ ..model, index: Failed, }, @rabbita.none)
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
                @cmd.custom_cmd(_ => {
                  open_page(base + found[model.selected].route[1:].to_owned())
                }),
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

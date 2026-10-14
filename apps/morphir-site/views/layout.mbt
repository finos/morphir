///|
using @html {type Html}

///|
pub(all) struct PageMeta {
  config : @model.SiteConfig
  route : String
  title : String
  description : String
  section : @model.Section
  mermaid : Bool
}

///|
/// Sets the stored theme before the first paint, so the page does not flash.
let theme_script : String = "try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}"

///|
/// A block of reviewed HTML.
pub fn raw(html : String, class? : String = "prose") -> Html {
  @html.div(class~, attrs=@html.Attrs::build().inner_html(html), @html.nothing)
}

///|
/// An empty mount point for a client island. `inner_html` keeps it free of the
/// hydration comments that an empty child list would add.
fn island(id : String) -> Html {
  @html.div(id~, attrs=@html.Attrs::build().inner_html(""), @html.nothing)
}

///|
fn nav_link(
  meta : PageMeta,
  section : @model.Section,
  route : String,
  label : String,
) -> Html {
  if meta.section == section {
    @html.a(
      href=meta.config.href(route),
      class="current",
      attrs=@html.Attrs::build().aria_current("page"),
      label,
    )
  } else {
    @html.a(href=meta.config.href(route), label)
  }
}

///|
pub fn layout(meta : PageMeta, main : Html) -> Html {
  let config = meta.config
  let title = if meta.section == Home {
    config.title
  } else {
    "\{meta.title} · \{config.title}"
  }
  let mermaid = if meta.mermaid {
    [
      @html.script(src=config.href("/assets/mermaid.min.js"), @html.nothing),
      @html.script(
        attrs=@html.Attrs::build().inner_html(
          "mermaid.initialize({startOnLoad:true})",
        ),
        @html.nothing,
      ),
    ]
  } else {
    []
  }
  @html.html(
    lang="en",
    attrs=@html.Attrs::build().data_set("base", config.base_path),
    [
      @html.head(
        [
          @html.meta(charset="utf-8"),
          @html.meta(
            name="viewport",
            content="width=device-width, initial-scale=1",
          ),
          @html.title(title),
          @html.meta(name="description", content=meta.description),
          @html.link(rel="stylesheet", href=config.href("/assets/site.css")),
          @html.link(
            rel="icon",
            type_="image/svg+xml",
            href=config.href("/assets/morphir-mark.svg"),
          ),
          @html.link(
            rel="alternate",
            type_="application/atom+xml",
            href=config.href("/blog/atom.xml"),
            title="\{config.title} blog",
          ),
          @html.script(
            attrs=@html.Attrs::build().inner_html(theme_script),
            @html.nothing,
          ),
          @html.script(
            src=config.href("/assets/islands.js"),
            type_="module",
            @html.nothing,
          ),
        ] +
        mermaid,
      ),
      @html.body([
        @html.a(href="#content", class="skip-link", "Skip to content"),
        @html.header(class="site-header", [
          @html.a(href=config.href("/"), class="brand", [
            @html.img(
              src=config.href("/assets/morphir-mark.svg"),
              alt="",
              width=28,
              height=28,
            ),
            @html.span(config.title),
          ]),
          @html.nav(
            id="site-links",
            class="site-links",
            attrs=@html.Attrs::build().aria_label("Main"),
            [
              nav_link(meta, Docs, "/docs/", "Docs"),
              nav_link(meta, Blog, "/blog/", "Blog"),
              @html.a(href=config.href("/try/"), "Try Morphir"),
              @html.a(href=config.repo_url, "GitHub"),
            ],
          ),
          @html.div(id="site-search", [
            @html.a(href=config.href("/docs/"), "Search docs"),
          ]),
          island("site-theme"),
          island("site-nav"),
        ]),
        @html.main_(id="content", [main]),
        @html.footer(class="site-footer", [
          @html.p([
            @html.text("Apache-2.0 · A "),
            @html.a(href="https://www.finos.org/", "FINOS"),
            @html.text(" project · "),
            @html.a(href="https://morphir.finos.org/", "Morphir"),
          ]),
        ]),
      ]),
    ],
  )
}

///|
pub async fn render(meta : PageMeta, main : Html) -> String {
  let page = layout(meta, main)
  @rabbita.new(() => @rabbita.Val::constant(page)).render(
    url=meta.config.absolute(meta.route),
  )
}

///|
pub let latest_posts_marker : String = "<div data-site=\"latest-posts\"></div>"

///|
fn nav_entry(meta : PageMeta, item : @model.NavItem) -> Html {
  let class = "depth-\{item.depth}"
  if item.route == "" {
    @html.li(class~, [@html.span(class="nav-label", item.title)])
  } else if item.route == meta.route {
    @html.li(class~, [
      @html.a(
        href=meta.config.href(item.route),
        class="current",
        attrs=@html.Attrs::build().aria_current("page"),
        item.title,
      ),
    ])
  } else {
    @html.li(class~, [@html.a(href=meta.config.href(item.route), item.title)])
  }
}

///|
pub fn docs_page(
  meta : PageMeta,
  nav : Array[@model.NavItem],
  body : String,
  source_url : String?,
  toc~ : Array[@model.TocEntry] = [],
) -> Html {
  let source = match source_url {
    Some(url) =>
      [
        @html.p(class="page-source", [
          @html.a(href=url, "View source on GitHub"),
        ]),
      ]
    None => []
  }
  let rail = if toc.is_empty() {
    []
  } else {
    [
      @html.aside(class="docs-rail", [
        @html.nav(
          id="site-toc",
          class="docs-toc",
          attrs=@html.Attrs::build().aria_label("On this page"),
          [
            @html.p(class="nav-label", "On this page"),
            @html.ul(
              toc.map(e => {
                @html.li(class="depth-\{e.depth}", [
                  @html.a(href="#\{e.id}", e.text),
                ])
              }),
            ),
          ],
        ),
      ]),
    ]
  }
  @html.div(
    class="docs-layout",
    [
      @html.aside(class="docs-sidebar", [
        @html.nav(attrs=@html.Attrs::build().aria_label("Documentation"), [
          @html.ul(nav.map(item => nav_entry(meta, item))),
        ]),
      ]),
      @html.article(class="docs-article", [raw(body)] + source),
    ] +
    rail,
  )
}

///|
fn byline(post : @model.PostSummary) -> Html {
  @html.p(class="post-meta", [
    @html.time(datetime=post.date, post.date),
    @html.text(" · " + post.authors.join(", ")),
  ])
}

///|
pub fn post_page(
  meta : PageMeta,
  post : @model.PostSummary,
  body : String,
) -> Html {
  ignore(meta)
  @html.article(class="post", [
    @html.header([@html.h1(post.title), byline(post)]),
    raw(body),
  ])
}

///|
fn post_card(meta : PageMeta, post : @model.PostSummary) -> Html {
  @html.li(class="post-card", [
    @html.a(href=meta.config.href(post.route), post.title),
    byline(post),
    @html.p(post.summary),
  ])
}

///|
pub fn blog_index(meta : PageMeta, posts : Array[@model.PostSummary]) -> Html {
  @html.section(class="blog-index", [
    @html.h1("Blog"),
    @html.p([@html.a(href=meta.config.href("/blog/atom.xml"), "Atom feed")]),
    @html.ul(class="post-list", posts.map(p => post_card(meta, p))),
  ])
}

///|
/// The landing page. `latest_posts_marker` must be at the top level of `landing`;
/// the newest posts replace it.
pub fn home_page(
  meta : PageMeta,
  landing : String,
  latest : Array[@model.PostSummary],
) -> Html {
  let (before, after) = match landing.find(latest_posts_marker) {
    Some(i) =>
      (
        landing[:i].to_owned(),
        landing[i + latest_posts_marker.length():].to_owned(),
      )
    None => (landing, "")
  }
  let posts = if latest.is_empty() {
    []
  } else {
    [
      @html.section(class="latest-posts", [
        @html.h2("Latest posts"),
        @html.ul(class="post-list", latest.map(p => post_card(meta, p))),
      ]),
    ]
  }
  @html.div(
    class="home",
    [raw(before, class="landing")] + posts + [raw(after, class="landing")],
  )
}

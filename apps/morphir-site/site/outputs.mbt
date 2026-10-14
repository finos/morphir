///|
pub(all) enum Output {
  /// `Text(out_path, content)`.
  Text(String, String)
  /// `Copy(out_path, repo_path)`.
  Copy(String, String)
}

///|
pub(all) struct Built {
  outputs : Array[Output]
  warnings : Array[@model.Problem]
}

///|
fn out_path(route : String) -> String {
  route[1:].to_owned() + "index.html"
}

///|
fn meta(
  config : @model.SiteConfig,
  route : String,
  title : String,
  description : String,
  section : @model.Section,
  mermaid : Bool,
) -> @views.PageMeta {
  { config, route, title, description, section, mermaid, }
}

///|
/// Prepare, then render every page, the docs index, the blog index, the feed and
/// the search index. Outputs keep source order, then generated files, then copies.
pub async fn build(
  config : @model.SiteConfig,
  sources : Array[SourceFile],
  main_build~ : Bool,
) -> Built {
  let prepared = prepare(config, sources, main_build~)
  let pages = prepared.pages
  let docs = pages.filter(p => {
    p.kind is (Doc(_) | Package(_)) && !p.full && p.route != "/docs/"
  })
  let nav = build_nav(
    docs.map(p => { route: p.route, title: p.title, order: p.order, }),
  )
  let posts = newest_first(pages.filter(p => p.kind is Post(_)))
  let summaries = posts.map(p => @model.PostSummary::{
    route: p.route,
    title: p.title,
    date: p.date,
    authors: p.authors,
    summary: p.summary,
  })
  let outputs : Array[Output] = []
  for page in pages {
    if page.full {
      outputs.push(Text(out_path(page.route), page.html))
      continue
    }
    let html = match page.kind {
      Post(_) => {
        let m = meta(
          config,
          page.route,
          page.title,
          page.summary,
          Blog,
          page.mermaid,
        )
        let summary = summaries[summaries
          .search_by(s => s.route == page.route)
          .unwrap()]
        @views.render(m, @views.post_page(m, summary, page.html))
      }
      Landing => {
        let m = meta(
          config,
          "/",
          config.title,
          config.description,
          Home,
          page.mermaid,
        )
        @views.render(
          m,
          @views.home_page(m, page.html, summaries.iter().take(3).collect()),
        )
      }
      _ => {
        let m = meta(
          config,
          page.route,
          page.title,
          page.summary,
          Docs,
          page.mermaid,
        )
        let source = "\{config.repo_url}/blob/main/\{page.source}"
        @views.render(
          m,
          @views.docs_page(m, nav, page.html, Some(source), toc=page.toc),
        )
      }
    }
    outputs.push(Text(out_path(page.route), html))
  }
  if !pages.iter().any(p => p.route == "/docs/") {
    let m = meta(
      config,
      "/docs/",
      "Documentation",
      config.description,
      Docs,
      false,
    )
    let body = "<h1 id=\"documentation\">Documentation</h1><p>Choose a page from the list.</p>"
    outputs.push(
      Text(
        "docs/index.html",
        @views.render(m, @views.docs_page(m, nav, body, None)),
      ),
    )
  }
  let blog = meta(
    config,
    "/blog/",
    "Blog",
    "Posts about \{config.title}",
    Blog,
    false,
  )
  outputs.push(
    Text(
      "blog/index.html",
      @views.render(blog, @views.blog_index(blog, summaries)),
    ),
  )
  outputs.push(Text("blog/atom.xml", atom_feed(config, posts)))
  outputs.push(Text("search-index.json", search_index(pages)))
  for file in prepared.copies {
    outputs.push(Copy(file, file))
  }
  { outputs, warnings: prepared.warnings, }
}

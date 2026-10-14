///|
pub(all) struct Page {
  source : String
  route : String
  kind : Kind
  title : String
  summary : String
  date : String
  authors : Array[String]
  order : Int
  /// A full HTML document: written as it is, without the layout.
  full : Bool
  html : String
  ids : Array[String]
  headings : Array[String]
  /// The "On this page" rail; empty for a full page.
  toc : Array[@model.TocEntry]
  text : String
  mermaid : Bool
}

///|
pub(all) struct Prepared {
  pages : Array[Page]
  /// Repository files to copy to the same path below the output directory.
  copies : Array[String]
  warnings : Array[@model.Problem]
}

///|
fn file_stem(path : String) -> String {
  let name = match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
  @model.strip_extension(name)
}

///|
/// Build one page, or `None` for a skipped draft. Problems go to `problems`.
fn build_page(
  source : SourceFile,
  kind : Kind,
  main_build : Bool,
  problems : Array[@model.Problem],
  warnings : Array[@model.Problem],
) -> Page? {
  let path = source.path
  guard source.text is Some(text) else {
    problems.push(@model.problem(path, "content file has no text"))
    return None
  }
  let fm = @content.parse_front_matter(path, text) catch {
    @model.Invalid(found) => {
      problems.append(found)
      return None
    }
  }
  if fm.flag("draft") {
    if main_build {
      problems.push(@model.problem(path, "draft page in a main build"))
    } else {
      warnings.push(@model.problem(path, "draft page skipped"))
    }
    return None
  }
  let is_html = path.has_suffix(".html")
  let full = is_html && fm.body.to_lower().contains("<html")
  let doc = if is_html {
    @content.analyse_html(fm.body)
  } else {
    @content.render_markdown(path, fm.body) catch {
      @model.Invalid(found) => {
        problems.append(found)
        return None
      }
    }
  }
  let mermaid = if full {
    @content.MermaidPass::{ html: fm.body, warnings: [], needs_client: false, }
  } else {
    @content.render_mermaid_blocks(path, doc.html)
  }
  warnings.append(mermaid.warnings)
  let title = match (fm.text("title"), doc.title) {
    (Some(t), _) => t
    (None, Some(t)) => t
    (None, None) => file_stem(path)
  }
  let summary = fm.text("summary").unwrap_or(doc.summary)
  let order = match fm.text("order") {
    Some(value) =>
      @string.parse_int(value) catch {
        _ => {
          problems.push(@model.problem(path, "`order` must be a whole number"))
          1000
        }
      }
    None => 1000
  }
  let mut date = ""
  let mut authors = []
  let route = match kind {
    Doc(rel) => @model.doc_route(rel)
    Package(name) => @model.package_route(name)
    Landing => "/"
    Post(file) => {
      let parts = @model.post_parts(file)
      if parts is None {
        problems.push(
          @model.problem(
            path, "blog file name must be `YYYY-MM-DD-slug.md` or `.html`, with a real date and a slug of a-z, 0-9 and single `-`",
          ),
        )
      }
      if fm.text("title") is None {
        problems.push(@model.problem(path, "blog post needs `title`"))
      }
      authors = fm.list("authors")
      if authors.is_empty() {
        problems.push(@model.problem(path, "blog post needs `authors`"))
      }
      match (fm.text("date"), parts) {
        (None, _) =>
          problems.push(@model.problem(path, "blog post needs `date`"))
        (Some(d), Some((file_date, _))) if d != file_date =>
          problems.push(
            @model.problem(
              path,
              "`date` \{d} does not match the file name date \{file_date}",
            ),
          )
        _ => ()
      }
      guard parts is Some((file_date, slug)) else { return None }
      date = file_date
      @model.post_route(slug)
    }
    Forbidden | Other => return None
  }
  Some({
    source: path,
    route,
    kind,
    title,
    summary,
    date,
    authors,
    order,
    full,
    html: mermaid.html,
    // A full page is written as it is, so its anchors are the ids it already has.
    ids: if full {
      @content.ids_in(fm.body)
    } else {
      doc.ids
    },
    headings: doc.headings.map(h => h.text),
    toc: if full {
      []
    } else {
      toc_entries(doc.headings)
    },
    text: doc.text,
    mermaid: mermaid.needs_client,
  })
}

///|
/// Routes the generator writes that no source file gives.
let generated_routes : Array[String] = [
  "/", "/docs/", "/blog/", "/blog/atom.xml", "/search-index.json",
]

///|
/// Parse, render and check every source file. Raises all problems together.
pub fn prepare(
  config : @model.SiteConfig,
  sources : Array[SourceFile],
  main_build~ : Bool,
) -> Prepared raise @model.Invalid {
  let problems : Array[@model.Problem] = []
  let warnings : Array[@model.Problem] = []
  let pages : Array[Page] = []
  for source in sources {
    let kind = classify(source.path, config)
    match kind {
      Forbidden =>
        problems.push(
          @model.problem(
            source.path,
            "forbidden path: agent specs, plans and ledgers live in beads",
          ),
        )
      Other => ()
      _ =>
        if build_page(source, kind, main_build, problems, warnings)
          is Some(page) {
          pages.push(page)
        }
    }
  }
  // Every package in `site.json` needs a README.
  for name in config.packages {
    let found = sources
      .iter()
      .any(s => {
        s.path == "pkgs/\{name}/README.md" || s.path == "apps/\{name}/README.md"
      })
    if !found {
      problems.push(
        @model.problem(
          "site/site.json",
          "package `\{name}` in site/site.json has no README.md in pkgs/\{name}/ or apps/\{name}/",
        ),
      )
    }
  }
  // Duplicate routes.
  let owners : Map[String, String] = Map([])
  let unique : Array[Page] = []
  for page in pages {
    match owners.get(page.route) {
      Some(first) =>
        problems.push(
          @model.problem(
            page.source,
            "route `\{page.route}` is also written by `\{first}`",
          ),
        )
      None => {
        owners.set(page.route, page.source)
        unique.push(page)
      }
    }
  }
  // Links.
  let routes : Map[String, String] = Map([])
  for page in unique {
    routes.set(page.source, page.route)
  }
  let site_routes = generated_routes + unique.map(p => p.route)
  let ctx = LinkContext::new(
    config,
    routes,
    sources.map(s => s.path),
    site_routes,
  )
  let anchors : Array[(String, String, String)] = []
  let copies : Array[String] = []
  let linked = unique.map(page => {
    let html = @content.map_urls(page.html, url => {
      let r = resolve(ctx, page.source, url)
      if r.problem is Some(message) {
        problems.push(@model.problem(page.source, message))
      }
      if r.anchor is Some((route, anchor)) {
        anchors.push((page.source, route, anchor))
      }
      if r.copy is Some(file) && !copies.contains(file) {
        copies.push(file)
      }
      r.url
    })
    { ..page, html, }
  })
  // Anchors on pages from source files. Generated routes have no anchors to check.
  let ids : Map[String, Array[String]] = Map([])
  for page in linked {
    ids.set(page.route, page.ids)
  }
  for check in anchors {
    let (from, route, anchor) = check
    if ids.get(route) is Some(found) && !found.contains(anchor) {
      problems.push(
        @model.problem(from, "anchor `#\{anchor}` does not exist on `\{route}`"),
      )
    }
  }
  // Sidebar groups.
  if config.nav is Some(groups) {
    for message in build_grouped_nav(groups, nav_entries(linked)).1 {
      problems.push(@model.problem("site/site.json", message))
    }
  }
  if problems.length() > 0 {
    raise @model.Invalid(problems)
  }
  { pages: linked, copies, warnings, }
}

///|
/// The pages of the docs sidebar: docs and package pages, except `/docs/` itself.
fn nav_entries(pages : Array[Page]) -> Array[NavEntry] {
  pages.filter_map(p => {
    let source = match p.kind {
      Doc(rel) => rel
      Package(name) => "packages/\{name}/README.md"
      _ => return None
    }
    if p.full || p.route == "/docs/" {
      None
    } else {
      Some({ route: p.route, source, title: p.title, order: p.order, })
    }
  })
}

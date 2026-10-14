///|
let config : @model.SiteConfig = {
  title: "Morphir MoonBit",
  description: "Morphir in MoonBit",
  base_path: "/m/",
  site_url: "https://x.io/m/",
  repo_url: "https://github.com/finos/morphir-moonbit",
  packages: [],
  nav: None,
}

///|
fn meta(
  route : String,
  title : String,
  section : @model.Section,
) -> @views.PageMeta {
  { config, route, title, description: "d", section, mermaid: false, }
}

///|
let post : @model.PostSummary = {
  route: "/blog/hello/",
  title: "Hello",
  date: "2026-10-13",
  authors: ["Ada", "Zoë"],
  summary: "First post.",
}

///|
async test "layout has head, islands, nav and main" {
  let m = meta("/docs/a/", "A", Docs)
  let out = @views.render(m, @views.raw("<p>hi</p>"))
  assert_true(
    out.has_prefix("<!DOCTYPE html><html data-base=\"/m/\" lang=\"en\">"),
  )
  assert_true(out.contains("<title>A · Morphir MoonBit</title>"))
  assert_true(
    out.contains("<link href=\"/m/assets/site.css\" rel=\"stylesheet\">"),
  )
  assert_true(
    out.contains(
      "<script src=\"/m/assets/islands.js\" type=\"module\"></script>",
    ),
  )
  assert_true(out.contains("href=\"/m/blog/atom.xml\""))
  assert_true(out.contains("<div id=\"site-search\">"))
  assert_true(out.contains("<div id=\"site-theme\"></div>"))
  assert_true(out.contains("<div id=\"site-nav\"></div>"))
  assert_true(out.contains("class=\"current\""))
  assert_true(
    out.contains(
      "<main id=\"content\"><div class=\"prose\"><p>hi</p></div></main>",
    ),
  )
  assert_false(out.contains("mermaid.min.js"))
}

///|
async test "mermaid pages load the client renderer" {
  let m = { ..meta("/docs/a/", "A", Docs), mermaid: true, }
  let out = @views.render(m, @views.raw(""))
  assert_true(
    out.contains("<script src=\"/m/assets/mermaid.min.js\"></script>"),
  )
}

///|
async test "docs page has sidebar with current page and source link" {
  let nav : Array[@model.NavItem] = [
    { route: "", title: "Adr", depth: 0, },
    { route: "/docs/adr/a/", title: "First", depth: 1, },
  ]
  let m = meta("/docs/adr/a/", "First", Docs)
  let out = @views.render(
    m,
    @views.docs_page(
      m,
      nav,
      "<h1 id=\"first\">First</h1>",
      Some("https://g/x.md"),
    ),
  )
  assert_true(out.contains("<span class=\"nav-label\">Adr</span>"))
  assert_true(
    out.contains(
      "<li class=\"depth-1\"><a aria-current=\"page\" href=\"/m/docs/adr/a/\"",
    ),
  )
  assert_true(out.contains("aria-current=\"page\""))
  assert_true(out.contains("href=\"https://g/x.md\""))
}

///|
async test "docs page lists the page headings in an On this page rail" {
  let m = meta("/docs/a/", "A", Docs)
  let toc : Array[@model.TocEntry] = [
    { id: "overview", text: "Overview", depth: 0, },
    { id: "details", text: "Details & more", depth: 1, },
  ]
  let out = @views.render(m, @views.docs_page(m, [], "<h1>A</h1>", None, toc~))
  inspect(
    out[out.find("<nav aria-label=\"On this page\"").unwrap():out
    .find("</aside></div>")
    .unwrap()],
    content=(
      #|<nav aria-label="On this page" class="docs-toc" id="site-toc"><p class="nav-label">On this page</p><ul><li class="depth-0"><a href="#overview" target="_self">Overview</a></li><li class="depth-1"><a href="#details" target="_self">Details &amp; more</a></li></ul></nav>
    ),
  )
  let bare = @views.render(m, @views.docs_page(m, [], "<h1>A</h1>", None))
  assert_false(bare.contains("docs-toc"))
}

///|
async test "post page and blog index" {
  let m = meta("/blog/hello/", "Hello", Blog)
  let page = @views.render(m, @views.post_page(m, post, "<p>body</p>"))
  assert_true(page.contains("<h1>Hello</h1>"))
  assert_true(page.contains("<time datetime=\"2026-10-13\">2026-10-13</time>"))
  assert_true(page.contains("Ada, Zoë"))
  let index = @views.render(
    meta("/blog/", "Blog", Blog),
    @views.blog_index(meta("/blog/", "Blog", Blog), [post]),
  )
  assert_true(index.contains("href=\"/m/blog/hello/\""))
  assert_true(index.contains("First post."))
}

///|
async test "home page replaces the latest posts marker" {
  let m = meta("/", "Morphir MoonBit", Home)
  let landing = "<section class=\"hero\">h</section>" +
    @views.latest_posts_marker +
    "<section>after</section>"
  let out = @views.render(m, @views.home_page(m, landing, [post]))
  assert_true(out.contains("<title>Morphir MoonBit</title>"))
  assert_true(out.contains("<section class=\"hero\">h</section>"))
  assert_true(out.contains("href=\"/m/blog/hello/\""))
  assert_true(out.contains("<section>after</section>"))
  assert_false(out.contains("data-site=\"latest-posts\""))
}

///|
async test "snapshot: layout" {
  let out = @views.render(meta("/docs/a/", "A", Docs), @views.raw("<p>hi</p>"))
  inspect(
    out,
    content=(
      #|<!DOCTYPE html><html data-base="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>A · Morphir MoonBit</title><meta name="description" content="d"><link href="/m/assets/site.css" rel="stylesheet"><link href="/m/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Morphir MoonBit blog" href="/m/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand"><img src="/m/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Morphir MoonBit</span></a><nav aria-label="Main" class="site-links" id="site-links"><a aria-current="page" href="/m/docs/" target="_self" class="current">Docs</a><a href="/m/blog/" target="_self">Blog</a><a href="/m/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/m/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><div class="prose"><p>hi</p></div></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
}

///|
async test "snapshot: docs page" {
  let nav : Array[@model.NavItem] = [
    { route: "", title: "Adr", depth: 0, },
    { route: "/docs/adr/a/", title: "First", depth: 1, },
  ]
  let m = meta("/docs/adr/a/", "First", Docs)
  let out = @views.render(
    m,
    @views.docs_page(
      m,
      nav,
      "<h1 id=\"first\">First</h1>",
      Some("https://g/x.md"),
    ),
  )
  inspect(
    out,
    content=(
      #|<!DOCTYPE html><html data-base="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>First · Morphir MoonBit</title><meta name="description" content="d"><link href="/m/assets/site.css" rel="stylesheet"><link href="/m/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Morphir MoonBit blog" href="/m/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand"><img src="/m/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Morphir MoonBit</span></a><nav aria-label="Main" class="site-links" id="site-links"><a aria-current="page" href="/m/docs/" target="_self" class="current">Docs</a><a href="/m/blog/" target="_self">Blog</a><a href="/m/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/m/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><div class="docs-layout"><aside class="docs-sidebar"><nav aria-label="Documentation"><ul><li class="depth-0"><span class="nav-label">Adr</span></li><li class="depth-1"><a aria-current="page" href="/m/docs/adr/a/" target="_self" class="current">First</a></li></ul></nav></aside><article class="docs-article"><div class="prose"><h1 id="first">First</h1></div><p class="page-source"><a href="https://g/x.md" target="_self">View source on GitHub</a></p></article></div></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
}

///|
async test "snapshot: post page" {
  let m = meta("/blog/hello/", "Hello", Blog)
  inspect(
    @views.render(m, @views.post_page(m, post, "<p>body</p>")),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Hello · Morphir MoonBit</title><meta name="description" content="d"><link href="/m/assets/site.css" rel="stylesheet"><link href="/m/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Morphir MoonBit blog" href="/m/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand"><img src="/m/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Morphir MoonBit</span></a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a aria-current="page" href="/m/blog/" target="_self" class="current">Blog</a><a href="/m/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/m/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><article class="post"><header><h1>Hello</h1><p class="post-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p></header><div class="prose"><p>body</p></div></article></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
}

///|
async test "snapshot: blog index" {
  let m = meta("/blog/", "Blog", Blog)
  inspect(
    @views.render(m, @views.blog_index(m, [post])),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Blog · Morphir MoonBit</title><meta name="description" content="d"><link href="/m/assets/site.css" rel="stylesheet"><link href="/m/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Morphir MoonBit blog" href="/m/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand"><img src="/m/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Morphir MoonBit</span></a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a aria-current="page" href="/m/blog/" target="_self" class="current">Blog</a><a href="/m/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/m/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><section class="blog-index"><h1>Blog</h1><p><a href="/m/blog/atom.xml" target="_self">Atom feed</a></p><ul class="post-list"><li class="post-card"><a href="/m/blog/hello/" target="_self">Hello</a><p class="post-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p><p>First post.</p></li></ul></section></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
}

///|
async test "snapshot: home page" {
  let m = meta("/", "Morphir MoonBit", Home)
  let landing = "<section class=\"hero\">h</section>" +
    @views.latest_posts_marker +
    "<section>after</section>"
  inspect(
    @views.render(m, @views.home_page(m, landing, [post])),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Morphir MoonBit</title><meta name="description" content="d"><link href="/m/assets/site.css" rel="stylesheet"><link href="/m/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Morphir MoonBit blog" href="/m/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand"><img src="/m/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Morphir MoonBit</span></a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a href="/m/blog/" target="_self">Blog</a><a href="/m/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/m/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><div class="home"><div class="landing"><section class="hero">h</section></div><section class="latest-posts"><h2>Latest posts</h2><ul class="post-list"><li class="post-card"><a href="/m/blog/hello/" target="_self">Hello</a><p class="post-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p><p>First post.</p></li></ul></section><div class="landing"><section>after</section></div></div></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
}

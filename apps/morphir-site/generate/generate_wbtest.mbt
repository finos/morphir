///|
/// Working directory under `moon test` is the module root, `apps/morphir-site`, so
/// "fixtures/content", "assets" and "_build/fixture-site" are relative to it.
async test "generate the fixture site" {
  let out = "_build/fixture-site"
  if @fs.exists(out) {
    @fs.rmdir(out, recursive=true)
  }
  let (warnings, written) = generate_report("fixtures/content", out, true)
  assert_eq(warnings, [])
  let files = list_files(out)
  written.sort_by(compare_units)
  assert_eq(written, files)
  assert_eq(files, [
    "assets/morphir-mark.svg", "assets/site.css", "blog/atom.xml", "blog/first/index.html",
    "blog/index.html", "docs/diagram/index.html", "docs/guide/index.html", "docs/index.html",
    "index.html", "search-index.json",
  ])
  let guide = @fs.read_file("\{out}/docs/guide/index.html").text()
  assert_true(guide.contains("<h2 id=\"install\">Install</h2>"))
  assert_true(guide.contains("class=\"language-moonbit\""))
  let readme = @fs.read_file("\{out}/docs/index.html").text()
  assert_true(readme.contains("href=\"/fixture/docs/guide/#install\""))
  let diagram = @fs.read_file("\{out}/docs/diagram/index.html").text()
  assert_true(diagram.contains("<figure class=\"diagram\"><svg"))
  let home = @fs.read_file("\{out}/index.html").text()
  assert_true(home.contains("href=\"/fixture/blog/first/\""))
  inspect(
    home,
    content=(
      #|<!DOCTYPE html><html data-base="/fixture/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fixture site</title><meta name="description" content="A fixture for the generator test"><link href="/fixture/assets/site.css" rel="stylesheet"><link href="/fixture/assets/morphir-mark.svg" rel="icon" type="image/svg+xml"><link title="Fixture site blog" href="/fixture/blog/atom.xml" rel="alternate" type="application/atom+xml"><script>try{var t=localStorage.getItem('site-theme');if(t&&t!=='system')document.documentElement.dataset.theme=t}catch(e){}</script><script src="/fixture/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/fixture/" target="_self" class="brand"><img src="/fixture/assets/morphir-mark.svg" alt="" width="28" height="28"><span>Fixture site</span></a><nav aria-label="Main" class="site-links" id="site-links"><a href="/fixture/docs/" target="_self">Docs</a><a href="/fixture/blog/" target="_self">Blog</a><a href="/fixture/try/" target="_self">Try Morphir</a><a href="https://github.com/finos/morphir-moonbit" target="_self">GitHub</a></nav><div id="site-search"><a href="/fixture/docs/" target="_self">Search docs</a></div><div id="site-theme"></div><div id="site-nav"></div></header><main id="content"><div class="home"><div class="landing"><section class="hero"><h1 id="fixture">Fixture</h1><a href="/fixture/docs/">Docs</a></section>
      #|</div><section class="latest-posts"><h2>Latest posts</h2><ul class="post-list"><li class="post-card"><a href="/fixture/blog/first/" target="_self">First post</a><p class="post-meta"><time datetime="2026-10-13">2026-10-13</time> · Fixture Author</p><p>The first fixture post.</p></li></ul></section><div class="landing">
      #|</div></div></main><footer class="site-footer"><p>Apache-2.0 · A <a href="https://www.finos.org/" target="_self">FINOS</a> project · <a href="https://morphir.finos.org/" target="_self">Morphir</a></p></footer></body></html>
    ),
  )
  inspect(
    @fs.read_file("\{out}/blog/atom.xml").text(),
    content=(
      #|<?xml version="1.0" encoding="utf-8"?>
      #|<feed xmlns="http://www.w3.org/2005/Atom">
      #|<title>Fixture site blog</title>
      #|<id>https://example.org/fixture/blog/</id>
      #|<link rel="self" href="https://example.org/fixture/blog/atom.xml"/>
      #|<link href="https://example.org/fixture/blog/"/>
      #|<updated>2026-10-13T00:00:00Z</updated>
      #|<entry>
      #|<title>First post</title>
      #|<id>https://example.org/fixture/blog/first/</id>
      #|<link href="https://example.org/fixture/blog/first/"/>
      #|<updated>2026-10-13T00:00:00Z</updated>
      #|<author><name>Fixture Author</name></author>
      #|<summary>The first fixture post.</summary>
      #|<content type="html">&lt;p&gt;The first fixture post.&lt;/p&gt;
      #|</content>
      #|</entry>
      #|</feed>
      #|
    ),
  )
  inspect(
    @fs.read_file("\{out}/search-index.json").text(),
    content=(
      #|[{"route":"/docs/","title":"Fixture docs","section":"Docs","summary":"Read the guide .","headings":["Fixture docs"],"text":"Fixture docs Read the guide ."},{"route":"/docs/diagram/","title":"Diagram","section":"Docs","summary":"","headings":["Diagram"],"text":"Diagram graph TD A --> B"},{"route":"/docs/guide/","title":"Guide","section":"Docs","summary":"","headings":["Guide","Install"],"text":"Guide Install let answer = 42"},{"route":"/blog/first/","title":"First post","section":"Blog","summary":"The first fixture post.","headings":[],"text":"The first fixture post."}]
    ),
  )
}

///|
test "plain text, escape and unescape" {
  assert_eq(
    @content.plain_text("<h1>A <em>b</em> &amp; c</h1>\n<p>d</p>"),
    "A b & c d",
  )
  assert_eq(
    @content.escape("<a href=\"x\">&"),
    "&lt;a href=&quot;x&quot;&gt;&amp;",
  )
  assert_eq(@content.unescape("&lt;b&gt; &amp;amp; &quot;"), "<b> &amp; \"")
}

///|
test "slug" {
  assert_eq(@content.slug("ADR 0001: Versioned IR"), "adr-0001-versioned-ir")
  assert_eq(@content.slug("Café ünïcode"), "caf-ncode")
  assert_eq(@content.slug("!!!"), "section")
}

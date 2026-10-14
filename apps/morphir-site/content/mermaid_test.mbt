///|
test "mermaid block becomes svg" {
  let pass = @content.render_mermaid_blocks(
    "a.md", "<p>x</p><pre><code class=\"language-mermaid\">graph TD\nA --&gt; B\n</code></pre><p>y</p>",
  )
  assert_true(pass.html.has_prefix("<p>x</p><figure class=\"diagram\"><svg"))
  assert_true(pass.html.has_suffix("</svg></figure><p>y</p>"))
  assert_eq(pass.warnings, [])
  assert_false(pass.needs_client)
}

///|
test "unsupported diagram falls back to the client" {
  let pass = @content.render_mermaid_blocks(
    "a.md", "<pre><code class=\"language-mermaid\">gantt\ntitle x\n</code></pre>",
  )
  assert_eq(pass.html, "<pre class=\"mermaid\">gantt\ntitle x\n</pre>")
  assert_eq(pass.warnings.length(), 1)
  assert_true(
    pass.warnings[0].message.has_prefix(
      "Mermaid diagram 1 uses the client renderer",
    ),
  )
  assert_true(pass.needs_client)
}

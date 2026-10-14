///|
/// The result of the Mermaid pass over one page.
pub(all) struct MermaidPass {
  html : String
  warnings : Array[@model.Problem]
  /// True when at least one diagram fell back to the client-side renderer.
  needs_client : Bool
}

///|
let mermaid_open : String = "<pre><code class=\"language-mermaid\">"

///|
let mermaid_close : String = "</code></pre>"

///|
/// Replace each Mermaid code block with an inline SVG. A diagram that does not
/// render stays as `<pre class="mermaid">` source for the client renderer, and
/// gives a warning.
pub fn render_mermaid_blocks(file : String, html : String) -> MermaidPass {
  let out = StringBuilder()
  let warnings = []
  let mut needs_client = false
  let mut rest = html[:]
  let mut index = 0
  while rest.find(mermaid_open) is Some(start) {
    let body = rest[start + mermaid_open.length():]
    guard body.find(mermaid_close) is Some(end) else { break }
    index += 1
    let escaped = body[:end].to_owned()
    out.write_view(rest[:start])
    let svg = @mermaid.render_mermaid(unescape(escaped)) catch {
      error => {
        warnings.push(
          @model.problem(
            file,
            "Mermaid diagram \{index} uses the client renderer: \{error}",
          ),
        )
        needs_client = true
        ""
      }
    }
    if svg == "" {
      out.write_string("<pre class=\"mermaid\">\{escaped}</pre>")
    } else {
      out.write_string("<figure class=\"diagram\">\{svg}</figure>")
    }
    rest = body[end + mermaid_close.length():]
  }
  out.write_view(rest)
  { html: out.to_string(), warnings, needs_client, }
}

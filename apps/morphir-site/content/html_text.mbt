///|
/// Escape text for an HTML text node or a double-quoted attribute value.
pub fn escape(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Undo the entity escapes that cmark writes in text and code. `&amp;` is last, so
/// `&amp;lt;` becomes `&lt;` and not `<`.
pub fn unescape(text : String) -> String {
  text
  .replace_all(old="&lt;", new="<")
  .replace_all(old="&gt;", new=">")
  .replace_all(old="&quot;", new="\"")
  .replace_all(old="&#39;", new="'")
  .replace_all(old="&amp;", new="&")
}

///|
/// The text of an HTML fragment: tags removed, entities decoded, white space collapsed.
pub fn plain_text(html : String) -> String {
  text_of(html, tag_gap=" ")
}

///|
/// The text of inline HTML, such as a heading: like `plain_text`, but a tag adds no
/// space, so `A (<code>b</code>)` is `A (b)`.
pub fn inline_text(html : String) -> String {
  text_of(html, tag_gap="")
}

///|
fn text_of(html : String, tag_gap~ : String) -> String {
  let out = StringBuilder()
  let mut in_tag = false
  for c in html {
    match c {
      '<' => in_tag = true
      '>' if in_tag => {
        in_tag = false
        out.write_string(tag_gap)
      }
      _ if !in_tag => out.write_char(c)
      _ => ()
    }
  }
  unescape(out.to_string())
  .split(" ")
  .flat_map(w => w.split("\n"))
  .filter(w => w.trim() != "")
  .map(w => w.trim().to_owned())
  .collect()
  .join(" ")
}

///|
/// A heading anchor: ASCII letters and digits are kept (lower case), white space,
/// `-` and `_` become one `-`, and every other character is removed.
pub fn slug(text : String) -> String {
  let out = StringBuilder()
  let mut dash = false
  for c in text.to_lower() {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      if dash && out.to_string() != "" {
        out.write_char('-')
      }
      dash = false
      out.write_char(c)
    } else if c == ' ' || c == '-' || c == '_' {
      dash = true
    }
  }
  let s = out.to_string()
  if s == "" {
    "section"
  } else {
    s
  }
}

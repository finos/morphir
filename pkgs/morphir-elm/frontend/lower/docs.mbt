///|
/// The text between `{-|` and `-}`, unchanged, as morphir-elm keeps it.
pub fn doc_text(doc : @ast.Node[String]?) -> String? {
  doc.map(d => {
    let text = d.value
    let start = if text.has_prefix("{-|") { 3 } else { 0 }
    let end = if text.has_suffix("-}") {
      text.length() - 2
    } else {
      text.length()
    }
    text[start:end].to_owned()
  })
}

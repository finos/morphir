///|
/// The words of an Elm name, as morphir-elm `Name.fromString` finds them: an upper-case letter starts a word,
/// lower-case letters continue a letter word, and a digit run is its own word. Other characters split words.
pub fn elm_words(text : String) -> Array[String] {
  let words : Array[String] = []
  let current : Ref[StringBuilder] = Ref(StringBuilder())
  let mut digits = false
  fn flush() {
    let word = current.val.to_string()
    if word != "" {
      words.push(word)
    }
    current.val = StringBuilder()
  }

  for c in text {
    if c >= '0' && c <= '9' {
      if !digits {
        flush()
      }
      digits = true
      current.val.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      flush()
      digits = false
      current.val.write_char(Int32::unsafe_to_char(c.to_int() + 32))
    } else if c >= 'a' && c <= 'z' {
      if digits {
        flush()
      }
      digits = false
      current.val.write_char(c)
    } else {
      flush()
      digits = false
    }
  }
  flush()
  words
}

///|
pub fn elm_name(text : String) -> @ir.Name {
  @ir.Name::from_words(elm_words(text))
}

///|
/// A dotted Elm module or package name, one segment per element.
pub fn elm_path(segments : Array[String]) -> @ir.Path {
  @ir.Path::from_names(segments.map(elm_name))
}

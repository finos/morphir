///|
pub struct Name(@list.List[String]) derive(Eq, Hash)

///|
pub typealias (Name) -> String as NameRenderer

///|
pub fn Name::is_empty(self : Name) -> Bool {
  self.0.is_empty()
}

///|
///Convert a list of strings into a Name.
pub fn Name::from_list(parts : @list.List[String]) -> Name {
  Name(parts)
}

///|
pub fn of(parts : Array[String]) -> Name {
  Name(@list.from_array(parts))
}

///|
pub fn from_string(input : String) -> Name {
  Name::from_string(input)
}

///|
pub fn Name::from_string(name : String) -> Name {
  fn split_into_words(
    input : StringView,
    words : @list.List[String],
  ) -> @list.List[String] {
    lexmatch input with longest {
      ("([a-zA-Z][a-z]*|[0-9]+)" as word, rest) =>
        split_into_words(rest, @list.cons(word.to_string().to_lower(), words))
      (".", rest) => split_into_words(rest, words)
      _ => words.rev()
    }
  }

  Name(split_into_words(name, @list.default()))
}

///|
/// Turns a name into camelCase string.
pub fn Name::to_camel_case(self : Name) -> String {
  match self.0 {
    Empty => ""
    More(first, tail=rest) =>
      first.to_lower() + rest.iter().map(part => capitalize(part)).join("")
  }
}

///|
/// Turns a name into a list of human-readable strings. The only difference
/// compared to to_list is how it handles abbreviations. They will be
/// turned into a single uppercase word instead of separate single-letter words.
/// For example, "valueInUSD" becomes ["value", "in", "USD"] instead of
/// ["value", "in", "u", "s", "d"].
pub fn to_human_words(self : Name) -> @list.List[String] {
  loop ([], StringBuilder::new(), self.0) {
    (acc, abbrev, Empty) if abbrev.is_empty() => break @list.from_array(acc)
    (acc, abbrev, Empty) => break @list.from_array(acc + [abbrev.to_string()])
    (acc, abbrev, More(first, tail=rest)) if first.length() == 1 =>
      continue (
          acc,
          {
            abbrev..write_string(first.to_upper())
            abbrev
          },
          rest,
        )
    (acc, abbrev, More(first, tail=rest)) if abbrev.is_empty() =>
      continue (acc + [first], StringBuilder::new(), rest)
    (acc, abbrev, More(first, tail=rest)) =>
      continue (acc + [abbrev.to_string(), first], StringBuilder::new(), rest)
  }
}

///|
///Turns a name into a list of human-readable strings with the first word capitalized. The only difference
///compared to [`to_list`](#to_list) is how it handles abbreviations. They will
///be turned into a single upper-case word instead of separate single-character
///words.
pub fn Name::to_human_words_title(self : Name) -> @list.List[String] {
  match self.to_human_words() {
    Empty => @list.default()
    More(first, tail=rest) => @list.cons(capitalize(first), rest)
  }
}

///|
/// Turns a name into kebab-case string.
pub fn Name::to_kebab_case(self : Name) -> String {
  self.to_human_words().iter().map(part => part.to_lower()).join("-")
}

///|
/// Converts a name to a list of strings.
pub fn Name::to_list(self : Name) -> @list.List[String] {
  self.0
}

///|
/// Turns a name into snake_case string.
pub fn Name::to_snake_case(self : Name) -> String {
  self.to_human_words().iter().join("_")
}

///|
/// Turns a name into TitleCase string.
pub fn Name::to_title_case(self : Name) -> String {
  self.0.iter().map(part => capitalize(part)).join("")
}

///|
pub impl @codec.ToMorphirJson for Name with to_json(
  self,
  options : @codec.MorphirJsonOptions,
) -> Json {
  match options.name_encoding {
    @codec.NameJsonEncoding::AsString => Json::string(self.0.iter().join("-"))
    @codec.NameJsonEncoding::AsList => self.0.to_json()
  }
}

///|
pub impl Show for Name with output(self, logger) {
  logger.write_string(self.to_kebab_case())
}

///|
fn capitalize(input : String) -> String {
  match input {
    [first, .. rest] if first.is_ascii_alphabetic() =>
      first.to_ascii_uppercase().to_string() + rest.to_string()
    _ => input
  }
}

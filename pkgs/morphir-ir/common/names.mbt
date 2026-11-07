///|
/// A word and an initialism remain distinct in the semantic name.
#derive(Eq, Compare, Hash, Debug)
pub(all) enum NameSegment {
  Word(String)
  Initialism(String)
}

///|
/// Immutable storage keeps names safe as map keys.
#derive(Eq, Compare, Hash, Debug)
pub struct Name {
  segments : @list.List[NameSegment]
}

///|
#derive(Eq, Debug)
pub(all) suberror NameError {
  InvalidName(String)
}

///|
/// Decode legacy words using the upstream maximal-single-letter-run rule.
pub fn Name::from_words(words : Array[String]) -> Name {
  let segments : Array[NameSegment] = []
  let mut i = 0
  while i < words.length() {
    let start = i
    while i < words.length() &&
          words[i].length() == 1 &&
          words[i] >= "a" &&
          words[i] <= "z" {
      i += 1
    }
    if i - start > 1 {
      segments.push(
        Initialism(words[start:i].iter().collect().join("").to_upper()),
      )
    } else if i > start {
      segments.push(Word(words[start]))
    } else {
      segments.push(Word(words[i]))
      i += 1
    }
  }
  { segments: @list.List::from_iter(segments.iter()), }
}

///|
/// Parse the v4 canonical name grammar without guessing from camel case.
pub fn Name::parse(text : String) -> Name raise NameError {
  let segments : Array[NameSegment] = []
  for part in text.split("-") {
    if part.is_empty() {
      raise InvalidName(text)
    }
    let mut lower = true
    let mut upper = true
    let mut has_upper = false
    for character in part {
      let digit = character >= '0' && character <= '9'
      lower = lower && (digit || (character >= 'a' && character <= 'z'))
      upper = upper && (digit || (character >= 'A' && character <= 'Z'))
      has_upper = has_upper || (character >= 'A' && character <= 'Z')
    }
    if !lower && !upper {
      raise InvalidName(text)
    }
    segments.push(
      if has_upper {
        Initialism(part.to_owned())
      } else {
        Word(part.to_owned())
      },
    )
  }
  { segments: @list.List::from_iter(segments.iter()), }
}

///|
/// A fresh array; changing it cannot change the name.
pub fn Name::to_segments(self : Name) -> Array[NameSegment] {
  self.segments.iter().collect()
}

///|
/// Legacy spelling. Some canonical v4 names have no lossless legacy spelling;
/// version migration must check the round trip instead of silently collapsing them.
pub fn Name::to_words(self : Name) -> Array[String] {
  let words : Array[String] = []
  for segment in self.segments {
    match segment {
      Word(word) => words.push(word)
      Initialism(initialism) =>
        for character in initialism.to_lower() {
          words.push(character.to_string())
        }
    }
  }
  words
}

///|
pub fn Name::to_canonical(self : Name) -> String {
  self.segments
  .iter()
  .map(segment => {
    match segment {
      Word(text) | Initialism(text) => text
    }
  })
  .collect()
  .join("-")
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct Path {
  segments : @list.List[Name]
}

///|
pub fn Path::from_names(segments : Array[Name]) -> Path {
  { segments: @list.List::from_iter(segments.iter()), }
}

///|
pub fn Path::parse(text : String) -> Path raise NameError {
  let segments : Array[Name] = []
  for segment in text.split("/") {
    segments.push(Name::parse(segment.to_owned()))
  }
  Path::from_names(segments)
}

///|
pub fn Path::to_names(self : Path) -> Array[Name] {
  self.segments.iter().collect()
}

///|
pub fn Path::to_canonical(self : Path) -> String {
  self.segments.iter().map(Name::to_canonical).collect().join("/")
}

///|
pub type PackageName = Path

///|
pub type ModuleName = Path

///|
#derive(Eq, Compare, Hash, Debug)
pub(all) struct FQName {
  package_name : PackageName
  module_name : ModuleName
  local_name : Name
}

///|
pub fn FQName::parse(text : String) -> FQName raise NameError {
  let package_and_local = text.split(":").collect()
  if package_and_local.length() != 2 {
    raise InvalidName(text)
  }
  let module_and_name = package_and_local[1].split("#").collect()
  if module_and_name.length() != 2 {
    raise InvalidName(text)
  }
  {
    package_name: Path::parse(package_and_local[0].to_owned()),
    module_name: Path::parse(module_and_name[0].to_owned()),
    local_name: Name::parse(module_and_name[1].to_owned()),
  }
}

///|
pub fn FQName::to_canonical(self : FQName) -> String {
  self.package_name.to_canonical() +
  ":" +
  self.module_name.to_canonical() +
  "#" +
  self.local_name.to_canonical()
}

///|
pub struct Path(@list.List[@name.Name]) derive(Eq, Hash, Show)

///|
///Convert a list of Names into a Path.
pub fn Path::from_list(parts : @list.List[@name.Name]) -> Path {
  Path(parts)
}

pub fn of(parts:Array[@name.Name]) -> Path {
  Path(@list.from_array(parts))
}

///|
///Translates a string into a path by splitting it into names along special characters.
///The algorithm will treat any non-word charaters that are not spaces as a path separator.
pub fn from_string(input : String) -> Path {
  let segments = loop (input.view(), [], StringBuilder::new()) {
    ([], acc, name_str) if name_str.is_empty() => break acc
    ([], acc, name_str) => break acc + [@name.from_string(name_str.to_string())]
    (rest, acc, name_str) =>
      lexmatch rest with longest {
        ("[^\w\s]+", remaining) =>
          continue (
              remaining,
              acc + [@name.from_string(name_str.to_string())],
              StringBuilder::new(),
            )
        ("." as next, remaining) =>
          continue (
              remaining,
              acc,
              {
                name_str.write_char(next)
                name_str
              },
            )
        _ => {
          let name_input = name_str.to_string() + rest.to_string()
          break acc + [@name.from_string(name_input)]
        }
      }
  }
  Path(@list.from_array(segments))
}

///|
pub fn to_list(self : Path) -> @list.List[@name.Name] {
  self.0
}

///|
pub fn Path::to_listqq(self : Path) -> @list.List[@name.Name] {
  self.0
}

///|
pub fn Path::to_string(
  self : Path,
  renderer : @name.NameRenderer,
  separator : String,
) -> String {
  self.0.iter().map(renderer).join(separator)
}

///|
/// Checks if a Path is a prefix of another.
/// A Path `p1` is a prefix of Path `p2` if all the names in `p1`
/// appear in the same order at the start of `p2`.
pub fn Path::is_prefix_of(self : Path, path : Path) -> Bool {
  loop (self.0, path.0) {
    (Empty, _) => break true
    (_, Empty) => break false
    (More(self_head, tail=rest_self), More(other_head, tail=rest_other)) =>
      if self_head == other_head {
        continue (rest_self, rest_other)
      } else {
        break false
      }
  }
}

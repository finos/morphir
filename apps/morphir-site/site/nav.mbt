///|
pub(all) struct NavEntry {
  route : String
  title : String
  /// Position among siblings; 1000 when the page has no `order`.
  order : Int
}

///|
fn segments(route : String) -> Array[String] {
  route[6:].split("/").filter(s => s != "").map(s => s.to_owned()).collect()
}

///|
fn label(name : String) -> String {
  if name == "packages" {
    return "Packages"
  }
  let words = name.split("-").map(w => w.to_owned()).collect()
  let first = words[0]
  if first == "" {
    return name
  }
  let head : String = first[:1].to_upper().to_owned() + first[1:].to_owned()
  let parts = [head]
  for w in words[1:] {
    parts.push(w)
  }
  parts.join(" ")
}

///|
/// Alphabetical order by UTF-16 code unit. `String::compare` orders by length first.
fn compare_titles(a : String, b : String) -> Int {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// The docs sidebar: a depth-first walk of the routes below `/docs/`. At each level,
/// leaves and directories are sorted by `order`, then by title. A directory without
/// a README is a label. `/docs/` itself is not listed.
pub fn build_nav(entries : Array[NavEntry]) -> Array[@model.NavItem] {
  let items = []
  fn walk(prefix : Array[String], depth : Int) -> Unit {
    let names : Array[String] = []
    for e in entries {
      let s = segments(e.route)
      if s.length() > prefix.length() &&
        s[:prefix.length()].iter().collect() == prefix &&
        !names.contains(s[prefix.length()]) {
        names.push(s[prefix.length()])
      }
    }
    let rows = names.map(name => {
      let path = prefix + [name]
      let own = entries
        .search_by(e => segments(e.route) == path)
        .map(i => entries[i])
      let has_children = entries
        .iter()
        .any(e => {
          let s = segments(e.route)
          s.length() > path.length() &&
          s[:path.length()].iter().collect() == path
        })
      (name, path, own, has_children)
    })
    rows.sort_by((a, b) => {
      let order_a = a.2.map(e => e.order).unwrap_or(1000)
      let order_b = b.2.map(e => e.order).unwrap_or(1000)
      let title_a = a.2.map(e => e.title).unwrap_or(label(a.0))
      let title_b = b.2.map(e => e.title).unwrap_or(label(b.0))
      if order_a != order_b {
        order_a - order_b
      } else {
        compare_titles(title_a, title_b)
      }
    })
    for row in rows {
      let (name, path, own, has_children) = row
      match own {
        Some(e) =>
          items.push(@model.NavItem::{ route: e.route, title: e.title, depth, })
        None =>
          items.push(@model.NavItem::{ route: "", title: label(name), depth, })
      }
      if has_children {
        walk(path, depth + 1)
      }
    }
  }

  walk([], 0)
  items
}

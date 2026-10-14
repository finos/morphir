///|
pub(all) struct NavEntry {
  route : String
  /// The source path below `docs/`; a package is `packages/NAME/README.md`.
  source : String
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

///|
/// A `nav` glob: `*` matches any characters and `?` one character, never `/`.
pub fn glob_match(pattern : String, name : String) -> Bool {
  let p = pattern.to_array()
  let n = name.to_array()
  fn go(i : Int, j : Int) -> Bool {
    if i == p.length() {
      return j == n.length()
    }
    match p[i] {
      '*' => {
        let mut k = j
        while true {
          if go(i + 1, k) {
            return true
          }
          if k == n.length() || n[k] == '/' {
            return false
          }
          k += 1
        }
        false
      }
      '?' => j < n.length() && n[j] != '/' && go(i + 1, j + 1)
      c => j < n.length() && n[j] == c && go(i + 1, j + 1)
    }
  }
  go(0, 0)
}

///|
fn is_glob(item : String) -> Bool {
  item.contains("*") || item.contains("?")
}

///|
/// The top-level entry of a page: `NAME.md` for a page directly below `docs/`,
/// else `DIR/`.
fn top_level(source : String) -> String {
  match source.find("/") {
    Some(i) => source[:i + 1].to_owned()
    None => source
  }
}

///|
/// The sidebar for `site.json` `nav` groups. Exact items claim their entry first, then
/// globs claim the entries that are left, in `nav` order. Each group starts with a
/// label row; a group whose items match nothing is left out. A directory with a
/// README is a link with its pages below it; a directory without one puts its pages
/// directly in the group. Returns the rows and the problems: exact items without a
/// page, and top-level entries that no item claims.
pub fn build_grouped_nav(
  groups : Array[@model.NavGroup],
  entries : Array[NavEntry],
) -> (Array[@model.NavItem], Array[String]) {
  let tops : Array[String] = []
  for e in entries {
    let top = top_level(e.source)
    if !tops.contains(top) {
      tops.push(top)
    }
  }
  let claims : Map[String, Array[String]] = Map([])
  let claimed : Array[String] = []
  let problems : Array[String] = []
  for g in groups {
    for item in g.items {
      if !is_glob(item) {
        if tops.contains(item) {
          claims.set(item, [item])
          claimed.push(item)
        } else {
          problems.push("`nav` entry `\{item}` matches no page")
        }
      }
    }
  }
  for g in groups {
    for item in g.items {
      if is_glob(item) {
        let found = tops.filter(t => !claimed.contains(t) && glob_match(item, t))
        claimed.append(found)
        claims.set(item, found)
      }
    }
  }
  for top in tops {
    if !claimed.contains(top) {
      let what = if top.has_suffix("/") { "directory" } else { "page" }
      problems.push("docs \{what} `\{top}` is not in `nav`")
    }
  }
  let items : Array[@model.NavItem] = []
  for g in groups {
    let rows : Array[@model.NavItem] = []
    for item in g.items {
      for top in sorted_tops(claims.get(item).unwrap_or([]), entries) {
        rows.append(top_rows(top, entries))
      }
    }
    if !rows.is_empty() {
      items.push({ route: "", title: g.group, depth: 0, })
      items.append(rows)
    }
  }
  (items, problems)
}

///|
/// The entry that stands for a top-level page or directory: the page itself, or the
/// directory's README.
fn own_entry(top : String, entries : Array[NavEntry]) -> NavEntry? {
  let route = if top.has_suffix("/") {
    @model.doc_route(top + "README.md")
  } else {
    @model.doc_route(top)
  }
  entries.search_by(e => e.route == route).map(i => entries[i])
}

///|
fn sorted_tops(
  tops : Array[String],
  entries : Array[NavEntry],
) -> Array[String] {
  let keyed = tops.map(top => {
    let (order, title) = match own_entry(top, entries) {
      Some(e) => (e.order, e.title)
      None => (1000, label(top[:top.length() - 1].to_owned()))
    }
    (top, order, title)
  })
  keyed.sort_by((a, b) => {
    if a.1 != b.1 {
      a.1 - b.1
    } else {
      compare_titles(a.2, b.2)
    }
  })
  keyed.map(k => k.0)
}

///|
/// The rows of one top-level entry. A directory without a README loses its label row
/// and one level of depth, so its pages sit directly in the group.
fn top_rows(top : String, entries : Array[NavEntry]) -> Array[@model.NavItem] {
  let rows = build_nav(entries.filter(e => top_level(e.source) == top))
  if rows.length() > 0 && rows[0].route == "" {
    rows[1:].iter().map(r => { ..r, depth: r.depth - 1, }).collect()
  } else {
    rows
  }
}

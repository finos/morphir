///|
/// A row of the project tree: a folder or a file.
pub(all) enum Item {
  Dir(@ids.SourcePath)
  File(@ids.SourcePath)
} derive(Eq, Debug)

///|
/// Where a new file goes: the project root or a folder.
pub(all) enum Folder {
  Root
  In(@ids.SourcePath)
} derive(Eq, Debug)

///|
/// The folders and files of a project. Folders come from the file paths; a `Branch` label holds more than one
/// segment when a chain of single folders is compacted, as `src/Shop` for `src` holding only `Shop`.
pub(all) enum Node {
  Branch(@ids.SourcePath, String, Array[Node])
  Leaf(@ids.SourcePath, String)
} derive(Eq, Debug)

///|
/// One visible row of the tree, in display order.
pub(all) struct Row {
  item : Item
  label : String
  /// Zero for rows at the root.
  depth : Int32
  /// Folders only: the children are shown.
  expanded : Bool
  /// The folder row that holds this row; `None` at the root.
  parent : @ids.SourcePath?
  /// `aria-setsize` and the one-based `aria-posinset` among the siblings.
  siblings : Int32
  position : Int32
  /// The problems of the file, or of all the files in the folder.
  problems : Int32
} derive(Eq, Debug)

///|
pub fn Item::path(self : Item) -> @ids.SourcePath {
  match self {
    Dir(path) | File(path) => path
  }
}

///|
/// The last segment of a path: `Api.elm` for `src/Shop/Api.elm`.
pub fn base_name(path : @ids.SourcePath) -> String {
  let text = path.to_string()
  match text.rev_find("/") {
    Some(slash) => text.unsafe_substring(start=slash + 1, end=text.length())
    None => text
  }
}

///|
/// The folder that holds `path`.
pub fn parent_of(path : @ids.SourcePath) -> Folder {
  let text = path.to_string()
  guard text.rev_find("/") is Some(slash) else { return Root }
  let parent = @ids.SourcePath::parse(text.unsafe_substring(start=0, end=slash)) catch {
    _ => return Root
  }
  In(parent)
}

///|
/// The path text of `name` in this folder. `name` may hold `/` to name subfolders.
pub fn Folder::join(self : Folder, name : String) -> String {
  match self {
    Root => name
    In(path) => path.to_string() + "/" + name
  }
}

///|
/// The folders that hold `path`, outermost first: `src` and `src/Shop` for `src/Shop/Api.elm`.
pub fn ancestors(path : @ids.SourcePath) -> Array[@ids.SourcePath] {
  let found : Array[@ids.SourcePath] = []
  let mut folder = parent_of(path)
  while folder is In(parent) {
    found.insert(0, parent)
    folder = parent_of(parent)
  }
  found
}

///|
/// True when `path` is inside the folder `dir`, at any depth.
pub fn is_inside(path : @ids.SourcePath, dir : @ids.SourcePath) -> Bool {
  path.to_string().has_prefix(dir.to_string() + "/")
}

///|
fn segments(path : @ids.SourcePath) -> Array[String] {
  path.to_string().split("/").map(StringView::to_owned).collect()
}

///|
/// The nodes of the paths below `prefix` (the folder at segment `depth`), folders first, each sorted by code unit.
fn level(
  entries : Array[(@ids.SourcePath, Array[String])],
  depth : Int32,
  prefix : String,
  compact : Bool,
) -> Array[Node] {
  let folder_names : Array[String] = []
  let groups : Map[String, Array[(@ids.SourcePath, Array[String])]] = Map([])
  let files : Array[Node] = []
  for entry in entries {
    let (path, parts) = entry
    let name = parts[depth]
    if parts.length() == depth + 1 {
      files.push(Leaf(path, name))
    } else {
      match groups.get(name) {
        Some(group) => group.push(entry)
        None => {
          folder_names.push(name)
          groups[name] = [entry]
        }
      }
    }
  }
  folder_names.sort_by((a, b) => a.lexical_compare(b))
  files.sort_by((a, b) => {
    match (a, b) {
      (Leaf(_, x), Leaf(_, y)) => x.lexical_compare(y)
      _ => 0
    }
  })
  let folders : Array[Node] = []
  for name in folder_names {
    let text = prefix + name
    // A prefix of a valid path is a valid path; the guard only keeps a refusal from aborting.
    let path = @ids.SourcePath::parse(text) catch { _ => continue }
    let children = level(
      groups.get(name).unwrap_or([]),
      depth + 1,
      text + "/",
      compact,
    )
    folders.push(
      match children {
        [Branch(inner, label, grandchildren)] if compact =>
          Branch(inner, name + "/" + label, grandchildren)
        _ => Branch(path, name, children)
      },
    )
  }
  folders + files
}

///|
/// The tree of a project's files. Each distinct path appears once as a `Leaf`. With `compact`, a folder that holds
/// only one folder shares its row.
pub fn build_tree(
  paths : Array[@ids.SourcePath],
  compact~ : Bool = true,
) -> Array[Node] {
  let seen : Array[@ids.SourcePath] = []
  let entries : Array[(@ids.SourcePath, Array[String])] = []
  for path in paths {
    if !seen.contains(path) {
      seen.push(path)
      entries.push((path, segments(path)))
    }
  }
  level(entries, 0, "", compact)
}

///|
/// The paths of every folder row.
pub fn folders_of(tree : Array[Node]) -> Array[@ids.SourcePath] {
  let found : Array[@ids.SourcePath] = []
  fn walk(nodes : Array[Node]) -> Unit {
    for node in nodes {
      if node is Branch(path, _, children) {
        found.push(path)
        walk(children)
      }
    }
  }

  walk(tree)
  found
}

///|
fn problems_of(node : Node, counts : Map[String, Int32]) -> Int32 {
  match node {
    Leaf(path, _) => counts.get(path.to_string()).unwrap_or(0)
    Branch(_, _, children) =>
      children.fold(init=0, (sum, child) => sum + problems_of(child, counts))
  }
}

///|
/// The visible rows: the children of a folder in `collapsed` are hidden. `counts` holds the problems of each file
/// path; a folder shows the sum over its files.
pub fn rows(
  tree : Array[Node],
  collapsed : Array[@ids.SourcePath],
  counts : Map[String, Int32],
) -> Array[Row] {
  let out : Array[Row] = []
  fn walk(
    nodes : Array[Node],
    depth : Int32,
    parent : @ids.SourcePath?,
  ) -> Unit {
    for index, node in nodes {
      match node {
        Branch(path, label, children) => {
          let expanded = !collapsed.contains(path)
          out.push({
            item: Dir(path),
            label,
            depth,
            expanded,
            parent,
            siblings: nodes.length(),
            position: index + 1,
            problems: problems_of(node, counts),
          })
          if expanded {
            walk(children, depth + 1, Some(path))
          }
        }
        Leaf(path, name) =>
          out.push({
            item: File(path),
            label: name,
            depth,
            expanded: false,
            parent,
            siblings: nodes.length(),
            position: index + 1,
            problems: problems_of(node, counts),
          })
      }
    }
  }

  walk(tree, 0, None)
  out
}

///|
/// A key on a focused row.
pub(all) enum Move {
  Up
  Down
  Left
  Right
  First
  Last
  /// Enter: open a file and leave the tree, or toggle a folder.
  Activate
  /// Space: open a file and stay in the tree, or toggle a folder.
  Preview
  Typeahead(String)
} derive(Eq, Debug)

///|
/// What a move does to the tree.
pub(all) enum Step {
  FocusOn(Item)
  Expand(@ids.SourcePath)
  Collapse(@ids.SourcePath)
  OpenFile(@ids.SourcePath)
  Stay
} derive(Eq, Debug)

///|
/// The tree pattern of WAI-ARIA: Up and Down move between visible rows, Right opens a folder or enters it, Left
/// closes a folder or goes to its parent, Home and End go to the ends, Enter and Space open a file or toggle a
/// folder, and a letter goes to the next row whose name starts with it.
pub fn step(rows : Array[Row], focused : Item?, motion : Move) -> Step {
  if rows.is_empty() {
    return Stay
  }
  let current = match focused {
    Some(item) => rows.search_by(row => row.item == item)
    None => None
  }
  let focus_at = fn(index : Int32) { FocusOn(rows[index].item) }
  match (motion, current) {
    (First, _) | (Down, None) => focus_at(0)
    (Last, _) | (Up, None) => focus_at(rows.length() - 1)
    (Down, Some(i)) =>
      if i + 1 < rows.length() {
        focus_at(i + 1)
      } else {
        Stay
      }
    (Up, Some(i)) => if i > 0 { focus_at(i - 1) } else { Stay }
    (_, None) => Stay
    (Right, Some(i)) =>
      match rows[i] {
        { item: Dir(path), expanded: false, .. } => Expand(path)
        { item: Dir(_), expanded: true, .. } =>
          if i + 1 < rows.length() && rows[i + 1].depth > rows[i].depth {
            focus_at(i + 1)
          } else {
            Stay
          }
        _ => Stay
      }
    (Left, Some(i)) =>
      match rows[i] {
        { item: Dir(path), expanded: true, .. } => Collapse(path)
        { parent: Some(parent), .. } => FocusOn(Dir(parent))
        _ => Stay
      }
    (Activate | Preview, Some(i)) =>
      match rows[i] {
        { item: Dir(path), expanded: true, .. } => Collapse(path)
        { item: Dir(path), .. } => Expand(path)
        { item: File(path), .. } => OpenFile(path)
      }
    (Typeahead(letter), Some(i)) => {
      let wanted = letter.to_lower()
      for offset in 1..<(rows.length() + 1) {
        let row = rows[(i + offset) % rows.length()]
        if row.label.to_lower().has_prefix(wanted) ||
          base_label(row).to_lower().has_prefix(wanted) {
          return FocusOn(row.item)
        }
      }
      Stay
    }
  }
}

///|
/// The name typeahead compares: the last segment of a compacted folder label.
fn base_label(row : Row) -> String {
  match row.label.rev_find("/") {
    Some(slash) =>
      row.label.unsafe_substring(start=slash + 1, end=row.label.length())
    None => row.label
  }
}

///|
pub extend Item with Eq::{not_equal, equal}

///|
pub extend Item with @debug.Debug::{to_repr}

///|
pub extend Folder with Eq::{not_equal, equal}

///|
pub extend Folder with @debug.Debug::{to_repr}

///|
pub extend Node with Eq::{not_equal, equal}

///|
pub extend Node with @debug.Debug::{to_repr}

///|
pub extend Row with Eq::{not_equal, equal}

///|
pub extend Row with @debug.Debug::{to_repr}

///|
pub extend Move with Eq::{not_equal, equal}

///|
pub extend Move with @debug.Debug::{to_repr}

///|
pub extend Step with Eq::{not_equal, equal}

///|
pub extend Step with @debug.Debug::{to_repr}

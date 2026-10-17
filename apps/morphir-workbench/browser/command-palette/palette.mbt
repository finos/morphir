///|
/// A command the palette lists. A command that exists but cannot run now is shown dimmed with its reason.
pub(all) struct Command {
  id : @keys.CommandId
  title : String
  /// A short group name shown beside the title, such as `Build` or `File`.
  category : String
  enabled : Bool
  reason : String
} derive(Eq, Debug)

///|
/// An entry of a second list that a command opens, such as a language. `value` is the id the workbench uses.
pub(all) struct Choice {
  value : String
  label : String
  detail : String
} derive(Eq, Debug)

///|
/// What an entry stands for.
pub(all) enum Value {
  OfFile(@ids.SourcePath)
  OfCommand(@keys.CommandId)
  OfChoice(String)
} derive(Eq, Debug)

///|
/// One line of the palette list.
pub(all) struct Entry {
  value : Value
  label : String
  /// Indexes of the characters of `label` that the query matched.
  label_marks : Array[Int32]
  detail : String
  detail_marks : Array[Int32]
  /// The shortcut of a command, or a note such as `current`.
  hint : String
  /// The `aria-keyshortcuts` value of a command's shortcut.
  keys : String
  enabled : Bool
  reason : String
  recent : Bool
  /// The icon class.
  icon : String
} derive(Eq, Debug)

///|
/// What the palette lists: project files, commands, or the second list of a command.
pub(all) enum Mode {
  Files
  Commands
  Choose(@keys.CommandId)
} derive(Eq, Debug)

///|
pub(all) struct State {
  open : Bool
  /// The command whose second list is open, and that list's prompt.
  choosing : (@keys.CommandId, String)?
  /// The text in the input; a leading `>` lists commands.
  query : String
  index : Int32
  /// Commands run from the palette, most recent first.
  recent : Array[@keys.CommandId]
} derive(Eq, Debug)

///|
pub fn State::new() -> State {
  { open: false, choosing: None, query: "", index: 0, recent: [], }
}

///|
pub fn State::mode(self : State) -> Mode {
  match self.choosing {
    Some((command, _)) => Choose(command)
    None => if self.query.has_prefix(">") { Commands } else { Files }
  }
}

///|
/// The query without the `>` that selects commands.
fn State::search(self : State) -> String {
  match self.mode() {
    Commands => self.query.unsafe_substring(start=1, end=self.query.length())
    _ => self.query
  }
}

///|
pub(all) enum Action {
  /// Opens the palette on files (`""`), commands (`">"`) or any text.
  Show(String)
  /// Opens the second list of a command with its prompt.
  Ask(@keys.CommandId, String)
  Query(String)
  Key(@keys.Chord)
  Hover(Int32)
  Pick(Int32)
  Close
}

///|
/// What an action asks the workbench to do.
pub(all) enum Outcome {
  Stay
  Closed
  Opened(@ids.SourcePath)
  Run(@keys.CommandId)
  Chose(@keys.CommandId, String)
} derive(Eq, Debug)

///|
let recent_limit = 8

///|
let page = 8

///|
/// The icon class of a file, by its extension.
fn file_icon(path : String) -> String {
  if path.has_suffix(".elm") {
    "icon-lang-elm"
  } else if path.has_suffix(".mbt") {
    "icon-lang-moonbit"
  } else if path.has_suffix(".scm") {
    "icon-lang-scheme"
  } else if path.has_suffix(".json") {
    "icon-lang-json"
  } else {
    "icon-document"
  }
}

///|
/// Extra score for a query that matches the file name itself, so `api` puts `Api.elm` before `api/Main.elm`.
let name_bonus = 12

///|
fn file_entry(path : @ids.SourcePath, search : String) -> (Int32, Entry)? {
  let text = path.to_string()
  let slash = match text.rev_find("/") {
    Some(index) => index
    None => -1
  }
  let name = text.unsafe_substring(start=slash + 1, end=text.length())
  let folder = if slash < 0 {
    ""
  } else {
    text.unsafe_substring(start=0, end=slash)
  }
  let entry = {
    value: OfFile(path),
    label: name,
    label_marks: [],
    detail: folder,
    detail_marks: [],
    hint: "",
    keys: "",
    enabled: true,
    reason: "",
    recent: false,
    icon: file_icon(text),
  }
  match fuzzy(search, name) {
    Some(found) =>
      Some(
        (found.score + name_bonus, { ..entry, label_marks: found.positions, }),
      )
    None =>
      match fuzzy(search, text) {
        // Positions before the slash fall in the folder, the rest in the name.
        Some(found) => {
          let label_offset = slash + 1
          let detail_marks = found.positions.filter(p => p < slash)
          let label_marks = found.positions
            .filter(p => p >= label_offset)
            .map(p => p - label_offset)
          Some((found.score, { ..entry, label_marks, detail_marks, }))
        }
        None => None
      }
  }
}

///|
/// Sorts scored entries best first; equal scores keep their order.
fn ranked(scored : Array[(Int32, Int32, Entry)]) -> Array[Entry] {
  scored.sort_by((a, b) => if a.0 != b.0 { b.0 - a.0 } else { a.1 - b.1 })
  scored.map(item => item.2)
}

///|
/// The entries the palette shows for its query. Files sort by path with no query; commands put recent ones first;
/// with a query, the best fuzzy matches come first and ties keep that order.
pub fn entries(
  state : State,
  files~ : Array[@ids.SourcePath],
  commands~ : Array[Command],
  choices~ : Array[Choice],
  mac~ : Bool,
) -> Array[Entry] {
  let search = state.search().trim().to_owned()
  match state.mode() {
    Files => {
      let sorted = files.copy()
      sorted.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
      let scored : Array[(Int32, Int32, Entry)] = []
      for index, path in sorted {
        if file_entry(path, search) is Some((score, entry)) {
          scored.push((score, index, entry))
        }
      }
      ranked(scored)
    }
    Commands => {
      let bindings = @keys.keymap()
      // Recent commands come first, most recent first; the order of the rest is the registry's.
      let order = fn(command : Command) {
        match state.recent.search(command.id) {
          Some(rank) => rank
          None => recent_limit + commands.search(command).unwrap_or(0)
        }
      }
      let scored : Array[(Int32, Int32, Entry)] = []
      for command in commands {
        guard fuzzy(search, command.title) is Some(found) else { continue }
        let chord = @keys.shortcut(bindings, command.id, mac~)
        scored.push(
          (
            found.score,
            order(command),
            {
              value: OfCommand(command.id),
              label: command.title,
              label_marks: found.positions,
              detail: if command.enabled {
                command.category
              } else {
                command.reason
              },
              detail_marks: [],
              hint: chord.map(c => c.label(mac~)).unwrap_or(""),
              keys: chord.map(c => c.aria(mac~)).unwrap_or(""),
              enabled: command.enabled,
              reason: command.reason,
              recent: state.recent.contains(command.id),
              icon: "icon-command",
            },
          ),
        )
      }
      ranked(scored)
    }
    Choose(_) => {
      let scored : Array[(Int32, Int32, Entry)] = []
      for index, choice in choices {
        guard fuzzy(search, choice.label) is Some(found) else { continue }
        scored.push(
          (
            found.score,
            index,
            {
              value: OfChoice(choice.value),
              label: choice.label,
              label_marks: found.positions,
              detail: "",
              detail_marks: [],
              hint: choice.detail,
              keys: "",
              enabled: true,
              reason: "",
              recent: false,
              icon: "icon-choice",
            },
          ),
        )
      }
      ranked(scored)
    }
  }
}

///|
fn State::moved(self : State, by : Int32, count : Int32) -> State {
  if count == 0 {
    return { ..self, index: 0, }
  }
  let index = ((self.index + by) % count + count) % count
  { ..self, index, }
}

///|
/// Moves the palette by one action. `entries` are the entries it shows now, from `entries`.
pub fn State::update(
  self : State,
  action : Action,
  entries : Array[Entry],
) -> (State, Outcome) {
  let count = entries.length()
  match action {
    Show(query) =>
      ({ ..self, open: true, choosing: None, query, index: 0, }, Stay)
    Ask(command, prompt) =>
      (
        {
          ..self,
          open: true,
          choosing: Some((command, prompt)),
          query: "",
          index: 0,
        },
        Stay,
      )
    Query(query) => ({ ..self, query, index: 0, }, Stay)
    Hover(index) if index >= 0 && index < count => ({ ..self, index, }, Stay)
    Hover(_) => (self, Stay)
    Close =>
      ({ ..self, open: false, choosing: None, query: "", index: 0, }, Closed)
    Key(chord) =>
      if !chord.is_typing() {
        (self, Stay)
      } else {
        match chord.key {
          "ArrowDown" => (self.moved(1, count), Stay)
          "ArrowUp" => (self.moved(-1, count), Stay)
          "PageDown" =>
            (
              {
                ..self,
                index: if count == 0 {
                  0
                } else {
                  (self.index + page).min(count - 1)
                },
              },
              Stay,
            )
          "PageUp" => ({ ..self, index: (self.index - page).max(0), }, Stay)
          "Enter" => self.update(Pick(self.index), entries)
          "Escape" => self.update(Close, entries)
          _ => (self, Stay)
        }
      }
    Pick(index) => {
      guard entries.get(index) is Some(entry) && entry.enabled else {
        return (
          {
            ..self,
            index: if index >= 0 && index < count {
              index
            } else {
              self.index
            },
          },
          Stay,
        )
      }
      let closed = { ..self, open: false, choosing: None, query: "", index: 0, }
      match entry.value {
        OfFile(path) => (closed, Opened(path))
        OfCommand(command) => {
          let recent = [command] + self.recent.filter(c => c != command)
          (
            {
              ..closed,
              recent: recent[:recent_limit.min(recent.length())].to_owned(),
            },
            Run(command),
          )
        }
        OfChoice(value) =>
          match self.choosing {
            Some((command, _)) => (closed, Chose(command, value))
            None => (closed, Closed)
          }
      }
    }
  }
}

///|
pub extend Command with Eq::{not_equal, equal}

///|
pub extend Command with @debug.Debug::{to_repr}

///|
pub extend Choice with Eq::{not_equal, equal}

///|
pub extend Choice with @debug.Debug::{to_repr}

///|
pub extend Value with Eq::{not_equal, equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend Entry with Eq::{not_equal, equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
pub extend Mode with Eq::{not_equal, equal}

///|
pub extend Mode with @debug.Debug::{to_repr}

///|
pub extend State with Eq::{not_equal, equal}

///|
pub extend State with @debug.Debug::{to_repr}

///|
pub extend Outcome with Eq::{not_equal, equal}

///|
pub extend Outcome with @debug.Debug::{to_repr}

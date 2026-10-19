///|
priv enum State {
  /// We await the start of the stream.
  StreamStart
  ImplicitDocumentStart
  DocumentStart
  DocumentContent
  DocumentEnd
  BlockNode
  // BlockNodeOrIndentlessSequence
  // FlowNode
  BlockSequenceFirstEntry
  BlockSequenceEntry
  IndentlessSequenceEntry
  BlockMappingFirstKey
  BlockMappingKey
  BlockMappingValue
  FlowSequenceFirstEntry
  FlowSequenceEntry
  FlowSequenceEntryMappingKey
  FlowSequenceEntryMappingValue
  FlowSequenceEntryMappingEnd
  FlowMappingFirstKey
  FlowMappingKey
  FlowMappingValue
  FlowMappingEmptyValue
  End
} derive(Eq)

///|
struct Parser {
  lexer : Lexer
  states : Array[State]
  mut state : State
  mut token : Token?
  mut current : (Event, Marker)?
  anchors : @hashmap.HashMap[String, Int32]
  mut anchor_id : Int32
  /// The tag directives (`%TAG`) the parser has encountered.
  ///
  /// Key is the handle, and value is the prefix.
  mut tags : @hashmap.HashMap[String, String]
  /// Make tags global across all documents.
  mut keep_tags : Bool
}

///|
/// Create a parser for `str`.
///
/// `lenient_quoted_scalar_indentation`, an opt-in js-yaml compatibility
/// setting, accepts multi-line single- and double-quoted scalars whose
/// continuation lines are not indented enough, as js-yaml does.
///
/// In block context, the continuation lines of a quoted (flow) scalar must be
/// indented: `nb-double-multi-line(n)` and `nb-single-multi-line(n)` fold
/// their lines with `s-flow-line-prefix(n)`, which starts with `s-indent(n)`,
/// and the value of a block mapping is a node at indentation `n+1`. This is
/// therefore an error, as in [test
/// QB6E](https://github.com/yaml/yaml-test-suite/blob/ccfa74e56afb53da960847ff6e6976c0a0825709/src/QB6E.yaml)
/// of the yaml-test-suite:
///
/// ```yaml
/// config:
///   themeCSS: "a
///   b"
/// ```
///
/// js-yaml (used by mermaid and many other tools) does not check the
/// indentation of these lines and accepts such documents. With
/// `lenient_quoted_scalar_indentation=true`, so does this parser: `themeCSS` above is `"a b"`. Exactly
/// one thing is relaxed: the indentation of the continuation lines of single-
/// and double-quoted scalars, including the line holding the closing quote,
/// may be anything, down to column 0. The leading white space of such a line
/// (spaces, and also tabs, since there is no indentation left for them to
/// break) is still not content, and line folding, escapes and the stripping
/// of white space around line breaks are unchanged. The scalar may be the
/// value of a block collection entry or sit inside a flow collection nested
/// in one (js-yaml accepts both); the indentation of the tokens following the
/// closing quote on its last line is not checked either, as it is the
/// indentation of that line. Everything else keeps the YAML 1.2 rules:
/// - a document marker (`---` or `...` followed by a blank) at the start of a
///   line inside a quoted scalar is still an error, as is the end of input
///   before the closing quote (js-yaml rejects both too);
/// - plain and block (`|`, `>`) scalars must be indented as before (js-yaml
///   rejects under-indented plain scalars too);
/// - a flow collection line that starts with a new entry or with a closing
///   bracket must be indented as before.
///
/// Folding follows YAML in both modes, also where js-yaml differs: js-yaml
/// keeps the white space before a line break of a quoted scalar (`"a  \n  b"`
/// is `"a   b"` there, `"a b"` here), and drops the empty lines following an
/// escaped line break (a `\` at the end of a line followed by an empty line
/// is `""` there, a line feed here, as `l-empty` in `s-double-escaped(n)`).
///
/// The default is `false`: strict YAML 1.2. The setting is fixed for the
/// life of the parser, since it changes how the input is scanned.
#alias(new, deprecated)
pub fn Parser::Parser(
  str : StringView,
  lenient_quoted_scalar_indentation~ : Bool = false,
) -> Parser {
  let lexer = Lexer::new(str)
  lexer.lenient_quoted_scalar_indentation = lenient_quoted_scalar_indentation
  Parser::{
    lexer,
    states: Array(capacity=40),
    state: State::StreamStart,
    token: None,
    current: None,
    anchors: @hashmap.HashMap([]),
    // valid anchor_id starts from 1
    anchor_id: 1,
    tags: @hashmap.HashMap([]),
    keep_tags: false,
  }
}

///|
/// Whether to keep tags across multiple documents when parsing.
///
/// This behavior is non-standard as per the YAML specification but can be encountered in the
/// wild. This boolean allows enabling this non-standard extension. This would result in the
/// parser accepting input from [test
/// QLJ7](https://github.com/yaml/yaml-test-suite/blob/ccfa74e56afb53da960847ff6e6976c0a0825709/src/QLJ7.yaml)
/// of the yaml-test-suite:
///
/// ```yaml
/// %TAG !prefix! tag:example.com,2011:
/// --- !prefix!A
/// a: b
/// --- !prefix!B
/// c: d
/// --- !prefix!C
/// e: f
/// ```
///
/// With `keep_tags` set to `false`, the above YAML is rejected. As per the specification, tags
/// only apply to the document immediately following them. This would error on `!prefix!B`.
///
/// With `keep_tags` set to `true`, the above YAML is accepted by the parser.
pub fn Parser::keep_tags(self : Parser, value : Bool) -> Unit {
  self.keep_tags = value
}

///|
/// Try to load the next event and return it, consuming it from `self`.
/// # Errors
/// Returns `ScanError` when loading the next event fails.
fn Parser::next_token(self : Parser) -> (Event, Marker) raise YamlError {
  let current = self.current
  self.current = None
  match current {
    Some(x) => x
    None => self.parse()
  }
}

///|

///|
fn Parser::peek_token(self : Parser) -> Token raise YamlError {
  match self.token {
    None => {
      let token = self.scan_next_token()
      self.token = Some(token)
      token
    }
    Some(tok) => tok
  }
}

///|
fn Parser::scan_next_token(self : Parser) -> Token raise YamlError {
  let token = self.lexer.next()
  match token {
    None =>
      match self.lexer.get_error() {
        None =>
          raise YamlError::YamlError(
            mark=self.lexer.get_marker(),
            info="unexpected eof",
          )
        Some(e) => raise e
      }
    Some(tok) => tok
  }
}

///|
fn Parser::parse(self : Parser) -> (Event, Marker) raise YamlError {
  if self.state == State::End {
    return (Event::StreamEnd, self.lexer.get_marker())
  }
  self.state_machine()
}

///|
/// Load the YAML from the stream in `self`, pushing events into `recv`.
///
/// The contents of the stream are parsed and the corresponding events are sent into the
/// recveiver. For detailed explanations about how events work, see `EventReceiver`.
///
/// If `multi` is set to `true`, the parser will allow parsing of multiple YAML documents
/// inside the stream.
///
/// The receiver must implement `MarkedEventReceiver`. An `EventReceiver` can be used by
/// wrapping it in a type that implements `MarkedEventReceiver` and forwards each event,
/// ignoring its marker.
/// # Errors
/// Returns `YamlError` when loading fails.
pub fn[R : MarkedEventReceiver] Parser::load(
  self : Parser,
  recv : R,
  multi : Bool,
) -> Unit raise YamlError {
  if !self.lexer.stream_started() {
    let (ev, mark) = self.next_token()
    if ev != Event::StreamStart {
      raise YamlError::YamlError(
        mark~,
        info="did not find expected <stream-start>",
      )
    }
    recv.on_event(ev, mark)
  }
  if self.lexer.stream_ended() {
    recv.on_event(Event::StreamEnd, self.lexer.get_marker())
    return
  }
  while true {
    let (ev, mark) = self.next_token()
    if ev == Event::StreamEnd {
      recv.on_event(ev, mark)
      return
    }

    // clear anchors before a new document
    self.anchors.clear()
    self.load_document(ev, mark, recv)
    if !multi {
      break
    }
  }
}

///|
fn[R : MarkedEventReceiver] Parser::load_document(
  self : Parser,
  first_ev : Event,
  mark : Marker,
  recv : R,
) -> Unit raise YamlError {
  if first_ev != Event::DocumentStart {
    raise YamlError::YamlError(
      mark~,
      info="did not find expected <document-start>",
    )
  }
  recv.on_event(first_ev, mark)
  let (ev, mark) = self.next_token()
  self.load_node(ev, mark, recv)

  // DOCUMENT-END is expected.
  let (ev, mark) = self.next_token()
  guard! ev == Event::DocumentEnd
  recv.on_event(ev, mark)
}

///|
fn[R : MarkedEventReceiver] Parser::load_node(
  self : Parser,
  first_ev : Event,
  mark : Marker,
  recv : R,
) -> Unit raise YamlError {
  match first_ev {
    Event::Alias(..) | Event::Scalar(..) => recv.on_event(first_ev, mark)
    Event::SequenceStart(..) => {
      recv.on_event(first_ev, mark)
      self.load_sequence(recv)
    }
    Event::MappingStart(..) => {
      recv.on_event(first_ev, mark)
      self.load_mapping(recv)
    }
    _ => {
      println("UNREACHABLE EVENT: \{first_ev.to_repr()}")
      panic()
    }
  }
}

///|
fn[R : MarkedEventReceiver] Parser::load_sequence(
  self : Parser,
  recv : R,
) -> Unit raise YamlError {
  let (ev, mark) = self.next_token()
  let mut ev = ev
  let mut mark = mark
  while ev != Event::SequenceEnd {
    self.load_node(ev, mark, recv)

    // next event
    let (next_ev, next_mark) = self.next_token()
    ev = next_ev
    mark = next_mark
  }
  recv.on_event(ev, mark)
}

///|
fn[R : MarkedEventReceiver] Parser::load_mapping(
  self : Parser,
  recv : R,
) -> Unit raise YamlError {
  let (key_ev, key_mark) = self.next_token()
  let mut key_ev = key_ev
  let mut key_mark = key_mark
  while key_ev != Event::MappingEnd {
    // key
    self.load_node(key_ev, key_mark, recv)
    // value
    let (ev, mark) = self.next_token()
    self.load_node(ev, mark, recv)

    // next event
    let (ev, mark) = self.next_token()
    key_ev = ev
    key_mark = mark
  }
  recv.on_event(key_ev, key_mark)
}

///|
/// Skip the next token from the scanner.
fn Parser::skip(self : Parser) -> Unit {
  self.token = None
}

///|
fn Parser::state_machine(self : Parser) -> (Event, Marker) raise YamlError {
  match self.state {
    FlowMappingEmptyValue => self.flow_mapping_value(true)
    FlowMappingValue => self.flow_mapping_value(false)
    FlowMappingKey => self.flow_mapping_key(false)
    FlowMappingFirstKey => self.flow_mapping_key(true)
    FlowSequenceEntryMappingEnd => self.flow_sequence_entry_mapping_end()
    FlowSequenceEntryMappingValue => self.flow_sequence_entry_mapping_value()
    FlowSequenceEntryMappingKey => self.flow_sequence_entry_mapping_key()
    FlowSequenceEntry => self.flow_sequence_entry(false)
    FlowSequenceFirstEntry => self.flow_sequence_entry(true)
    BlockMappingValue => self.block_mapping_value()
    BlockMappingKey => self.block_mapping_key(false)
    BlockMappingFirstKey => self.block_mapping_key(true)
    IndentlessSequenceEntry => self.indentless_sequence_entry()
    BlockSequenceEntry => self.block_sequence_entry(false)
    BlockSequenceFirstEntry => self.block_sequence_entry(true)
    BlockNode => self.parse_node(true, false)
    DocumentEnd => self.document_end()
    DocumentContent => self.document_content()
    DocumentStart => self.document_start(false)
    ImplicitDocumentStart => self.document_start(true)
    StreamStart => self.stream_start()
    // impossible case
    End => panic()
  }
}

///|
fn Parser::flow_mapping_key(
  self : Parser,
  first : Bool,
) -> (Event, Marker) raise YamlError {
  if first {
    ignore(self.peek_token())
    self.skip()
  }
  let marker = match self.peek_token() {
    { marker, token_type: TokenType::FlowMappingEnd, } => marker
    { marker, token_type: _, } => {
      if !first {
        match self.peek_token() {
          { marker: _, token_type: TokenType::FlowEntry, } => self.skip()
          { marker, token_type: _, } =>
            raise YamlError::YamlError(
              mark=marker,
              info="while parsing a flow mapping, did not find expected ',' or '}'",
            )
        }
      }
      match self.peek_token() {
        { marker: _, token_type: TokenType::Key, } => {
          self.skip()
          if self.peek_token()
            is {
              marker,
              token_type: TokenType::Value
              | TokenType::FlowEntry
              | TokenType::FlowMappingEnd,
            } {
            self.state = State::FlowMappingValue
            return (Event::empty_scalar(), marker)
          }
          self.push_state(State::FlowMappingValue)
          return self.parse_node(false, false)
        }
        { marker: _, token_type: TokenType::Value, } => {
          self.state = State::FlowMappingValue
          return (Event::empty_scalar(), marker)
        }
        { marker: _, token_type: TokenType::FlowMappingEnd, } => ()
        _ => {
          self.push_state(State::FlowMappingEmptyValue)
          return self.parse_node(false, false)
        }
      }
      marker
    }
  }
  self.pop_state()
  self.skip()
  (Event::MappingEnd, marker)
}

///|
fn Parser::flow_mapping_value(
  self : Parser,
  empty : Bool,
) -> (Event, Marker) raise YamlError {
  let marker = {
    if empty {
      let { marker, token_type: _, } = self.peek_token()
      self.state = State::FlowMappingKey
      return (Event::empty_scalar(), marker)
    }
    match self.peek_token() {
      { marker, token_type: TokenType::Value, } => {
        self.skip()
        match self.peek_token().token_type {
          TokenType::FlowEntry | TokenType::FlowMappingEnd => ()
          _ => {
            self.push_state(State::FlowMappingKey)
            return self.parse_node(false, false)
          }
        }
        marker
      }
      { marker, token_type: _, } => marker
    }
  }
  self.state = State::FlowMappingKey
  (Event::empty_scalar(), marker)
}

///|
fn Parser::block_mapping_key(
  self : Parser,
  first : Bool,
) -> (Event, Marker) raise YamlError {
  // skip BlockMappingStart
  if first {
    ignore(self.peek_token())
    self.skip()
  }
  match self.peek_token() {
    { marker: _, token_type: TokenType::Key, } => {
      self.skip()
      if self.peek_token()
        is {
          marker,
          token_type: TokenType::Key
          | TokenType::Value
          | TokenType::BlockEnd,
        } {
        self.state = State::BlockMappingValue
        (Event::empty_scalar(), marker)
      } else {
        self.push_state(State::BlockMappingValue)
        self.parse_node(true, true)
      }
    }
    // libyaml failed to parse spec 1.2, ex8.18
    { marker, token_type: TokenType::Value, } => {
      self.state = State::BlockMappingValue
      (Event::empty_scalar(), marker)
    }
    { marker, token_type: TokenType::BlockEnd, } => {
      self.pop_state()
      self.skip()
      (Event::MappingEnd, marker)
    }
    { marker, token_type: _, } =>
      raise YamlError::YamlError(
        mark=marker,
        info="while parsing a block mapping, did not find expected key",
      )
  }
}

///|
fn Parser::block_mapping_value(
  self : Parser,
) -> (Event, Marker) raise YamlError {
  match self.peek_token() {
    { marker: _, token_type: TokenType::Value, } => {
      self.skip()
      if self.peek_token()
        is {
          marker,
          token_type: TokenType::Key
          | TokenType::Value
          | TokenType::BlockEnd,
        } {
        self.state = State::BlockMappingKey
        (Event::empty_scalar(), marker)
      } else {
        self.push_state(State::BlockMappingKey)
        self.parse_node(true, true)
      }
    }
    { marker, token_type: _, } => {
      self.state = State::BlockMappingKey
      (Event::empty_scalar(), marker)
    }
  }
}

///|
fn Parser::flow_sequence_entry(
  self : Parser,
  first : Bool,
) -> (Event, Marker) raise YamlError {
  // skip FlowMappingStart
  if first {
    ignore(self.peek_token())
    self.skip()
  }
  match self.peek_token() {
    { marker, token_type: TokenType::FlowSequenceEnd, } => {
      self.pop_state()
      self.skip()
      return (Event::SequenceEnd, marker)
    }
    { marker: _, token_type: TokenType::FlowEntry, } if !first => self.skip()
    { marker, token_type: _, } if !first =>
      raise YamlError::YamlError(
        mark=marker,
        info="while parsing a flow sequence, expected ',' or ']'",
      )
    _ => ()
  }
  match self.peek_token() {
    { marker, token_type: TokenType::FlowSequenceEnd, } => {
      self.pop_state()
      self.skip()
      (Event::SequenceEnd, marker)
    }
    { marker, token_type: TokenType::Key, } => {
      self.state = State::FlowSequenceEntryMappingKey
      self.skip()
      (Event::MappingStart(id=0, tag=None), marker)
    }
    _ => {
      self.push_state(State::FlowSequenceEntry)
      self.parse_node(false, false)
    }
  }
}

///|
fn Parser::flow_sequence_entry_mapping_key(
  self : Parser,
) -> (Event, Marker) raise YamlError {
  if self.peek_token()
    is {
      marker,
      token_type: TokenType::Value
      | TokenType::FlowEntry
      | TokenType::FlowSequenceEnd,
    } {
    self.skip()
    self.state = State::FlowSequenceEntryMappingValue
    (Event::empty_scalar(), marker)
  } else {
    self.push_state(State::FlowSequenceEntryMappingValue)
    self.parse_node(false, false)
  }
}

///|
fn Parser::flow_sequence_entry_mapping_value(
  self : Parser,
) -> (Event, Marker) raise YamlError {
  match self.peek_token() {
    { marker: _, token_type: TokenType::Value, } => {
      self.skip()
      self.state = State::FlowSequenceEntryMappingValue
      if self.peek_token()
        is {
          marker,
          token_type: TokenType::FlowEntry
          | TokenType::FlowSequenceEnd,
        } {
        self.state = State::FlowSequenceEntryMappingEnd
        (Event::empty_scalar(), marker)
      } else {
        self.push_state(State::FlowSequenceEntryMappingEnd)
        self.parse_node(false, false)
      }
    }
    { marker, token_type: _, } => {
      self.state = State::FlowSequenceEntryMappingEnd
      (Event::empty_scalar(), marker)
    }
  }
}

///|
fn Parser::flow_sequence_entry_mapping_end(self : Parser) -> (Event, Marker) {
  self.state = State::FlowSequenceEntry
  (Event::MappingEnd, self.lexer.get_marker())
}

///|
fn Parser::indentless_sequence_entry(
  self : Parser,
) -> (Event, Marker) raise YamlError {
  match self.peek_token() {
    { marker: _, token_type: TokenType::BlockEntry, } => ()
    { marker, token_type: _, } => {
      self.pop_state()
      return (Event::SequenceEnd, marker)
    }
  }
  self.skip()
  if self.peek_token()
    is {
      marker,
      token_type: TokenType::BlockEntry
      | TokenType::Key
      | TokenType::Value
      | TokenType::BlockEnd,
    } {
    self.state = State::IndentlessSequenceEntry
    (Event::SequenceEnd, marker)
  } else {
    self.push_state(State::IndentlessSequenceEntry)
    self.parse_node(true, false)
  }
}

///|
fn Parser::block_sequence_entry(
  self : Parser,
  first : Bool,
) -> (Event, Marker) raise YamlError {
  // BLOCK-SEQUENCE-START
  if first {
    let _ = self.peek_token()
    self.skip()
  }
  match self.peek_token() {
    { marker, token_type: TokenType::BlockEnd, } => {
      self.pop_state()
      self.skip()
      (Event::SequenceEnd, marker)
    }
    { marker: _, token_type: TokenType::BlockEntry, } => {
      self.skip()
      if self.peek_token()
        is { marker, token_type: TokenType::BlockEntry | TokenType::BlockEnd, } {
        self.state = State::BlockSequenceEntry
        (Event::empty_scalar(), marker)
      } else {
        self.push_state(State::BlockSequenceEntry)
        self.parse_node(true, false)
      }
    }
    { marker, token_type: _, } =>
      raise YamlError::YamlError(
        mark=marker,
        info="while parsing a block collection, did not find expected '-' indicator",
      )
  }
}

///|
fn Parser::document_end(self : Parser) -> (Event, Marker) raise YamlError {
  let mut explicit_end = false
  let marker = match self.peek_token() {
    { marker, token_type: TokenType::DocumentEnd, } => {
      explicit_end = true
      self.skip()
      marker
    }
    { marker, token_type: _, } => marker
  }
  if !self.keep_tags {
    self.tags.clear()
  }
  if explicit_end {
    self.state = State::ImplicitDocumentStart
  } else {
    if self.peek_token()
      is {
        marker,
        token_type: TokenType::VersionDirective(..)
        | TokenType::TagDirective(..),
      } {
      raise YamlError::YamlError(
        mark=marker,
        info="missing explicit document end marker before directive",
      )
    }
    self.state = State::DocumentStart
  }
  (Event::DocumentEnd, marker)
}

///|
fn Parser::document_content(self : Parser) -> (Event, Marker) raise YamlError {
  match self.peek_token() {
    {
      marker,
      token_type: TokenType::VersionDirective(..)
      | TokenType::TagDirective(..)
      | TokenType::DocumentStart
      | TokenType::DocumentEnd
      | TokenType::StreamEnd,
    } => {
      self.pop_state()
      // empty scalar
      (Event::empty_scalar(), marker)
    }
    _ => self.parse_node(true, false)
  }
}

///|
fn Parser::parse_node(
  self : Parser,
  block : Bool,
  indentless_sequence : Bool,
) -> (Event, Marker) raise YamlError {
  let mut anchor_id = 0
  let mut tag = None
  match self.peek_token() {
    { marker: _, token_type: TokenType::Alias(_), } => {
      self.pop_state()
      if self.fetch_token() is { marker, token_type: TokenType::Alias(name), } {
        match self.anchors.get(name) {
          None =>
            raise YamlError::YamlError(
              mark=marker,
              info="while parsing node, found unknown anchor",
            )
          Some(id) => return (Event::Alias(id~), marker)
        }
      }
      panic()
    }
    { marker: _, token_type: TokenType::Anchor(_), } =>
      if self.fetch_token() is { marker, token_type: TokenType::Anchor(name), } {
        anchor_id = self.register_anchor(name, marker)
        if self.peek_token().token_type is TokenType::Tag(..) {
          if self.fetch_token().token_type is TokenType::Tag(handle~, suffix~) {
            tag = Some(self.resolve_tag(marker, handle, suffix))
          } else {
            panic()
          }
        }
      } else {
        panic()
      }
    { marker, token_type: TokenType::Tag(..), } =>
      if self.fetch_token().token_type is TokenType::Tag(handle~, suffix~) {
        tag = Some(self.resolve_tag(marker, handle, suffix))
        if self.peek_token().token_type is TokenType::Anchor(_) {
          if self.fetch_token()
            is { marker, token_type: TokenType::Anchor(name), } {
            anchor_id = self.register_anchor(name, marker)
          } else {
            panic()
          }
        }
      } else {
        panic()
      }
    _ => ()
  }
  match self.peek_token() {
    { marker, token_type: TokenType::BlockEntry, } if indentless_sequence => {
      self.state = State::IndentlessSequenceEntry
      (Event::SequenceStart(id=anchor_id, tag~), marker)
    }
    { marker: _, token_type: TokenType::Scalar(_), } => {
      self.pop_state()
      if self.fetch_token()
        is { marker, token_type: TokenType::Scalar(style, value), } {
        (Event::Scalar(value~, style~, id=anchor_id, tag~), marker)
      } else {
        panic()
      }
    }
    { marker, token_type: TokenType::FlowSequenceStart, } => {
      self.state = State::FlowSequenceFirstEntry
      (Event::SequenceStart(id=anchor_id, tag~), marker)
    }
    { marker, token_type: TokenType::FlowMappingStart, } => {
      self.state = State::FlowMappingFirstKey
      (Event::MappingStart(id=anchor_id, tag~), marker)
    }
    { marker, token_type: TokenType::BlockSequenceStart, } if block => {
      self.state = State::BlockSequenceFirstEntry
      (Event::SequenceStart(id=anchor_id, tag~), marker)
    }
    { marker, token_type: TokenType::BlockMappingStart, } if block => {
      self.state = State::BlockMappingFirstKey
      (Event::MappingStart(id=anchor_id, tag~), marker)
    }
    // ex 7.2, an empty scalar can follow a secondary tag
    { marker, token_type: _, } if tag is Some(_) || anchor_id > 0 => {
      self.pop_state()
      (Event::empty_scalar_with_anchor(anchor_id, tag), marker)
    }
    { marker, token_type: _, } =>
      raise YamlError::YamlError(
        mark=marker,
        info="while parsing a node, did not find expected node content",
      )
  }
}

///|
/// Resolve a tag from the handle and the suffix.
fn Parser::resolve_tag(
  self : Parser,
  mark : Marker,
  handle : String,
  suffix : String,
) -> Tag raise YamlError {
  if handle == "!!" {
    // "!!" is a shorthand for "tag:yaml.org,2002:". However, that default can be
    // overridden.
    match self.tags.get("!!") {
      Some(prefix) => Tag::{ handle: prefix, suffix, }
      None => Tag::{ handle: "tag:yaml.org,2002:", suffix, }
    }
  } else if handle.is_empty() && suffix == "!" {
    // "!" introduces a local tag. Local tags may have their prefix overridden.
    match self.tags.get("") {
      Some(prefix) => Tag::{ handle: prefix, suffix, }
      None => Tag::{ handle: "", suffix, }
    }
  } else {
    // Lookup handle in our tag directives.
    let prefix = self.tags.get(handle)
    if prefix is Some(prefix) {
      Tag::{ handle: prefix, suffix, }
      // Otherwise, it may be a local handle. With a local handle, the handle is set to
      // "!" and the suffix to whatever follows it ("!foo" -> ("!", "foo")).
      // If the handle is of the form "!foo!", this cannot be a local handle and we need
      // to error.
    } else if handle.length() >= 2 &&
      handle.has_prefix("!") &&
      handle.has_suffix("!") {
      raise YamlError::YamlError(mark~, info="the handle wasn't declared")
    } else {
      Tag::{ handle, suffix, }
    }
  }
}

///|
fn Parser::register_anchor(self : Parser, name : String, _ : Marker) -> Int32 {
  // anchors can be overridden/reused
  let new_id = self.anchor_id
  self.anchor_id += 1
  self.anchors[name] = new_id
  new_id
}

///|
fn Parser::fetch_token(self : Parser) -> Token {
  let token = self.token
  self.token = None
  token.unwrap_or_else(() => {
    println("fetch_token needs to be preceded by peek_token")
    panic()
  })
}

///|
fn Parser::pop_state(self : Parser) -> Unit {
  self.state = self.states.pop().unwrap()
}

///|
fn Parser::document_start(
  self : Parser,
  implicit : Bool,
) -> (Event, Marker) raise YamlError {
  while self.peek_token().token_type is TokenType::DocumentEnd {
    self.skip()
  }
  match self.peek_token() {
    { marker, token_type: TokenType::StreamEnd, } => {
      self.state = State::End
      self.skip()
      (Event::StreamEnd, marker)
    }
    {
      marker: _,
      token_type: TokenType::VersionDirective(_)
      | TokenType::TagDirective(_)
      | TokenType::DocumentStart,
    } =>
      // explicit document
      self.explicit_document_start()
    { marker, .. } if implicit => {
      self.parser_process_directives()
      self.push_state(State::DocumentEnd)
      self.state = State::BlockNode
      (Event::DocumentStart, marker)
    }
    _ => self.explicit_document_start()
  }
}

///|
fn Parser::push_state(self : Parser, state : State) -> Unit raise YamlError {
  guard self.states.length() < self.lexer.nesting_limit + 3 else {
    raise YamlError(mark=self.lexer.get_marker(), info="yaml_depth_limit")
  }
  self.states.push(state)
}

///|
fn Parser::explicit_document_start(
  self : Parser,
) -> (Event, Marker) raise YamlError {
  self.parser_process_directives()
  match self.peek_token() {
    { marker, token_type: TokenType::DocumentStart, } => {
      self.push_state(State::DocumentEnd)
      self.state = State::DocumentContent
      self.skip()
      (Event::DocumentStart, marker)
    }
    { marker, .. } =>
      raise YamlError::YamlError(
        mark=marker,
        info="did not find expected <document-start>",
      )
  }
}

///|
fn Parser::parser_process_directives(self : Parser) -> Unit raise YamlError {
  let mut version_directive_received = false
  while true {
    let tags = @hashmap.HashMap([])
    match self.peek_token() {
      { marker, token_type: TokenType::VersionDirective(..), } => {
        // XXX parsing with warning according to spec
        if version_directive_received {
          raise YamlError::YamlError(
            mark=marker,
            info="duplicate version directive",
          )
        }
        version_directive_received = true
      }
      { marker, token_type: TokenType::TagDirective(handle~, prefix~), } => {
        if tags.contains(handle) {
          raise YamlError::YamlError(
            mark=marker,
            info="the TAG directive must only be given at most once per handle in the same document",
          )
        }
        tags[handle] = prefix
      }
      _ => break
    }
    self.tags = tags
    self.skip()
  }
}

///|
fn Parser::stream_start(self : Parser) -> (Event, Marker) raise YamlError {
  match self.peek_token() {
    { marker, token_type: TokenType::StreamStart, } => {
      self.state = State::ImplicitDocumentStart
      self.skip()
      (Event::StreamStart, marker)
    }
    { marker, .. } =>
      raise YamlError::YamlError(
        mark=marker,
        info="did not find expected <stream-start>",
      )
  }
}

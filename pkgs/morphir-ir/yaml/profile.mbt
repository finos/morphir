///|
/// Independent budgets apply before source parsing, scanner buffer appends,
/// event pulls, node allocation, container pushes and semantic assembly.
pub(all) struct Limits {
  max_bytes : Int32
  max_events : Int32
  max_nodes : Int32
  max_depth : Int32
  max_scalar_units : Int32
  max_assembly_nodes : Int32
}

///|
pub fn Limits::default() -> Limits {
  {
    max_bytes: 16 * 1024 * 1024,
    max_events: 400000,
    max_nodes: 100000,
    max_depth: 128,
    max_scalar_units: 4 * 1024 * 1024,
    max_assembly_nodes: 100000,
  }
}

///|
priv enum Frame {
  Sequence(Array[Json], String)
  Mapping(Map[String, Json], Ref[String?], String)
}

///|
fn cursor(stack : Array[Frame]) -> String raise @wire.CodecError {
  match stack.last() {
    None => "/"
    Some(Sequence(items, path)) => path + "/" + items.length().to_string()
    Some(Mapping(_, key, path)) =>
      match key.val {
        None => if path == "" { "/" } else { path }
        Some(key) => {
          guard key.length() <= 4096 else {
            raise @wire.Invalid(
              "yaml_cursor_limit", "Diagnostic cursor exceeds 4096 UTF-16 units",
            )
          }
          let component = key
            .replace_all(old="~", new="~0")
            .replace_all(old="/", new="~1")
          guard path.length() + 1 + component.length() <= 4096 else {
            raise @wire.Invalid(
              "yaml_cursor_limit", "Diagnostic cursor exceeds 4096 UTF-16 units",
            )
          }
          path + "/" + component
        }
      }
  }
}

///|
fn reject(
  code : String,
  path : String,
  mark : @parser.Marker,
  detail : String,
) -> Unit raise @wire.CodecError {
  raise @wire.Invalid(
    code,
    path +
    " at " +
    mark.line.to_string() +
    ":" +
    (mark.col + 1).to_string() +
    ": " +
    detail,
  )
}

///|
fn place(
  stack : Array[Frame],
  root : Ref[Json?],
  value : Json,
  mark : @parser.Marker,
) -> Unit raise @wire.CodecError {
  match stack.last() {
    None => {
      guard root.val is None else {
        reject("invalid_yaml", "/", mark, "expected exactly one document")
      }
      root.val = Some(value)
    }
    Some(Sequence(items, _)) => items.push(value)
    Some(Mapping(fields, pending, _)) =>
      match pending.val {
        None => {
          guard value is String(key) else {
            reject(
              "invalid_type",
              cursor(stack),
              mark,
              "mapping keys must be strings",
            )
          }
          guard key != "<<" else {
            reject(
              "unsupported_yaml_feature",
              cursor(stack),
              mark,
              "merge keys are not part of the profile",
            )
          }
          guard !fields.contains(key) else {
            reject(
              "duplicate_member",
              cursor(stack),
              mark,
              "duplicate member " + key,
            )
          }
          pending.val = Some(key)
        }
        Some(key) => {
          fields[key] = value
          pending.val = None
        }
      }
  }
}

///|
/// The YAML 1.2 core decimal grammar, without converting through a Double.
fn numeric(text : String) -> Bool {
  let chars = text.to_array()
  let mut i = 0
  if i < chars.length() && chars[i] is ('+' | '-') {
    i += 1
  }
  let start = i
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    i += 1
  }
  let whole = i - start
  let mut fraction = 0
  if i < chars.length() && chars[i] == '.' {
    i += 1
    let start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    fraction = i - start
  }
  if whole + fraction == 0 {
    return false
  }
  if i < chars.length() && chars[i] is ('e' | 'E') {
    i += 1
    if i < chars.length() && chars[i] is ('+' | '-') {
      i += 1
    }
    let start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    if i == start {
      return false
    }
  }
  i == chars.length()
}

///|
fn scalar(
  text : String,
  style : @parser.TScalarStyle,
  path : String,
  mark : @parser.Marker,
) -> Json raise @wire.CodecError {
  if !(style is Plain) {
    return Json::string(text)
  }
  match text {
    "" | "null" | "Null" | "NULL" | "~" => return Json::null()
    "true" | "True" | "TRUE" => return Json::boolean(true)
    "false" | "False" | "FALSE" => return Json::boolean(false)
    _ => ()
  }
  let unsigned = if text.has_prefix("+") || text.has_prefix("-") {
    text[1:].to_owned()
  } else {
    text
  }
  if [".inf", ".Inf", ".INF", ".nan", ".NaN", ".NAN"].contains(unsigned) {
    reject(
      "invalid_literal", path, mark, "non-finite numbers are not part of the profile",
    )
  }
  if (text.has_prefix("0x") || text.has_prefix("0o")) &&
    text.length() > 2 &&
    text[2:]
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }) {
    reject("invalid_literal", path, mark, "write decimal")
  }
  if !numeric(text) {
    return Json::string(text)
  }
  if unsigned.length() > 1 &&
    unsigned[0] == '0' &&
    unsigned[1] >= '0' &&
    unsigned[1] <= '9' {
    reject(
      "invalid_literal", path, mark, "leading zeros are not part of the profile",
    )
  }
  let sign = if text.has_prefix("-") { "-" } else { "" }
  let normalized = if unsigned.has_prefix(".") {
    "0" + unsigned
  } else {
    unsigned
  }
  let chars = normalized.to_array()
  let out = StringBuilder()
  out.write_string(sign)
  for i, c in chars {
    out.write_char(c)
    if c == '.' && (i + 1 == chars.length() || chars[i + 1] is ('e' | 'E')) {
      out.write_char('0')
    }
  }
  @wire.parse(out.to_string())
}

///|
/// Parse exactly one mapping-root document under the normative Morphir profile.
/// No generic YAML loader or implicit scalar coercion participates in this path.
fn parse_document(
  source : String,
  limits : Limits,
) -> (Json, Int32, Int32) raise @wire.CodecError {
  guard limits.max_bytes > 0 &&
    limits.max_events > 0 &&
    limits.max_nodes > 0 &&
    limits.max_depth >= 0 &&
    limits.max_depth <= 512 &&
    limits.max_scalar_units >= 0 &&
    limits.max_assembly_nodes > 0 else {
    raise @wire.Invalid(
      "yaml_invalid_limits", "Limits must be nonnegative, depth at most 512, and source/event/node/assembly budgets positive",
    )
  }
  guard source.length() <= limits.max_bytes else {
    raise @wire.Invalid("yaml_source_limit", "Source byte budget exceeded")
  }
  let mut source_bytes = 0
  for c in source {
    let units = if c.to_int() < 128 {
      1
    } else if c.to_int() < 2048 {
      2
    } else if c.to_int() < 65536 {
      3
    } else {
      4
    }
    guard units <= limits.max_bytes - source_bytes else {
      raise @wire.Invalid("yaml_source_limit", "Source byte budget exceeded")
    }
    source_bytes += units
  }
  let text = if source.length() > 0 && source[0].to_int() == 65279 {
    source[1:]
  } else {
    source[:]
  }
  let parser = @parser.Parser::bounded(
    text,
    max_depth=limits.max_depth + 1,
    max_tokens=limits.max_events,
    max_scalar_units=limits.max_scalar_units,
  )
  let stack : Array[Frame] = []
  let root : Ref[Json?] = Ref(None)
  let mut documents = 0
  let mut events = 0
  let mut nodes = 0
  try {
    while true {
      guard events < limits.max_events else {
        raise @wire.Invalid("yaml_event_limit", "Event budget exceeded")
      }
      events += 1
      let (event, mark) = parser.next_event()
      let path = cursor(stack)
      match event {
        StreamStart | DocumentEnd => ()
        DocumentStart => {
          documents += 1
          guard documents == 1 else {
            reject("invalid_yaml", path, mark, "expected exactly one document")
          }
        }
        StreamEnd => break
        Alias(_) =>
          reject(
            "unsupported_yaml_feature", path, mark, "anchors and aliases are not part of the profile",
          )
        Scalar(value~, style~, id~, tag~) => {
          guard id == 0 && tag is None else {
            reject(
              "unsupported_yaml_feature", path, mark, "tags, anchors and aliases are not part of the profile",
            )
          }
          guard nodes < limits.max_nodes else {
            reject("yaml_node_limit", path, mark, "Node budget exceeded")
          }
          guard nodes < limits.max_assembly_nodes else {
            reject(
              "yaml_assembly_limit", path, mark, "Semantic assembly budget exceeded",
            )
          }
          guard stack.length() <= limits.max_depth else {
            reject("yaml_depth_limit", path, mark, "Depth budget exceeded")
          }
          nodes += 1
          place(stack, root, scalar(value, style, path, mark), mark)
        }
        SequenceStart(id~, tag~) | MappingStart(id~, tag~) => {
          guard id == 0 && tag is None else {
            reject(
              "unsupported_yaml_feature", path, mark, "tags, anchors and aliases are not part of the profile",
            )
          }
          guard nodes < limits.max_nodes else {
            reject("yaml_node_limit", path, mark, "Node budget exceeded")
          }
          guard nodes < limits.max_assembly_nodes else {
            reject(
              "yaml_assembly_limit", path, mark, "Semantic assembly budget exceeded",
            )
          }
          guard stack.length() <= limits.max_depth else {
            reject("yaml_depth_limit", path, mark, "Depth budget exceeded")
          }
          if stack.last() is Some(Mapping(_, pending, _)) && pending.val is None {
            reject("invalid_type", path, mark, "mapping keys must be strings")
          }
          nodes += 1
          let base = if path == "/" { "" } else { path }
          stack.push(
            match event {
              SequenceStart(..) => Sequence([], base)
              _ => Mapping(Map([]), Ref(None), base)
            },
          )
        }
        SequenceEnd | MappingEnd => {
          guard stack.pop() is Some(frame) else {
            reject("invalid_yaml", path, mark, "Unexpected container end")
          }
          let value = match frame {
            Sequence(items, _) => Json::array(items)
            Mapping(fields, _, _) => Json::object(fields)
          }
          place(stack, root, value, mark)
        }
      }
    }
  } catch {
    @parser.YamlError(mark~, info~) => {
      let code = if info == "unsupported_yaml_feature" ||
        info.has_prefix("yaml_") {
        info
      } else {
        "invalid_yaml"
      }
      reject(code, cursor(stack), mark, info)
    }
    @wire.Invalid(code, detail) => raise @wire.Invalid(code, detail)
    error => raise @wire.Invalid("invalid_yaml", error.to_string())
  }
  guard documents == 1 && root.val is Some(value) else {
    raise @wire.Invalid("invalid_yaml", "expected exactly one document")
  }
  guard value is Object(_) else {
    raise @wire.Invalid("invalid_type", "Root must be a mapping")
  }
  (value, nodes, events)
}

///|
pub fn parse(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Json raise @wire.CodecError {
  parse_document(source, limits).0
}

///|
/// Version selection and migration share the JSON semantic decoder.
pub fn read(
  source : String,
  limits~ : Limits = Limits::default(),
) -> @ir.IRFile raise {
  @migration.to_current(read_versioned(source, limits~))
}

///|
/// Original-file owners capture the source revision before migration.
pub fn read_versioned(
  source : String,
  limits~ : Limits = Limits::default(),
) -> @versions.IRFile raise {
  let value = parse(source, limits~)
  ignore(assembly_cost(value, limits.max_assembly_nodes))
  @versioned.from_json(value)
}

///|
/// Readable names and types can expand one scalar into many semantic nodes.
/// Charge code units as well as physical nodes before any typed normalization.
/// This conservative work budget also bounds the scratch space of shorthand
/// expansion. It never parses or coerces user text itself.
fn assembly_cost(value : Json, limit : Int32) -> Int32 raise @wire.CodecError {
  let remaining = Ref(limit)
  fn charge(units : Int32) -> Unit raise @wire.CodecError {
    guard units <= remaining.val else {
      raise @wire.Invalid(
        "yaml_assembly_limit", "Typed normalization work budget exceeded",
      )
    }
    remaining.val -= units
  }
  fn visit(value : Json) -> Unit raise @wire.CodecError {
    charge(1)
    match value {
      String(text) => charge(text.length())
      Number(_, repr=Some(text)) => charge(text.length())
      Object(fields) =>
        for key, item in fields {
          charge(key.length())
          visit(item)
        }
      Array(items) =>
        for item in items {
          visit(item)
        }
      _ => ()
    }
  }
  visit(value)
  limit - remaining.val
}

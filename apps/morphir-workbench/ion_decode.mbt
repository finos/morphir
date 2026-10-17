// Binary Ion to Ion text for the generated-file viewer. Every limit stops the work before it grows: the input
// size before base64 decoding, the depth and value count before the Ion reader runs, and the text length while
// it is written.

///|
/// The largest binary Ion file the workbench decodes to text: 4 MiB.
pub let ion_input_limit : Int32 = 4 * 1024 * 1024

///|
/// The longest Ion text a decode returns: 4 Mi characters.
pub let ion_text_limit : Int32 = 4 * 1024 * 1024

///|
/// The deepest container nesting a decode reads, as for an Ion model import.
pub let ion_depth_limit : Int32 = 128

///|
/// The most values (annotation wrappers included) a decode reads, as for an Ion model import.
pub let ion_value_limit : Int32 = 100000

///|
/// The longest integer or decimal, in bytes, a decode reads: 64 KiB, about 158,000 digits. Longer numbers would make
/// printing slow.
pub let ion_number_limit : Int32 = 64 * 1024

///|
/// Decodes a binary Ion file (`source`: its bytes in base64) to pretty Ion text. A file that does not start with
/// the Ion binary version marker `E0 01 00 EA` is refused, as are files past the size, depth, value or text
/// limits. Ion errors reach the caller with their `ion.*` codes.
fn decode_ion(request : Json) -> Json raise {
  let path = optional_text(request, "path").unwrap_or("")
  let encoded = @wire.string(@wire.field(request, "source"))
  let too_large = fn() {
    failure(
      "The file is larger than the 4 MiB that the workbench decodes to Ion text",
      "workbench.ion_input_too_large", "decode",
    )
  }
  if encoded.length() > (ion_input_limit + 2) / 3 * 4 {
    return too_large()
  }
  let bytes = @base64.decode(encoded[:]) catch {
    _ =>
      return failure(
        "The file's content is not valid base64", "workbench.invalid_encoding", "decode",
      )
  }
  if bytes.length() > ion_input_limit {
    return too_large()
  }
  if !@ion_binary.has_binary_version_marker(bytes[:]) {
    return failure(
      "This file is not binary Ion: it does not start with the version marker E0 01 00 EA",
      "workbench.not_binary_ion", "decode",
    )
  }
  if ion_shape_refusal(bytes[:]) is Some(refused) {
    return refused
  }
  let values = @ion_binary.read_binary(bytes[:])
  let text = match ion_text_within(values, ion_text_limit) {
    Written(text) => text
    OverBudget(_) =>
      return failure(
        "The Ion text of this file is longer than the 4 Mi characters the workbench shows",
        "workbench.ion_text_too_large", "decode",
      )
  }
  @wire.obj([
    ("success", Json::boolean(true)),
    ("operation", @wire.text("decode-ion")),
    ("path", @wire.text(path)),
    ("text", @wire.text(text)),
    ("values", Json::number(values.length().to_double())),
    ("bytes", Json::number(bytes.length().to_double())),
  ])
}

///|
/// The number of octets of the VarUInt at `pos`, which ends with the octet whose high bit is set; `None` when it
/// runs past `end`.
fn var_uint_width(bytes : BytesView, pos : Int32, end : Int32) -> Int32? {
  for at = pos; at < end; at = at + 1 {
    if (bytes[at].to_int() & 0x80) != 0 {
      return Some(at - pos + 1)
    }
  }
  None
}

///|
/// Walks the binary structure without building values and refuses a file deeper than `ion_depth_limit`, with
/// more than `ion_value_limit` values or with an integer or decimal longer than `ion_number_limit`, so the reader
/// never meets one. The walk uses a stack, not recursion. A length that runs past its container, or an annotation
/// wrapper around another, is an `ion.syntax` error.
fn ion_shape_refusal(bytes : BytesView) -> Json? raise @ion.IonError {
  let truncated = fn() -> Unit raise @ion.IonError {
    raise @ion.IonError::Syntax("A value runs past the end of its container")
  }
  // Each frame is a container's end, the depth of its children and whether they carry field names.
  let frames : Array[(Int32, Int32, Bool)] = [(bytes.length(), 0, false)]
  let mut pos = 0
  let mut count = 0
  while frames.last() is Some((end, depth, is_struct)) {
    if pos >= end {
      ignore(frames.pop())
      pos = end
      continue
    }
    if frames.length() == 1 && @ion_binary.has_version_marker(bytes, pos) {
      pos += 4
      continue
    }
    if is_struct {
      guard var_uint_width(bytes, pos, end) is Some(width) else { truncated() }
      pos += width
      if pos >= end {
        truncated()
      }
    }
    guard @ion_binary.value_size(bytes, pos) is Some(size) else { truncated() }
    let value_end = pos + size
    if value_end > end {
      truncated()
    }
    let descriptor = bytes[pos].to_int()
    let type_code = descriptor >> 4
    let nibble = descriptor & 0x0F
    // Type 0 with a length nibble below 0xF is a NOP pad, not a value. 0x0F is the untyped null and 0x1F to 0xDF
    // are typed nulls: all values.
    if type_code != 0 || nibble == 0x0F {
      count += 1
    }
    if count > ion_value_limit {
      return Some(
        failure(
          "This file holds more than \{ion_value_limit} Ion values, the most the workbench decodes",
          "workbench.ion_too_many_values",
          "decode",
        ),
      )
    }
    if depth > ion_depth_limit {
      return Some(
        failure(
          "This file nests Ion containers deeper than \{ion_depth_limit} levels, the most the workbench decodes",
          "workbench.ion_too_deep",
          "decode",
        ),
      )
    }
    let header = if nibble == 0x0E || (type_code == 13 && nibble == 1) {
      match var_uint_width(bytes, pos + 1, value_end) {
        Some(width) => 1 + width
        None => size
      }
    } else {
      1
    }
    if (type_code == 2 || type_code == 3 || type_code == 5) &&
      nibble != 0x0F &&
      size - header > ion_number_limit {
      return Some(
        failure(
          "This file holds a number longer than \{ion_number_limit} bytes, the most the workbench decodes",
          "workbench.ion_number_too_large",
          "decode",
        ),
      )
    }
    if nibble == 0x0F || type_code == 1 {
      // A typed null, or a bool whose nibble is its value.
      pos = value_end
    } else if type_code >= 11 && type_code <= 13 {
      frames.push((value_end, depth + 1, type_code == 13))
      pos = pos + header
    } else if type_code == 14 {
      // An annotation wrapper: the annotation symbols, then the one value they annotate, at the same depth.
      let start = pos + header
      guard var_uint_width(bytes, start, value_end) is Some(width) && width <= 4 else {
        truncated()
      }
      let mut annotations = 0
      for at in start..<(start + width) {
        annotations = (annotations << 7) | (bytes[at].to_int() & 0x7F)
      }
      let wrapped = start + width + annotations
      if annotations > value_end - start || wrapped >= value_end {
        truncated()
      }
      if bytes[wrapped].to_int() >> 4 == 14 {
        raise @ion.IonError::Syntax(
          "An annotation wrapper cannot wrap another annotation wrapper",
        )
      }
      frames.push((value_end, depth, false))
      pos = wrapped
    } else {
      pos = value_end
    }
  }
  None
}

///|
/// Pretty Ion text, or how much of it fitted before the budget ran out.
pub(all) enum IonText {
  Written(String)
  /// The characters written before the next piece would pass the budget; never more than the budget.
  OverBudget(Int32)
} derive(Eq)

///|
pub extend IonText with Eq::{equal, not_equal}

///|
priv suberror TextBudget

///|
/// Pretty Ion text written piece by piece with a running count. A piece that would pass the limit raises
/// `TextBudget` before it is added.
priv struct BudgetWriter {
  buffer : StringBuilder
  mut used : Int32
  limit : Int32
}

///|
fn BudgetWriter::write(
  self : BudgetWriter,
  text : String,
) -> Unit raise TextBudget {
  if self.used + text.length() > self.limit {
    raise TextBudget
  }
  self.used += text.length()
  self.buffer.write_string(text)
}

///|
/// At least this many characters of `value` before it is written, so a long string or blob passes the budget
/// before its text is built.
fn least_text(value : @ion.IonValue) -> Int32 {
  match value.kind() {
    String(text) => text.length() + 2
    Symbol(token) => token.text().map(text => text.length()).unwrap_or(0)
    Clob(bytes) => bytes.length() + 6
    Blob(bytes) => (bytes.length() + 2) / 3 * 4 + 6
    _ => 0
  }
}

///|
/// One value as `@ion_text.write_all_pretty` renders it: containers here, one element per line indented by two
/// spaces a level, and every scalar through the library's own `write_fragment`.
fn BudgetWriter::value(
  self : BudgetWriter,
  value : @ion.IonValue,
  depth : Int32,
  in_sexp : Bool,
) -> Unit raise {
  let (open, close, items, separator, in_items) = match value.kind() {
    List(items) => ("[", "]", items.map(item => (None, item)), ",", false)
    Sexp(items) => ("(", ")", items.map(item => (None, item)), "", true)
    Struct(fields) =>
      (
        "{",
        "}",
        fields.map(field => (Some(field.name()), field.value())),
        ",",
        false,
      )
    _ => {
      if self.used + least_text(value) > self.limit {
        raise TextBudget
      }
      self.write(@ion_text.write_fragment(value, depth~, pretty=true, in_sexp~))
      return
    }
  }
  for annotation in value.annotations() {
    self.write(@ion_text.symbol_to_text(annotation))
    self.write("::")
  }
  if items.is_empty() {
    self.write(open + close)
    return
  }
  self.write(open)
  for index, item in items {
    self.write("\n")
    self.write("  ".repeat(depth + 1))
    if item.0 is Some(name) {
      self.write(@ion_text.symbol_to_text(name))
      self.write(": ")
    }
    self.value(item.1, depth + 1, in_items)
    if index + 1 < items.length() {
      self.write(separator)
    }
  }
  self.write("\n")
  self.write("  ".repeat(depth))
  self.write(close)
}

///|
/// `values` as `@ion_text.write_all_pretty` writes them, one per line with the local symbol tables they need, but
/// stopped as soon as the text would pass `limit` characters.
pub fn ion_text_within(
  values : Array[@ion.IonValue],
  limit : Int32,
) -> IonText raise {
  let writer = { buffer: StringBuilder(), used: 0, limit, }
  let mut reserved = 9
  try {
    for index, value in values {
      if index > 0 {
        writer.write("\n")
      }
      if value.has_imported_symbols() {
        let table = @ion.SymbolTable::for_values([value])
        if table.to_local_symbol_table() is Some(directive) {
          writer.value(directive, 0, false)
          writer.write("\n")
        }
        writer.value(table.localize_for_text(value), 0, false)
        reserved = 9
        continue
      }
      let highest = @ion.highest_symbol_id([value])
      if highest > reserved {
        let table = @ion.SymbolTable::system()
        table.reserve(highest - 9)
        if table.to_local_symbol_table() is Some(directive) {
          writer.value(directive, 0, false)
          writer.write("\n")
        }
        reserved = highest
      }
      writer.value(value, 0, false)
    }
  } catch {
    TextBudget => return OverBudget(writer.used)
    error => raise error
  }
  Written(writer.buffer.to_string())
}

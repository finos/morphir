///|
fn units(value : @sdk.Text) -> Array[UInt16] {
  value.to_units()
}

///|
fn text(value : String) -> @sdk.Text {
  @sdk.Text::from_string(value)
}

///|
fn push_text(destination : Array[UInt16], value : @sdk.Text) -> Unit {
  for unit in units(value) {
    destination.push(unit)
  }
}

///|
fn part(source : Array[UInt16], start : Int32, end : Int32) -> @sdk.Text {
  let result : Array[UInt16] = []
  for i = start; i < end; i = i + 1 {
    result.push(source[i])
  }
  @sdk.Text::from_units(result)
}

///|
fn match_at(
  source : Array[UInt16],
  needle : Array[UInt16],
  start : Int32,
) -> Bool {
  if start + needle.length() > source.length() {
    return false
  }
  for i = 0; i < needle.length(); i = i + 1 {
    if source[start + i] != needle[i] {
      return false
    }
  }
  true
}

///|
fn next_index(source : Array[UInt16], i : Int32) -> Int32 {
  if i + 1 < source.length() &&
    source[i].is_leading_surrogate() &&
    source[i + 1].is_trailing_surrogate() {
    i + 2
  } else {
    i + 1
  }
}

///|
fn chars(value : @sdk.Text) -> Array[@sdk.Character] {
  let source = units(value)
  let result : Array[@sdk.Character] = []
  let mut i = 0
  while i < source.length() {
    let next = next_index(source, i)
    result.push(@sdk.Character::from_text(part(source, i, next)))
    i = next
  }
  result
}

///|
fn code(character : @sdk.Character) -> Int32 {
  let source = character.to_units()
  if source.length() == 0 {
    return -1
  }
  if source.length() > 1 &&
    source[0].is_leading_surrogate() &&
    source[1].is_trailing_surrogate() {
    65536 + (source[0].to_int() - 55296) * 1024 + source[1].to_int() - 56320
  } else {
    source[0].to_int()
  }
}

///|
pub fn compare(left : @sdk.Text, right : @sdk.Text) -> @sdk.Order {
  @sdk.text_order(left, right)
}

///|
pub fn is_empty(value : @sdk.Text) -> Bool {
  value.length() == 0
}

///|
pub fn length(value : @sdk.Text) -> Int32 {
  value.length()
}

///|
pub fn reverse(value : @sdk.Text) -> @sdk.Text {
  let source = chars(value)
  let result : Array[@sdk.Character] = []
  for i = source.length() - 1; i >= 0; i = i - 1 {
    result.push(source[i])
  }
  from_list(@list.from_array(result))
}

///|
pub fn repeat(count : Int32, value : @sdk.Text) -> @sdk.Text {
  let result : Array[UInt16] = []
  let source = units(value)
  for i = 0; i < count; i = i + 1 {
    for unit in source {
      result.push(unit)
    }
  }
  @sdk.Text::from_units(result)
}

///|
pub fn append(left : @sdk.Text, right : @sdk.Text) -> @sdk.Text {
  let result = units(left)
  for unit in units(right) {
    result.push(unit)
  }
  @sdk.Text::from_units(result)
}

///|
pub fn concat(values : @list.List[@sdk.Text]) -> @sdk.Text {
  let result : Array[UInt16] = []
  for value in @list.to_array(values) {
    push_text(result, value)
  }
  @sdk.Text::from_units(result)
}

///|
pub fn split(separator : @sdk.Text, value : @sdk.Text) -> @list.List[@sdk.Text] {
  let source = units(value)
  let needle = units(separator)
  let result : Array[@sdk.Text] = []
  if needle.length() == 0 {
    for i = 0; i < source.length(); i = i + 1 {
      result.push(part(source, i, i + 1))
    }
    return @list.from_array(result)
  }
  let mut start = 0
  let mut i = 0
  while i <= source.length() - needle.length() {
    if match_at(source, needle, i) {
      result.push(part(source, start, i))
      i += needle.length()
      start = i
    } else {
      i += 1
    }
  }
  result.push(part(source, start, source.length()))
  @list.from_array(result)
}

///|
pub fn join(separator : @sdk.Text, values : @list.List[@sdk.Text]) -> @sdk.Text {
  let result : Array[UInt16] = []
  let mut first = true
  for value in @list.to_array(values) {
    if !first {
      push_text(result, separator)
    }
    push_text(result, value)
    first = false
  }
  @sdk.Text::from_units(result)
}

///|
pub fn replace(
  before : @sdk.Text,
  after : @sdk.Text,
  value : @sdk.Text,
) -> @sdk.Text {
  join(after, split(before, value))
}

///|
fn is_ecmascript_space(code : Int32) -> Bool {
  (code >= 9 && code <= 13) ||
  code == 32 ||
  code == 160 ||
  code == 5760 ||
  (code >= 8192 && code <= 8202) ||
  code == 8232 ||
  code == 8233 ||
  code == 8239 ||
  code == 8287 ||
  code == 12288 ||
  code == 65279
}

///|
pub fn trim_left(value : @sdk.Text) -> @sdk.Text {
  let source = units(value)
  let mut start = 0
  while start < source.length() && is_ecmascript_space(source[start].to_int()) {
    start += 1
  }
  part(source, start, source.length())
}

///|
pub fn trim_right(value : @sdk.Text) -> @sdk.Text {
  let source = units(value)
  let mut end = source.length()
  while end > 0 && is_ecmascript_space(source[end - 1].to_int()) {
    end -= 1
  }
  part(source, 0, end)
}

///|
pub fn trim(value : @sdk.Text) -> @sdk.Text {
  trim_right(trim_left(value))
}

///|
pub fn words(value : @sdk.Text) -> @list.List[@sdk.Text] {
  let source = units(trim(value))
  if source.length() == 0 {
    return @list.from_array([text("")])
  }
  let result : Array[@sdk.Text] = []
  let mut start = 0
  let mut i = 0
  while i < source.length() {
    if is_ecmascript_space(source[i].to_int()) {
      result.push(part(source, start, i))
      while i < source.length() && is_ecmascript_space(source[i].to_int()) {
        i += 1
      }
      start = i
    } else {
      i += 1
    }
  }
  result.push(part(source, start, source.length()))
  @list.from_array(result)
}

///|
pub fn lines(value : @sdk.Text) -> @list.List[@sdk.Text] {
  let source = units(value)
  let result : Array[@sdk.Text] = []
  let mut start = 0
  let mut i = 0
  while i < source.length() {
    let unit = source[i].to_int()
    if unit == 10 || unit == 13 {
      result.push(part(source, start, i))
      if unit == 13 && i + 1 < source.length() && source[i + 1].to_int() == 10 {
        i += 1
      }
      start = i + 1
    }
    i += 1
  }
  result.push(part(source, start, source.length()))
  @list.from_array(result)
}

///|
fn clamp_index(index : Int32, total : Int32) -> Int32 {
  let absolute = if index < 0 { total + index } else { index }
  if absolute < 0 {
    0
  } else if absolute > total {
    total
  } else {
    absolute
  }
}

///|
pub fn slice(start : Int32, end : Int32, value : @sdk.Text) -> @sdk.Text {
  let source = units(value)
  let a = clamp_index(start, source.length())
  let b = clamp_index(end, source.length())
  if a >= b {
    text("")
  } else {
    part(source, a, b)
  }
}

///|
pub fn left(count : Int32, value : @sdk.Text) -> @sdk.Text {
  if count <= 0 {
    text("")
  } else {
    slice(0, count, value)
  }
}

///|
pub fn right(count : Int32, value : @sdk.Text) -> @sdk.Text {
  if count <= 0 {
    text("")
  } else {
    slice(-count, value.length(), value)
  }
}

///|
pub fn drop_left(count : Int32, value : @sdk.Text) -> @sdk.Text {
  if count <= 0 {
    value
  } else {
    slice(count, value.length(), value)
  }
}

///|
pub fn drop_right(count : Int32, value : @sdk.Text) -> @sdk.Text {
  if count <= 0 {
    value
  } else {
    slice(0, -count, value)
  }
}

///|
pub fn contains(needle : @sdk.Text, value : @sdk.Text) -> Bool {
  if needle.length() == 0 {
    true
  } else {
    @list.length(indexes(needle, value)) > 0
  }
}

///|
pub fn starts_with(prefix : @sdk.Text, value : @sdk.Text) -> Bool {
  match_at(units(value), units(prefix), 0)
}

///|
pub fn ends_with(suffix : @sdk.Text, value : @sdk.Text) -> Bool {
  let source = units(value)
  let needle = units(suffix)
  source.length() >= needle.length() &&
  match_at(source, needle, source.length() - needle.length())
}

///|
pub fn indexes(needle : @sdk.Text, value : @sdk.Text) -> @list.List[Int32] {
  let source = units(value)
  let match_units = units(needle)
  let positions = []
  if match_units.length() == 0 {
    return @list.from_array(positions)
  }
  let mut i = 0
  while i <= source.length() - match_units.length() {
    if match_at(source, match_units, i) {
      positions.push(i)
      i += match_units.length()
    } else {
      i += 1
    }
  }
  @list.from_array(positions)
}

///|
pub fn indices(needle : @sdk.Text, value : @sdk.Text) -> @list.List[Int32] {
  indexes(needle, value)
}

///|
pub fn to_int(value : @sdk.Text) -> @integer.Integer? {
  let source = value.to_string() catch { _ => return None }
  @integer.from_string(source)
}

///|
pub fn from_int(value : @integer.Integer) -> @sdk.Text {
  text(@integer.to_string(value))
}

///|
pub fn to_float(value : @sdk.Text) -> Double? {
  let source = value.to_string() catch { _ => return None }
  if source.is_empty() {
    return None
  }
  if source == "Infinity" || source == "+Infinity" {
    return Some(1.0 / 0.0)
  }
  if source == "-Infinity" {
    return Some(-1.0 / 0.0)
  }
  for character in source.to_array() {
    if !(character >= '0' && character <= '9') &&
      character != '+' &&
      character != '-' &&
      character != '.' &&
      character != 'e' &&
      character != 'E' {
      return None
    }
  }
  let parsed = @parse.parse_double(source) catch { _ => return None }
  if parsed.is_nan() {
    None
  } else {
    Some(parsed)
  }
}

///|
pub fn from_float(value : Double) -> @sdk.Text {
  text(value.to_string())
}

///|
pub fn from_char(value : @sdk.Character) -> @sdk.Text {
  value.to_text()
}

///|
pub fn cons(character : @sdk.Character, value : @sdk.Text) -> @sdk.Text {
  append(character.to_text(), value)
}

///|
pub fn uncons(value : @sdk.Text) -> (@sdk.Character, @sdk.Text)? {
  let source = units(value)
  if source.length() == 0 {
    None
  } else {
    let end = next_index(source, 0)
    Some(
      (
        @sdk.Character::from_text(part(source, 0, end)),
        part(source, end, source.length()),
      ),
    )
  }
}

///|
pub fn to_list(value : @sdk.Text) -> @list.List[@sdk.Character] {
  @list.from_array(chars(value))
}

///|
pub fn from_list(values : @list.List[@sdk.Character]) -> @sdk.Text {
  let result : Array[UInt16] = []
  for character in @list.to_array(values) {
    push_text(result, character.to_text())
  }
  @sdk.Text::from_units(result)
}

///|
pub fn to_upper(value : @sdk.Text) -> @sdk.Text {
  let result : Array[UInt16] = []
  for character in chars(value) {
    let n = code(character)
    let original = character.to_text()
    if n >= 55296 && n <= 57343 {
      push_text(result, original)
    } else {
      let scalar = n.to_char().unwrap().to_string()
      push_text(result, text(upper_scalar(n, scalar)))
    }
  }
  @sdk.Text::from_units(result)
}

///|
fn final_sigma(characters : Array[@sdk.Character], index : Int32) -> Bool {
  let mut before = index - 1
  while before >= 0 && is_case_ignorable(code(characters[before])) {
    before -= 1
  }
  if before < 0 || !is_cased(code(characters[before])) {
    return false
  }
  let mut after = index + 1
  while after < characters.length() &&
        is_case_ignorable(code(characters[after])) {
    after += 1
  }
  after == characters.length() || !is_cased(code(characters[after]))
}

///|
pub fn to_lower(value : @sdk.Text) -> @sdk.Text {
  let characters = chars(value)
  let result : Array[UInt16] = []
  for i = 0; i < characters.length(); i = i + 1 {
    let character = characters[i]
    let n = code(character)
    if n == 931 && final_sigma(characters, i) {
      push_text(result, text("ς"))
    } else if n >= 55296 && n <= 57343 {
      push_text(result, character.to_text())
    } else {
      let scalar = n.to_char().unwrap().to_string()
      push_text(result, text(lower_scalar(n, scalar)))
    }
  }
  @sdk.Text::from_units(result)
}

///|
pub fn pad_left(
  count : Int32,
  character : @sdk.Character,
  value : @sdk.Text,
) -> @sdk.Text {
  append(repeat(count - length(value), character.to_text()), value)
}

///|
pub fn pad_right(
  count : Int32,
  character : @sdk.Character,
  value : @sdk.Text,
) -> @sdk.Text {
  append(value, repeat(count - length(value), character.to_text()))
}

///|
pub fn pad(
  count : Int32,
  character : @sdk.Character,
  value : @sdk.Text,
) -> @sdk.Text {
  let missing = count - length(value)
  let left_count = if missing <= 0 { 0 } else { (missing + 1) / 2 }
  let right_count = if missing <= 0 { 0 } else { missing / 2 }
  append(
    append(repeat(left_count, character.to_text()), value),
    repeat(right_count, character.to_text()),
  )
}

///|
pub fn[A] foldl(
  f : (@sdk.Character, A) -> A raise?,
  initial : A,
  value : @sdk.Text,
) -> A raise? {
  let mut result = initial
  for character in chars(value) {
    result = f(character, result)
  }
  result
}

///|
pub fn[A] foldr(
  f : (@sdk.Character, A) -> A raise?,
  initial : A,
  value : @sdk.Text,
) -> A raise? {
  let source = chars(value)
  let mut result = initial
  for i = source.length() - 1; i >= 0; i = i - 1 {
    result = f(source[i], result)
  }
  result
}

///|
pub fn map(
  f : (@sdk.Character) -> @sdk.Character raise?,
  value : @sdk.Text,
) -> @sdk.Text raise? {
  from_list(@list.from_array(chars(value).map(f)))
}

///|
pub fn filter(
  f : (@sdk.Character) -> Bool raise?,
  value : @sdk.Text,
) -> @sdk.Text raise? {
  from_list(@list.from_array(chars(value).filter(f)))
}

///|
pub fn any(
  f : (@sdk.Character) -> Bool raise?,
  value : @sdk.Text,
) -> Bool raise? {
  for character in chars(value) {
    if f(character) {
      return true
    }
  }
  false
}

///|
pub fn all(
  f : (@sdk.Character) -> Bool raise?,
  value : @sdk.Text,
) -> Bool raise? {
  for character in chars(value) {
    if !f(character) {
      return false
    }
  }
  true
}

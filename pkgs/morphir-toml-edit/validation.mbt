///|
let decimal : @string.Regex = @string.Regex::unsafe_from_string(
  "^[+\\-]?(0|[1-9](_?[0-9])*)$",
)

///|
let hexadecimal : @string.Regex = @string.Regex::unsafe_from_string(
  "^0x[0-9a-fA-F](_?[0-9a-fA-F])*$",
)

///|
let octal : @string.Regex = @string.Regex::unsafe_from_string(
  "^0o[0-7](_?[0-7])*$",
)

///|
let binary : @string.Regex = @string.Regex::unsafe_from_string(
  "^0b[01](_?[01])*$",
)

///|
let floating : @string.Regex = @string.Regex::unsafe_from_string(
  "^[+\\-]?(0|[1-9](_?[0-9])*)([.][0-9](_?[0-9])*)?([eE][+\\-]?[0-9](_?[0-9])*)?$",
)

///|
let date_time : @string.Regex = @string.Regex::unsafe_from_string(
  "^([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([Tt ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]([.][0-9]+)?([Zz]|[+\\-][0-9][0-9]:[0-9][0-9])?)?|[0-9][0-9]:[0-9][0-9]:[0-9][0-9]([.][0-9]+)?)$",
)

///|
fn number(s : String, start : Int32, end : Int32) -> Int32 {
  let mut n = 0
  for i = start; i < end; i = i + 1 {
    n = n * 10 + s.code_unit_at(i).to_int() - 48
  }
  n
}

///|
fn valid_date_time(s : String) -> Bool {
  if date_time.execute(s) is None {
    return false
  }
  let has_date = s.length() >= 10 && s.code_unit_at(4).to_int() == 45
  let time_start = if has_date { 11 } else { 0 }
  if has_date {
    let y = number(s, 0, 4)
    let m = number(s, 5, 7)
    let d = number(s, 8, 10)
    if m < 1 || m > 12 {
      return false
    }
    let days = month_days(y, m)
    if d < 1 || d > days {
      return false
    }
  }
  if s.length() == 10 && has_date {
    return true
  }
  if number(s, time_start, time_start + 2) > 23 ||
    number(s, time_start + 3, time_start + 5) > 59 ||
    number(s, time_start + 6, time_start + 8) > 60 {
    return false
  }
  let n = s.length()
  if has_date &&
    n >= 6 &&
    (
      s.code_unit_at(n - 6).to_int() == 43 ||
      s.code_unit_at(n - 6).to_int() == 45
    ) {
    if number(s, n - 5, n - 3) > 23 || number(s, n - 2, n) > 59 {
      return false
    }
  }
  if has_date && number(s, time_start + 6, time_start + 8) == 60 {
    let last = s.code_unit_at(n - 1).to_int()
    let numeric_offset = n >= 6 &&
      (
        s.code_unit_at(n - 6).to_int() == 43 ||
        s.code_unit_at(n - 6).to_int() == 45
      )
    if last == 90 || last == 122 || numeric_offset {
      let offset = if numeric_offset {
        let minutes = number(s, n - 5, n - 3) * 60 + number(s, n - 2, n)
        if s.code_unit_at(n - 6).to_int() == 45 {
          -minutes
        } else {
          minutes
        }
      } else {
        0
      }
      return valid_leap_second(s, offset)
    }
  }
  true
}

///|
fn month_days(year : Int32, month : Int32) -> Int32 {
  if month == 2 {
    if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
/// Positive UTC leap-second dates from IERS Leap_Second.dat, Bulletin 72,
/// July 2026. The file lists effective dates; these are the preceding days.
/// https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat
let leap_second_dates : Array[Int32] = [
  19720630, 19721231, 19731231, 19741231, 19751231, 19761231, 19771231, 19781231,
  19791231, 19810630, 19820630, 19830630, 19850630, 19871231, 19891231, 19901231,
  19920630, 19930630, 19940630, 19951231, 19970630, 19981231, 20051231, 20081231,
  20120630, 20150630, 20161231,
]

///|
/// RFC 3339 section 5.7 requires the same UTC instant in every zone. Local
/// date-times and local times have no known offset and cannot use this check.
fn valid_leap_second(s : String, offset : Int32) -> Bool {
  let mut year = number(s, 0, 4)
  let mut month = number(s, 5, 7)
  let mut day = number(s, 8, 10)
  let mut minutes = number(s, 11, 13) * 60 + number(s, 14, 16) - offset
  if minutes < 0 {
    minutes += 1440
    day -= 1
    if day == 0 {
      month -= 1
      if month == 0 {
        year -= 1
        month = 12
      }
      day = month_days(year, month)
    }
  } else if minutes >= 1440 {
    minutes -= 1440
    day += 1
    if day > month_days(year, month) {
      day = 1
      month += 1
      if month == 13 {
        year += 1
        month = 1
      }
    }
  }
  minutes == 1439 &&
  leap_second_dates.contains(year * 10000 + month * 100 + day)
}

///|
fn valid_atom(s : String) -> Bool {
  if ["true", "false", "inf", "+inf", "-inf", "nan", "+nan", "-nan"].contains(s) {
    return true
  }
  if valid_date_time(s) {
    return true
  }
  let base = if hexadecimal.execute(s) is Some(_) {
    16
  } else if octal.execute(s) is Some(_) {
    8
  } else if binary.execute(s) is Some(_) {
    2
  } else if decimal.execute(s) is Some(_) {
    10
  } else {
    0
  }
  if base != 0 {
    let digits = s.replace_all(old="_", new="")
    let digits = if base == 10 { digits } else { digits[2:].to_owned() }
    return try {
      ignore(@string.parse_int64(digits, base~))
      true
    } catch {
      _ => false
    }
  }
  (s.contains(".") || s.contains("e") || s.contains("E")) &&
  floating.execute(s) is Some(_)
}

///|
/// A declaration arena models TOML's implicit, explicit and dotted tables,
/// and resolves headers through the most recent array-of-tables element.
priv enum Declaration {
  Implicit
  Explicit
  Dotted
}

///|
priv struct Table {
  fields : Map[String, Binding]
  mut declaration : Declaration
}

///|
priv enum Binding {
  Child(Table)
  TableArray(Array[Table])
  Leaf
}

///|
fn new_table(declaration : Declaration) -> Table {
  { fields: Map([]), declaration, }
}

///|
fn child(
  source : String,
  table : Table,
  key : String,
  at : Int32,
  dotted : Bool,
) -> Table raise Diagnostic {
  match table.fields.get(key) {
    Some(Child(t)) => {
      if dotted {
        match t.declaration {
          Explicit =>
            raise problem(
              source,
              at,
              InvalidToml,
              "Cannot extend an explicit table with dotted keys",
            )
          Implicit | Dotted => ()
        }
      }
      t
    }
    Some(TableArray(ts)) if !dotted => ts[ts.length() - 1]
    Some(_) =>
      raise problem(source, at, InvalidToml, "Key is already a value: " + key)
    None => {
      let t = new_table(if dotted { Dotted } else { Implicit })
      table.fields[key] = Child(t)
      t
    }
  }
}

///|
fn declare_entry(
  source : String,
  table : Table,
  entry : Entry,
) -> Unit raise Diagnostic {
  let mut t = table
  for i = 0; i < entry.keys.length() - 1; i = i + 1 {
    t = child(source, t, entry.keys[i], entry.start, true)
  }
  let key = entry.keys[entry.keys.length() - 1]
  if t.fields.contains(key) {
    raise problem(source, entry.start, InvalidToml, "Duplicate key: " + key)
  }
  t.fields[key] = Leaf
}

///|
fn validate_inline(
  source : String,
  entries : Array[Entry],
) -> Unit raise Diagnostic {
  let root = new_table(Explicit)
  for entry in entries {
    declare_entry(source, root, entry)
  }
}

///|
fn validate_document(
  source : String,
  statements : Array[Statement],
) -> Unit raise Diagnostic {
  let root = new_table(Explicit)
  let mut current = root
  for statement in statements {
    match statement {
      Assignment(_, entry) => declare_entry(source, current, entry)
      Header(path, kind, span) => {
        let aot = kind is ArrayOfTables
        let mut t = root
        for i = 0; i < path.length() - 1; i = i + 1 {
          t = child(source, t, path[i], span.start, false)
        }
        let key = path[path.length() - 1]
        match t.fields.get(key) {
          None => {
            current = new_table(Explicit)
            t.fields[key] = if aot {
              TableArray([current])
            } else {
              Child(current)
            }
          }
          Some(TableArray(ts)) if aot => {
            current = new_table(Explicit)
            ts.push(current)
          }
          Some(Child(existing)) if !aot =>
            match existing.declaration {
              Implicit => {
                existing.declaration = Explicit
                current = existing
              }
              Explicit | Dotted =>
                raise problem(
                  source,
                  span.start,
                  InvalidToml,
                  "Table is already defined",
                )
            }
          _ =>
            raise problem(
              source,
              span.start,
              InvalidToml,
              "Conflicting table definition",
            )
        }
      }
    }
  }
}

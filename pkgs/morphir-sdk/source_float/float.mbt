///|
/// Source Float is IEEE binary32. Public Double transport is always rounded at
/// this boundary; the resulting Double holds the exact binary32 value.
pub fn round32(value : Double) -> Double {
  Float::from_double(value).to_double()
}

///|
pub fn add32(left : Double, right : Double) -> Double {
  (Float::from_double(left) + Float::from_double(right)).to_double()
}

///|
pub fn subtract32(left : Double, right : Double) -> Double {
  (Float::from_double(left) - Float::from_double(right)).to_double()
}

///|
pub fn multiply32(left : Double, right : Double) -> Double {
  (Float::from_double(left) * Float::from_double(right)).to_double()
}

///|
pub fn divide32(left : Double, right : Double) -> Double {
  (Float::from_double(left) / Float::from_double(right)).to_double()
}

///|
pub fn negate32(value : Double) -> Double {
  (-Float::from_double(value)).to_double()
}

///|
pub fn from_float64_exact(value : Double) -> @integer.Integer? {
  if value.is_nan() || value.is_inf() {
    return None
  }
  let integer = @integer.from_float_truncated(value) catch { _ => return None }
  if @integer.to_float(integer) == value {
    Some(integer)
  } else {
    None
  }
}

///|
pub fn from_float64_truncated(value : Double) -> @integer.Integer? {
  if value.is_nan() || value.is_inf() {
    return None
  }
  Some(@integer.from_float_truncated(value) catch { _ => return None })
}

///|
pub fn from_float64_floor(value : Double) -> @integer.Integer? {
  from_float64_truncated(value.floor())
}

///|
pub fn from_float64_ceiling(value : Double) -> @integer.Integer? {
  from_float64_truncated(value.ceil())
}

///|
pub fn from_float64_rounded(value : Double) -> @integer.Integer? {
  from_float64_truncated(value.round())
}

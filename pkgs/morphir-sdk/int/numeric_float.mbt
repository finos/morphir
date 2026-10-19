///|
/// Exact means the source float is a finite integer; no fractional rounding.
pub fn from_float64_exact(value : Double) -> @integer.Integer? {
  @source_float.from_float64_exact(value)
}

///|
pub fn from_float64_truncated(value : Double) -> @integer.Integer? {
  @source_float.from_float64_truncated(value)
}

///|
pub fn from_float64_floor(value : Double) -> @integer.Integer? {
  @source_float.from_float64_floor(value)
}

///|
pub fn from_float64_ceiling(value : Double) -> @integer.Integer? {
  @source_float.from_float64_ceiling(value)
}

///|
pub fn from_float64_rounded(value : Double) -> @integer.Integer? {
  @source_float.from_float64_rounded(value)
}

///|
pub fn from_float32_exact(value : Double) -> @integer.Integer? {
  from_float64_exact(@source_float.round32(value))
}

///|
pub fn from_float32_truncated(value : Double) -> @integer.Integer? {
  from_float64_truncated(@source_float.round32(value))
}

///|
pub fn from_float32_floor(value : Double) -> @integer.Integer? {
  from_float64_floor(@source_float.round32(value))
}

///|
pub fn from_float32_ceiling(value : Double) -> @integer.Integer? {
  from_float64_ceiling(@source_float.round32(value))
}

///|
pub fn from_float32_rounded(value : Double) -> @integer.Integer? {
  from_float64_rounded(@source_float.round32(value))
}

///|
pub fn to_float64_rounded(value : @integer.Integer) -> Double {
  @integer.to_float(value)
}

///|
pub fn to_float64_exact(value : @integer.Integer) -> Double? {
  let result = @integer.to_float(value)
  if @source_float.from_float64_exact(result) == Some(value) {
    Some(result)
  } else {
    None
  }
}

///|
pub fn to_float32_rounded(value : @integer.Integer) -> Double {
  let original = @integer.to_bigint(value)
  if original.is_zero() {
    return 0.0
  }
  let negative = original.compare_int(0) < 0
  let magnitude = if negative { -original } else { original }
  let bits = magnitude.bit_length()
  if bits > 129 {
    return if negative { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }
  let shift = Int32::max(bits - 24, 0)
  let mut leading = magnitude >> shift
  if shift > 0 {
    let remainder = magnitude - (leading << shift)
    let halfway = @bigint.BigInt::from_int(1) << (shift - 1)
    if remainder > halfway ||
      (
        remainder == halfway &&
        (leading & @bigint.BigInt::from_int(1)) != @bigint.BigInt::from_int(0)
      ) {
      leading = leading + @bigint.BigInt::from_int(1)
    }
  }
  let rounded = leading << shift
  if rounded.bit_length() > 128 {
    return if negative { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }
  @integer.to_float(
    @integer.from_bigint(if negative { -rounded } else { rounded }),
  )
}

///|
pub fn to_float32_exact(value : @integer.Integer) -> Double? {
  let result = to_float32_rounded(value)
  if @source_float.from_float64_exact(result) == Some(value) {
    Some(result)
  } else {
    None
  }
}

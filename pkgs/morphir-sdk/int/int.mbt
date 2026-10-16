///|
pub struct Int8 {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int8(n : @integer.Integer) -> Int8? {
  let low = @integer.from_int64(-128L)
  let high = @integer.from_int64(127L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int8(n : Int8) -> @integer.Integer {
  n.value
}

///|
pub struct Int16Value {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int16(n : @integer.Integer) -> Int16Value? {
  let low = @integer.from_int64(-32768L)
  let high = @integer.from_int64(32767L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int16(n : Int16Value) -> @integer.Integer {
  n.value
}

///|
pub struct Int32Value {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int32(n : @integer.Integer) -> Int32Value? {
  let low = @integer.from_int64(-2147483648L)
  let high = @integer.from_int64(2147483647L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int32(n : Int32Value) -> @integer.Integer {
  n.value
}

///|
pub struct Int64Value {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int64(n : @integer.Integer) -> Int64Value? {
  let low = @integer.from_int64(-9223372036854775808L)
  let high = @integer.from_int64(9223372036854775807L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int64(n : Int64Value) -> @integer.Integer {
  n.value
}

///|
pub extend Int8 with Eq::{equal, not_equal}

///|
pub extend Int8 with @debug.Debug::{to_repr}

///|
pub extend Int8 with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int16Value with Eq::{equal, not_equal}

///|
pub extend Int16Value with @debug.Debug::{to_repr}

///|
pub extend Int16Value with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int32Value with Eq::{equal, not_equal}

///|
pub extend Int32Value with @debug.Debug::{to_repr}

///|
pub extend Int32Value with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int64Value with Eq::{equal, not_equal}

///|
pub extend Int64Value with @debug.Debug::{to_repr}

///|
pub extend Int64Value with Compare::{compare, op_lt, op_le, op_gt, op_ge}

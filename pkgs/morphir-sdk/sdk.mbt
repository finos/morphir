///|
pub(all) enum Order {
  LT
  EQ
  GT
} derive(Eq, Debug)

///|
pub(all) suberror SdkError {
  DivisionByZero
  InvalidNumber(String)
  OutOfRange(String)
  InvalidComparison(String)
  UnrepresentableText(String)
} derive(Eq, Debug)

///|
pub fn order(n : Int32) -> Order {
  if n < 0 {
    LT
  } else if n > 0 {
    GT
  } else {
    EQ
  }
}

///|
pub fn order_int(value : Order) -> Int32 {
  match value {
    LT => -1
    EQ => 0
    GT => 1
  }
}

///|
/// Elm compares strings lexically by UTF-16 code units. MoonBit's `Compare`
/// instance for String uses shortlex order, so SDK adapters must use this.
pub fn string_order(left : String, right : String) -> Order {
  order(left.lexical_compare(right))
}

///|
pub fn text_order(left : Text, right : Text) -> Order {
  let a = left.to_units()
  let b = right.to_units()
  let count = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < count; i = i + 1 {
    if a[i] < b[i] {
      return LT
    }
    if a[i] > b[i] {
      return GT
    }
  }
  order(a.length() - b.length())
}

///|
pub extend Order with Eq::{equal, not_equal}

///|
pub extend Order with @debug.Debug::{to_repr}

///|
pub extend SdkError with Eq::{equal, not_equal}

///|
pub extend SdkError with @debug.Debug::{to_repr}

///|
/// Versioned MoonBit source extension, separate from the classic SDK inventory.
pub const PROFILE : String = "morphir-moonbit-source-string-v1"

///|
pub const INDEX_PROFILE : String = "morphir-moonbit-source-string-index-v1"

///|
pub const MAX_CODE_UNITS : Int32 = 1048576

///|
fn check_limit(limit : Int32) -> Unit raise @sdk.SdkError {
  if limit < 0 || limit > MAX_CODE_UNITS {
    raise @sdk.OutOfRange("MoonBit source String limit")
  }
}

///|
/// Return the same immutable Text after checking size and well-formed UTF-16.
pub fn require_valid(
  value : @sdk.Text,
  limit : Int32,
) -> @sdk.Text raise @sdk.SdkError {
  check_limit(limit)
  if value.length() > limit {
    raise @sdk.OutOfRange("MoonBit source String exceeds code-unit limit")
  }
  let units = value.to_units()
  let mut i = 0
  while i < units.length() {
    if units[i].is_leading_surrogate() {
      if i + 1 >= units.length() || !units[i + 1].is_trailing_surrogate() {
        raise @sdk.UnrepresentableText(
          "MoonBit source String requires well-formed UTF-16",
        )
      }
      i += 2
    } else if units[i].is_trailing_surrogate() {
      raise @sdk.UnrepresentableText(
        "MoonBit source String requires well-formed UTF-16",
      )
    } else {
      i += 1
    }
  }
  value
}

///|
/// Check both operands and preflight the result before allocating concatenation.
pub fn append_bounded(
  left : @sdk.Text,
  right : @sdk.Text,
  limit : Int32,
) -> @sdk.Text raise @sdk.SdkError {
  ignore(require_valid(left, limit))
  ignore(require_valid(right, limit))
  if left.length() > limit - right.length() {
    raise @sdk.OutOfRange(
      "MoonBit source String concatenation exceeds code-unit limit",
    )
  }
  @text.append(left, right)
}

///|
/// MoonBit String.length counts UTF-16 code units, including both surrogate units.
pub fn length_int32(
  value : @sdk.Text,
  limit : Int32,
) -> @int.Int32Value raise @sdk.SdkError {
  let checked = require_valid(value, limit)
  match @int.to_int32(@integer.from_int64(checked.length().to_int64())) {
    Some(result) => result
    None => raise @sdk.OutOfRange("MoonBit source String length")
  }
}

///|
/// Clamp both bounds, then move split surrogate boundaries toward the interior.
pub fn slice_owned(
  value : @sdk.Text,
  start : @int.Int32Value,
  end : @int.Int32Value,
  limit : Int32,
) -> @sdk.Text raise @sdk.SdkError {
  let units = require_valid(value, limit).to_units()
  let length = units.length()
  let start = match @integer.to_int(@int.from_int32(start)) {
    Some(n) => n
    None => raise @sdk.OutOfRange("MoonBit source String start index")
  }
  let end = match @integer.to_int(@int.from_int32(end)) {
    Some(n) => n
    None => raise @sdk.OutOfRange("MoonBit source String end index")
  }
  let mut first = start.max(0).min(length)
  let mut last = end.max(0).min(length)
  if first > 0 &&
    first < length &&
    units[first - 1].is_leading_surrogate() &&
    units[first].is_trailing_surrogate() {
    first += 1
  }
  if last > 0 &&
    last < length &&
    units[last - 1].is_leading_surrogate() &&
    units[last].is_trailing_surrogate() {
    last -= 1
  }
  if first >= last {
    return @sdk.Text::from_units([])
  }
  @sdk.Text::from_units(units[first:last].to_owned())
}

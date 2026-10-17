///|
/// Versioned MoonBit source extension, separate from the classic SDK inventory.
pub const PROFILE : String = "morphir-moonbit-source-string-v1"

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

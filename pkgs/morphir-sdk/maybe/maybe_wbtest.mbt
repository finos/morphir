///|
// Oracle: elm/core 1.0.5 Maybe.elm, exposed by Morphir.IR.SDK.Maybe.
test "Maybe combinators preserve presence and defaults" {
  let absent : Int32? = None
  assert_eq(map((n : Int32) => n + 1, Some(2)), Some(3))
  assert_eq(map((n : Int32) => n + 1, None), None)
  assert_eq(
    and_then((n : Int32) => if n > 0 { Some(n * 2) } else { None }, Some(2)),
    Some(4),
  )
  assert_eq(with_default(9, None), 9)
  assert_eq(with_default(9, Some(2)), 2)
  assert_eq(map2((a, b) => a + b, Some(1), Some(2)), Some(3))
  assert_eq(map3((a, b, c) => a + b + c, Some(1), Some(2), Some(3)), Some(6))
  assert_eq(
    map4((a, b, c, d) => a + b + c + d, Some(1), Some(2), Some(3), Some(4)),
    Some(10),
  )
  assert_eq(
    map5(
      (a, b, c, d, e) => a + b + c + d + e,
      Some(1),
      Some(2),
      Some(3),
      Some(4),
      Some(5),
    ),
    Some(15),
  )
  assert_false(has_value(absent))
}

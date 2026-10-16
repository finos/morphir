///|
// Oracle: elm/core 1.0.5 Result.elm, exposed by Morphir.IR.SDK.Result.
test "Result combinators keep the first error" {
  let first : Result[Int32, String] = Err("first")
  let second : Result[Int32, String] = Err("second")
  let one : Result[Int32, String] = Ok(1)
  let two : Result[Int32, String] = Ok(2)
  let three : Result[Int32, String] = Ok(3)
  let four : Result[Int32, String] = Ok(4)
  let five : Result[Int32, String] = Ok(5)
  let absent : Int32? = None
  assert_eq(map2((a, b) => a + b, first, second), Err("first"))
  assert_eq(map2((a, b) => a + b, one, second), Err("second"))
  assert_eq(map3((a, b, c) => a + b + c, one, two, three), Ok(6))
  assert_eq(map4((a, b, c, d) => a + b + c + d, one, two, three, four), Ok(10))
  assert_eq(
    map5((a, b, c, d, e) => a + b + c + d + e, one, two, three, four, five),
    Ok(15),
  )
  assert_eq(map_error((s : String) => s + "!", first), Err("first!"))
  assert_eq(to_maybe(first), None)
  assert_eq(from_maybe("missing", absent), Err("missing"))
  assert_eq(with_default(7, first), 7)
}

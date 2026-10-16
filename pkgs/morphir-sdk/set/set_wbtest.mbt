///|
// Oracle: elm/core 1.0.5 Set semantics exposed by Morphir.IR.SDK.Set.
fn int_order(a : Int32, b : Int32) -> @sdk.Order {
  @sdk.order(a - b)
}

///|
test "set deduplicates, orders and leaves inputs untouched" {
  let cmp : (Int32, Int32) -> @sdk.Order raise @sdk.SdkError = (a, b) => {
    int_order(a, b)
  }
  let left = from_list(cmp, @list.from_array([3, 1, 3, 2]))
  let right = from_list(cmp, @list.from_array([2, 4]))
  assert_eq(@list.to_array(to_list(left)), [1, 2, 3])
  assert_eq(@list.to_array(to_list(union(left, right))), [1, 2, 3, 4])
  assert_eq(@list.to_array(to_list(intersect(left, right))), [2])
  assert_eq(@list.to_array(to_list(diff(left, right))), [1, 3])
  assert_eq(@list.to_array(to_list(left)), [1, 2, 3])
  assert_eq(@list.to_array(to_list(map(cmp, n => n % 2, left))), [0, 1])
}

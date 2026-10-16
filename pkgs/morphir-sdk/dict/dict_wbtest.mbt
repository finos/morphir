///|
// Oracle: elm/core 1.0.5 Dict semantics exposed by Morphir.IR.SDK.Dict.
fn int_order(a : Int32, b : Int32) -> @sdk.Order {
  @sdk.order(a - b)
}

///|
test "duplicate keys, union bias, ordered traversal and immutability" {
  let cmp : (Int32, Int32) -> @sdk.Order raise @sdk.SdkError = (a, b) => {
    int_order(a, b)
  }
  let original = from_list(
    cmp,
    @list.from_array([(2, "first"), (1, "one"), (2, "last")]),
  )
  let right = from_list(cmp, @list.from_array([(2, "right"), (3, "three")]))
  assert_eq(@list.to_array(to_list(original)), [(1, "one"), (2, "last")])
  assert_eq(@list.to_array(to_list(union(original, right))), [
    (1, "one"),
    (2, "last"),
    (3, "three"),
  ])
  assert_eq(@list.to_array(to_list(intersect(original, right))), [(2, "last")])
  assert_eq(@list.to_array(to_list(diff(original, right))), [(1, "one")])
  assert_eq(@list.to_array(to_list(original)), [(1, "one"), (2, "last")])
  assert_eq(foldl((k, _, acc) => acc * 10 + k, 0, original), 12)
  assert_eq(foldr((k, _, acc) => acc * 10 + k, 0, original), 21)
}

///|
test "merge visits combined keys in ascending order" {
  let cmp : (Int32, Int32) -> @sdk.Order raise @sdk.SdkError = (a, b) => {
    int_order(a, b)
  }
  let left = from_list(cmp, @list.from_array([(1, "a"), (3, "c")]))
  let right = from_list(cmp, @list.from_array([(2, "b"), (3, "d")]))
  let result = merge(
    (k : Int32, _, acc) => acc + "L" + k.to_string(),
    (k : Int32, _, _, acc) => acc + "B" + k.to_string(),
    (k : Int32, _, acc) => acc + "R" + k.to_string(),
    left,
    right,
    "",
  )
  assert_eq(result, "L1R2B3")
}

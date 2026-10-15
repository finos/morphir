///|
test "let order without a cycle is the DFS post-order" {
  assert_eq(@lower.let_groups([[], [], []]), [Single(0), Single(1), Single(2)])
  // a = b; b = 1; c = 2
  assert_eq(@lower.let_groups([[1], [], []]), [Single(1), Single(0), Single(2)])
  // x = 1; y = z; z = x
  assert_eq(@lower.let_groups([[], [2], [0]]), [Single(0), Single(2), Single(1)])
  // c = b + 1; b = a + 1; a = 1
  assert_eq(@lower.let_groups([[1], [2], []]), [Single(2), Single(1), Single(0)])
}

///|
test "let order with a cycle uses Kosaraju components" {
  // p = q 1; q k = r k; r k = q k; s = p
  assert_eq(@lower.let_groups([[1], [2], [1], [0]]), [
    Recursive([1, 2]),
    Single(0),
    Single(3),
  ])
  // loop n = loop n
  assert_eq(@lower.let_groups([[0]]), [Recursive([0])])
}

///|
test "let order with a cycle keeps the plain declarations around it" {
  // z = 1; s = p; p = q 1; q k = r k; r k = q k; w = z
  // morphir-elm make 2.100.0: z, letrec {q, r}, p, s, w.
  assert_eq(@lower.let_groups([[], [2], [3], [4], [3], [0]]), [
    Single(0),
    Recursive([3, 4]),
    Single(2),
    Single(1),
    Single(5),
  ])
}

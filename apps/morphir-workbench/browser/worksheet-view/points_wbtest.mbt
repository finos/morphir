///|
test "captured UTF16 offsets map CRLF and surrogate pairs to editor positions" {
  assert_eq(point("😀\r\nx", 0), (1, 1))
  assert_eq(point("😀\r\nx", 2), (1, 3))
  assert_eq(point("😀\r\nx", 4), (2, 1))
  assert_eq(point("😀\r\nx", 5), (2, 2))
  assert_eq(point("a\rb\nc", 4), (3, 1))
}

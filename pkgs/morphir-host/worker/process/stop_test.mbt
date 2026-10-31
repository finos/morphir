///|
test "process workers have a 2 second exit grace" {
  assert_eq(@process.EXIT_GRACE_MS, 2000)
  assert_true(@process.STOP_CONFIRM_MS > @process.EXIT_GRACE_MS)
}

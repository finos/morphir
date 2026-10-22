///|
test "fixture executable preserves last literal operand and executable fallback" {
  assert_eq(
    fixture_executable("original executable/雪", []),
    "original executable/雪",
  )
  for
    path in [
      "fixture.exe", "folder with spaces/雪.exe", "", "--", "--help", "-x", "--morphir-native-worker",
    ] {
    assert_eq(fixture_executable("original", [path]), path)
    assert_eq(
      fixture_executable("original", ["ignored", "--", "--unknown", path]),
      path,
    )
  }
}

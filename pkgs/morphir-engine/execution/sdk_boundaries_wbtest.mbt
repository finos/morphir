///|
test "integral invocation boundaries reject out-of-range values before provider use" {
  for
    (owner, tag, maximum, outside) in [
      ("int-16", "int16", "32767", "32768"),
      ("int-64", "int64", "9223372036854775807", "9223372036854775808"),
      ("byte", "byte", "255", "256"),
      ("uint-16", "uint-16", "65535", "65536"),
      ("uint-32", "uint-32", "4294967295", "4294967296"),
      ("uint-64", "uint-64", "18446744073709551615", "18446744073709551616"),
    ] {
    fn boundary(value : String) -> @protocol.Value raise {
      @protocol.Value::from_json({
        "type": "custom",
        "owner": "morphir/SDK:int#" + owner,
        "tag": "morphir/SDK:int#" + tag,
        "items": [{ "type": "int", "value": value }],
      })
    }
    validate_sdk_boundary(boundary(maximum))
    for invalid in ["-1", outside] {
      if owner.has_prefix("int-") && invalid == "-1" {
        continue
      }
      try {
        validate_sdk_boundary(boundary(invalid))
        fail("Expected integral range refusal")
      } catch {
        @protocol.Invalid(code) =>
          assert_eq(
            code,
            "execution." + owner.replace(old="-", new="") + "_range",
          )
        error => raise error
      }
    }
  }
}

///|
// Header recognition stays in the shared data parser. JSON is only the fixed
// JavaScript ABI result, not a second projection parser or inspection decision.
#export_name("recognize_projection_header")
pub fn recognize_projection_header(
  bytes : Bytes,
  max_bytes : Int32,
  max_depth : Int32,
  max_values : Int32,
) -> String {
  let result : Json = try {
    let header = @data.recognize_projection_header(bytes, {
      max_bytes,
      max_depth,
      max_values,
    })
    {
      "kind": "recognized",
      "release": @version.FormatVersion::to_release_string(header),
    }
  } catch {
    @data.Invalid(code, _) => { "kind": "refused", "code": code }
    _ => { "kind": "refused", "code": "data.decode_failed" }
  }
  result.stringify()
}

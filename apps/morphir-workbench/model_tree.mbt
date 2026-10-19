///|
/// Capture private worker bytes under the same aggregate limit as file import.
/// The shared reader owns tree layout, version and semantic validation.
fn inspect_tree(request : Json) -> @data.CheckpointInspection raise {
  let entries = @wire.array(@wire.field(request, "sourceTree"))
  guard !entries.is_empty() && entries.length() <= @data.model_tree_file_limit else {
    raise @data.Invalid("data.byte_limit", "Tree exceeds the file budget")
  }
  let files : Map[String, Bytes] = Map([])
  let mut total = 0
  let mut path_units = 0
  for entry in entries {
    @wire.fields(entry, ["path", "contentBase64"])
    let path = @wire.string(@wire.field(entry, "path"))
    guard path.length() <= 4096 && !files.contains(path) else {
      raise @data.Invalid(
        "data.invalid_path", "Duplicate or oversized tree path",
      )
    }
    guard path.length() <= 1048576 - path_units else {
      raise @data.Invalid(
        "data.tree_limit", "Tree exceeds the path text budget",
      )
    }
    path_units += path.length()
    let encoded = @wire.string(@wire.field(entry, "contentBase64"))
    let remaining = 16 * 1024 * 1024 - total
    guard encoded.length() <= (remaining + 2) / 3 * 4 else {
      raise @data.Invalid(
        "data.byte_limit", "Tree exceeds the source byte budget",
      )
    }
    let bytes = @base64.decode(encoded[:])
    guard bytes.length() <= remaining && @base64.encode(bytes[:]) == encoded else {
      raise @data.Invalid(
        "data.invalid_encoding", "Invalid captured tree bytes",
      )
    }
    total += bytes.length()
    files[path] = bytes
  }
  @data.inspect_model_tree(files, limits={
    max_bytes: 16 * 1024 * 1024,
    max_depth: 128,
    max_values: 100000,
  })
}

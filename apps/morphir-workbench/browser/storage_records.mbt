///|
fn items_of_file_manifest(manifest : Json) -> Array[String] {
  match field(manifest, "files") {
    Object(files) =>
      files
      .values()
      .filter_map(value => {
        match value {
          String(key) => Some(key)
          _ => None
        }
      })
      .collect()
    _ => []
  }
}

///|
fn metadata_receipt(
  path : String,
  operation : String,
  project : String,
) -> Json raise {
  let bytes = metadata_read_file(path + "/receipt.json", 16384, fn() { () })
  if bytes.length() > 16384 {
    raise @config.Invalid("metadata.restore_invalid_receipt")
  }
  let receipt = @wire.parse(@utf8.decode(bytes[:]))
  if build_text(receipt, "profile") != "morphir-metadata-receipt-v1" ||
    build_text(receipt, "invocation") != operation ||
    build_text(receipt, "projectScope") != project {
    raise @config.Invalid("metadata.restore_invalid_receipt")
  }
  receipt
}

///|
fn metadata_dispose_tree(root : String, deadline : Double) -> Unit raise {
  let mut count = 0
  fn walk(path : String, depth : Int) -> Unit raise {
    count += 1
    if count > 16384 || depth > 64 || @platform.monotonic_seconds() >= deadline {
      raise @config.Invalid("metadata.restore_cleanup_limit: scratch retained")
    }
    match @platform.kind(path) {
      0 => ()
      2 => {
        for name in @platform.list(path) {
          if name == "" ||
            name == "." ||
            name == ".." ||
            name.contains("/") ||
            name.contains("\\") {
            raise @config.Invalid("metadata.restore_invalid_cleanup_path")
          }
          walk(path + "/" + name, depth + 1)
        }
        @platform.remove_dir(path)
      }
      _ => @platform.remove_file(path)
    }
  }
  walk(root, 0)
  if @platform.monotonic_seconds() >= deadline {
    raise @config.Invalid("metadata.restore_cleanup_limit: deadline exceeded")
  }
}

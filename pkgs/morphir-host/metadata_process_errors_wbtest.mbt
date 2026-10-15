///|
test "process failures remain typed metadata diagnostics at the interpreter boundary" {
  let cases : Array[(Error, String)] = [
    (
      @config.Invalid(
        "metadata.restore_executable_changed: selected service pin",
      ),
      "metadata.restore_executable_changed",
    ),
    (
      @metadata_wire.Invalid("metadata.restore_invalid_response: Wrong profile"),
      "metadata.restore_invalid_response",
    ),
    (@protocol.Invalid("Cancelled"), "metadata.restore_cancelled"),
    (
      @platform.IOError("metadata.restore_runtime_unavailable"),
      "metadata.restore_runtime_unavailable",
    ),
    (
      @config.Invalid("execution.tree_termination_failed"),
      "metadata.restore_process_failed",
    ),
  ]
  for (source, expected) in cases {
    let typed = try {
      metadata_process_boundary("project", fn() raise { raise source })
      false
    } catch {
      @linked_metadata.Invalid(code, context, detail) =>
        code == expected && context == "project" && detail.length() <= 1024
      _ => false
    }
    assert_true(typed)
  }
}

///|
/// Translate owned host errors before crossing the metadata capability boundary.
/// Unknown exceptions expose no body; logging uses fixed lifecycle codes only.
fn[T] metadata_process_boundary(
  context : String,
  run : () -> T raise,
) -> T raise {
  run() catch {
    @linked_metadata.Invalid(_, _, _) as error => raise error
    error => {
      let message = match error {
        @metadata_wire.Invalid(message) => message
        _ => error_message(error)
      }
      let code = if message == "Cancelled" {
        "metadata.restore_cancelled"
      } else if message.has_prefix("metadata.restore_") {
        message
        .split_once(":")
        .map(pair => pair.0.to_owned())
        .unwrap_or(message)
      } else {
        "metadata.restore_process_failed"
      }
      let detail = if message.has_prefix("metadata.restore_") ||
        message.has_prefix("execution.") ||
        message == "Cancelled" {
        if message.length() > 1024 {
          message[:1024].to_owned()
        } else {
          message
        }
      } else {
        "The qualified provider exchange refused; check host grants and service profile"
      }
      raise @linked_metadata.Invalid(code, context, detail)
    }
  }
}

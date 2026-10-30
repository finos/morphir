///|
priv struct TextSink {
  write : (String) -> Unit
  clock : () -> @formatting.LogTimestamp
}

///|
impl @logging.Logger for TextSink with fn log(self, event) {
  let record = @formatting.LogRecord::capture(event, (self.clock)())
  (self.write)(@formatting.format_text(record))
}

///|
/// A synchronous text adapter for hosts whose owner supplies stderr and UTC time.
/// Formatting and level filtering remain Moon-Lander responsibilities.
pub fn text_logger(
  level : DiagnosticLevel,
  write : (String) -> Unit,
  clock : () -> @formatting.LogTimestamp,
) -> &@logging.Logger {
  level.filter(TextSink::{ write, clock, })
}

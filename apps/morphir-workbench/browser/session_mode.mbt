///|
/// The selected page experience. It is presentation, never source authority.
enum SessionMode {
  LocalRuntime
  ConnectedRuntime
  ConnectedOriginals
} derive(Eq)

///|
extern "js" fn session_mode_text() -> String =
  #|() => globalThis.morphirWorkbench.mode ?? (globalThis.morphirWorkbench.connected ? 'connected' : 'local')

///|
fn session_mode() -> SessionMode {
  match session_mode_text() {
    "connected-originals" => ConnectedOriginals
    "connected" => ConnectedRuntime
    _ => LocalRuntime
  }
}

///|
fn startup_cmd(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  match session_mode() {
    ConnectedOriginals => @cmd.none
    LocalRuntime | ConnectedRuntime =>
      request_cmd(
        emit,
        0,
        0,
        object([("operation", Json::string("initialize"))]),
      )
  }
}

///|
async fn main {
  let app = @proton.asset(
    "Morphir Workbench",
    "frontend/dist/index.html",
    width=1280,
    height=860,
  ).load_config()
  let app = match @env.get_env_vars().get("MORPHIR_WORKBENCH_LAUNCH_URL") {
    None => with_native_session(app)
    Some(url) => {
      if !loopback_launch(url) {
        abort("Expected an authenticated loopback launch URL")
      }
      app.entry_url(url)
    }
  }
  app.run_or_abort()
}

///|
/// An explicit host launch keeps its cookie and HTTP requests in one origin.
/// The one-use token is neither logged nor persisted by this application.
fn loopback_launch(url : String) -> Bool {
  guard url.strip_prefix("http://127.0.0.1:") is Some(rest) else {
    return false
  }
  let parts = rest.split("/launch?token=").collect()
  guard parts.length() == 2 else { return false }
  let port = parts[0]
  if port.is_empty() ||
    port.length() > 5 ||
    !port.iter().all(c => c >= '0' && c <= '9') {
    return false
  }
  let number = @string.parse_int(port) catch { _ => return false }
  let token = parts[1]
  number > 0 &&
  number <= 65535 &&
  !token.is_empty() &&
  token.length() <= 256 &&
  token
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_'
  })
}

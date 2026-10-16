///|
fn canonical_loopback_origin(origin : String) -> String? {
  if origin == "http://127.0.0.1" {
    return Some(origin)
  }
  guard origin.strip_prefix("http://127.0.0.1:") is Some(port) &&
    !port.is_empty() &&
    port.length() <= 5 &&
    port.iter().all(c => c >= '0' && c <= '9') else {
    return None
  }
  let value = @string.parse_int(port) catch { _ => return None }
  guard value > 0 && value <= 65535 else { return None }
  Some(
    if value == 80 {
      "http://127.0.0.1"
    } else {
      "http://127.0.0.1:" + value.to_string()
    },
  )
}

///|
/// The explicit connected launch shape. The token never becomes download data.
pub fn loopback_launch_origin(url : String) -> String? {
  guard url.has_prefix("http://127.0.0.1:") else { return None }
  let parts = url.split("/launch?token=").collect()
  guard parts.length() == 2 else { return None }
  let token = parts[1]
  guard !token.is_empty() &&
    token.length() <= 256 &&
    token
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_'
    }) else {
    return None
  }
  canonical_loopback_origin(parts[0].to_owned())
}

///|
/// Only the host supplies the current native page URL and configured origin.
/// Approval always means a system save dialog, never a renderer-selected path.
pub fn allow_blob_export(
  window : String,
  page_url : String,
  download_url : String,
  connected_origin~ : String? = None,
) -> Bool {
  guard window == "main" else { return false }
  let origins = match connected_origin {
    None => ["https://proton.localhost", "proton://app"]
    Some(origin) => {
      guard canonical_loopback_origin(origin) == Some(origin) else {
        return false
      }
      [origin]
    }
  }
  origins.any(origin => {
    let prefix = "blob:" + origin + "/"
    page_url.has_prefix(origin + "/") &&
    download_url.has_prefix(prefix) &&
    download_url.length() > prefix.length()
  })
}

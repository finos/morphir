///|
async fn main {
  if @env.args().contains("--morphir-native-worker") {
    @native.worker()
    return
  }
  let app = @proton.asset(
    "Morphir Workbench",
    "frontend/dist/index.html",
    width=1280,
    height=860,
  ).load_config()
  let launch = @env.get_env_vars().get("MORPHIR_WORKBENCH_LAUNCH_URL")
  let connected_origin = match launch {
    None => None
    Some(url) => {
      guard @session.loopback_launch_origin(url) is Some(origin) else {
        abort("Expected an authenticated loopback launch URL")
      }
      Some(origin)
    }
  }
  let app = match launch {
    None => with_native_session(app)
    Some(url) => app.entry_url(url)
  }
  app
  .on_download_request(async fn(browser, request) noraise {
    let page = browser.state() catch {
      _ => return @proton.DownloadDecision::Deny
    }
    if @session.allow_blob_export(
        browser.window_id(),
        page.url,
        request.url,
        connected_origin~,
      ) {
      @proton.DownloadDecision::ShowSaveDialog
    } else {
      @proton.DownloadDecision::Deny
    }
  })
  .run_or_abort()
}

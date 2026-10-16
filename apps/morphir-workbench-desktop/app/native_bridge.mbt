///|
fn native_caller(context : @proton.CommandContext) -> @session.Caller raise {
  @session.Caller::admit(
    context.window_id(),
    context.source_origin(),
    context.page_instance(),
  )
}

///|
fn with_native_session(app : @proton.App) -> @proton.App {
  let session = @session.Session::new()
  let open : @contract.Command[String, Json] = @contract.command(
    "workbench_session_open",
  )
  let check : @contract.Command[String, Json] = @contract.command(
    "workbench_session_check",
  )
  let close : @contract.Command[String, Json] = @contract.command(
    "workbench_session_close",
  )
  app
  .commands(
    fn(registrar) raise {
      registrar.bind(open, fn(context, version) {
        session.open(native_caller(context), version) catch {
          error => @session.failure(error)
        }
      })
      registrar.bind(check, fn(context, id) {
        session.check(native_caller(context), id) catch {
          error => @session.failure(error)
        }
      })
      registrar.bind(close, fn(context, id) {
        session.close(native_caller(context), id) catch {
          error => @session.failure(error)
        }
      })
    },
    targets=[@proton.RendererTarget::bundled()],
  )
  .on_browser_event(fn(browser, event) {
    if browser.window_id() == "main" {
      match event {
        DidStartLoading | BridgeFailed(_) | RendererProcessTerminated(..) =>
          session.revoke()
        _ => ()
      }
    }
  })
  .on_window_event(fn(window, event) {
    if window.id() == "main" && event == Closed {
      session.shutdown()
    }
  })
  .on_quit(fn(_, _) { session.shutdown() })
}

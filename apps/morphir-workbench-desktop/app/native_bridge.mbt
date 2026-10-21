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
  let mut owner : @bridge.Owner? = None
  let files = @bridge.FileOwner::new(
    enabled=@native.desktop_supported() && @workspace.supported(),
  )
  app
  .app_lifecycle(
    on_start=fn(context) {
      owner = Some(
        @bridge.Owner::new(
          context.task_group(),
          context.application_executable,
          executions=@native.desktop_supported(),
          contract=@request.CapabilityChecks,
          workspace=@native.desktop_supported() && @workspace.supported(),
        ),
      )
    },
    on_shutdown=async fn(_) {
      files.close()
      if owner is Some(owner) {
        owner.shutdown()
      }
    },
  )
  .commands(
    fn(registrar) raise {
      registrar.bind(@contract.command("workbench_native"), async fn(
        context,
        source : String,
      ) -> String {
        if @bridge.is_file_request(source) {
          return files.request(source, fn() raise { native_caller(context) }, async fn() {
            guard context.window() is Some(window) else {
              raise @session.Rejected("workbench.native_caller")
            }
            window.choose_directory(
              Some("Open Morphir workspace for editing"),
              None,
            )
          })
        }
        guard owner is Some(owner) else {
          return @utf8.decode(
            @reply.failure(@reply.Unavailable, @reply.NoEffect),
          )
        }
        owner.request(source, fn() raise { native_caller(context) }, async fn() {
          guard context.window() is Some(window) else {
            raise @session.Rejected("workbench.native_caller")
          }
          window.choose_directory(Some("Open Morphir workspace"), None)
        })
      })
    },
    targets=[@proton.RendererTarget::bundled()],
  )
  .on_browser_event(fn(browser, event) {
    if browser.window_id() == "main" {
      match event {
        DidStartLoading | BridgeFailed(_) | RendererProcessTerminated(..) => {
          files.revoke()
          if owner is Some(owner) {
            owner.revoke()
          }
        }
        _ => ()
      }
    }
  })
  .on_window_event(fn(window, event) {
    if window.id() == "main" && event == Closed {
      files.close()
      if owner is Some(owner) {
        owner.close()
      }
    }
  })
  .on_before_quit(async fn(_) noraise {
    try {
      files.close()
      if owner is Some(owner) {
        owner.shutdown()
      }
      @proton.ApplicationQuitDecision::Allow
    } catch {
      _ => {
        @stdio.stderr.write(
          "Morphir: quit prevented because native worker exit could not be confirmed.\n",
        ) catch {
          _ => ()
        }
        @proton.ApplicationQuitDecision::Prevent
      }
    }
  })
}

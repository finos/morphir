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
  let session = @session.Session::new(jobs=@native.desktop_supported())
  let services : Map[String, @native.Service] = Map([])
  let mut group : @async.TaskGroup[Unit]? = None
  let mut executable = ""
  let mut cleanup_failed = false
  fn revoke() {
    session.revoke()
    for (id, service) in services.to_array() {
      service.close()
      if group is Some(tasks) {
        tasks.spawn_bg(async fn() {
          try {
            service.shutdown()
            services.remove(id)
          } catch {
            _ => {
              cleanup_failed = true
              @stdio.stderr.write(
                "Morphir: native worker exit could not be confirmed after page revocation.\n",
              ) catch {
                _ => ()
              }
            }
          }
        })
      }
    }
  }
  app
  .app_lifecycle(
    on_start=fn(context) {
      group = Some(context.task_group())
      executable = context.application_executable
    },
    on_shutdown=async fn(_) {
      session.shutdown()
      for (_, service) in services.to_array() {
        service.shutdown()
      }
      services.clear()
    },
  )
  .commands(
    fn(registrar) raise {
      registrar.bind(@contract.command("workbench_session_open"), async fn(
        context,
        version : String,
      ) -> Json {
        try {
          let caller = native_caller(context)
          let reply = session.open(caller, version)
          guard reply is Object(fields) &&
            fields.get("sessionId") is Some(String(id)) else {
            abort("Invalid native descriptor")
          }
          // A new page cannot claim workers until all previous-page children exit.
          for (old_id, old) in services.to_array() {
            if old_id != id {
              old.shutdown()
              services.remove(old_id)
            }
          }
          guard !cleanup_failed else {
            raise @session.Rejected("workbench.native_cleanup")
          }
          ignore(session.check(caller, id))
          if @native.desktop_supported() && !services.contains(id) {
            guard group is Some(tasks) && executable != "" else {
              raise @session.Rejected("workbench.native_startup")
            }
            services[id] = @native.Service::new(tasks, executable, id)
          }
          reply
        } catch {
          error => @session.failure(error)
        }
      })
      registrar.bind(@contract.command("workbench_session_check"), fn(
        context,
        id : String,
      ) -> Json {
        session.check(native_caller(context), id) catch {
          error => @session.failure(error)
        }
      })
      registrar.bind(@contract.command("workbench_session_close"), async fn(
        context,
        id : String,
      ) -> Json {
        try {
          let reply = session.close(native_caller(context), id)
          if services.get(id) is Some(service) {
            service.shutdown()
            services.remove(id)
          }
          reply
        } catch {
          error => @session.failure(error)
        }
      })
      registrar.bind(@contract.command("workbench_job"), fn(
        context,
        source : String,
      ) -> Json {
        try {
          let (id, path, body) = @native.bridge_request(source)
          ignore(session.check(native_caller(context), id))
          guard services.get(id) is Some(service) else {
            raise @session.Rejected("workbench.native_jobs_unavailable")
          }
          service.request(path, body)
        } catch {
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
          revoke()
        _ => ()
      }
    }
  })
  .on_window_event(fn(window, event) {
    if window.id() == "main" && event == Closed {
      revoke()
      session.shutdown()
    }
  })
  .on_before_quit(async fn(_) noraise {
    session.shutdown()
    try {
      for (_, service) in services.to_array() {
        service.shutdown()
      }
      services.clear()
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

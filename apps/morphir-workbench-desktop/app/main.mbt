///|
async fn main {
  let args = @env.args()
  let wire = args.contains("--morphir-native-worker")
  let mode = presentation_mode(args[1:]) catch {
    error => {
      let text = presentation_event(1, "failure", {
        "error": {
          "code": "argument_error",
          "message": Json(error.to_string()),
        },
        "exitCode": 2,
      })
      if wire {
        @stdio.stderr.write(text)
      } else {
        @stdio.stdout.write(text)
      }
      presentation_exit(2)
      return
    }
  }
  let enabled = match mode {
    Human => false
    Events => true
    Help(text) => {
      if wire {
        @stdio.stderr.write(presentation_help(text))
      } else {
        @stdio.stdout.write(presentation_help(text))
      }
      return
    }
  }
  let presentation = DesktopPresentation::{ enabled, wire, sequence: 0, }
  if wire {
    if !enabled {
      @native.worker()
      return
    }
    presentation.report(Startup)
    try {
      @native.worker()
      presentation.report(Exit(0))
    } catch {
      error => {
        presentation.report(Failure("worker_error", error.to_string()))
        presentation.report(Exit(1))
        presentation_exit(1)
      }
    }
    return
  }
  presentation.report(Startup)
  let status = desktop_run(presentation) catch {
    error => {
      let message = match error {
        @diagnostics.InvalidLevel(_) as failure => failure.message()
        @diagnostics.InvalidFileFormat(_) as failure => failure.message()
        _ => @host.error_message(error)
      }
      if presentation.enabled {
        presentation.report(Failure("desktop_start_failed", message))
      } else {
        @stdio.stderr.write(message + "\n") catch {
          _ => ()
        }
      }
      1
    }
  }
  presentation.report(Exit(status))
  if status != 0 {
    presentation_exit(status)
  }
}

///|
async fn desktop_run(presentation : DesktopPresentation) -> Int32 {
  let environment = @env.get_env_vars()
  let location = @host.locate(".")
  let options = @host.configuration_options(location, environment)
  let document = @host.run_configuration(location, environment, options)
  let settings = @diagnostics.Settings::from_config(document.framework())
  let directory = @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse(location.root + "/.morphir/logs"),
  )
  @runtime.with_session(settings.session(directory), session => {
    let logger = @logging.with_category(
      session.logger(),
      "morphir.workbench.desktop",
    )
    let configuration_logger = @logging.with_category(
      session.logger(),
      "morphir.configuration",
    )
    for report in document.framework().reports() {
      if report.status is Loaded && report.path is Some(path) {
        configuration_logger.debug("Loaded configuration {path}", [Json(path)])
      }
    }
    let status = desktop_app(presentation, document.framework(), logger)
    let report = session.close()
    for message in report.failure_messages() {
      ignore(@runtime.write_diagnostic(message + "\n"))
    }
    if status == 0 && report.delivery_failed() {
      1
    } else {
      status
    }
  })
}

///|
async fn desktop_app(
  presentation : DesktopPresentation,
  configuration : @configuration.Config,
  logger : &@logging.Logger,
) -> Int32 {
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
        if presentation.enabled {
          presentation.report(
            Failure(
              "invalid_launch_url", "Expected an authenticated loopback launch URL",
            ),
          )
          return 1
        } else {
          raise @session.Rejected(
            "Expected an authenticated loopback launch URL",
          )
        }
      }
      Some(origin)
    }
  }
  let app = match launch {
    None => with_native_session(app, presentation, configuration, logger)
    Some(url) => app.entry_url(url)
  }
  let app = app.on_download_request(fn(browser, request) noraise {
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
  let status = Ref(0)
  if presentation.enabled {
    app
    .on_window_event(async fn(_, event) noraise {
      if event is ReadyToShow {
        presentation.report(WindowReady)
      }
    })
    .on_browser_event(async fn(_, event) noraise {
      match event {
        DidFinishLoad => presentation.report(BrowserLoaded)
        LoadFailed(error_code~, error_text~, ..) =>
          presentation.report(
            Failure(
              "browser_load_failed",
              error_code.to_string() + ": " + error_text,
            ),
          )
        BridgeFailed(diagnostic~) =>
          presentation.report(Failure(diagnostic.code, diagnostic.message))
        RendererProcessTerminated(status~, error_code~, detail~, ..) =>
          presentation.report(
            Failure(
              "renderer_process_terminated",
              status.to_string() + "/" + error_code.to_string() + ": " + detail,
            ),
          )
        _ => ()
      }
    })
    .on_quit(fn(_, code) noraise { status.val = code })
    .run() catch {
      error => {
        presentation.report(
          Failure(desktop_run_error_code(error), error.message()),
        )
        return 1
      }
    }
  } else {
    app.on_quit(fn(_, code) noraise { status.val = code }).run() catch {
      error => {
        @stdio.stderr.write(error.message() + "\n")
        return 1
      }
    }
  }
  status.val
}

///|
fn desktop_run_error_code(error : @proton.AppRunError) -> String {
  match error {
    EventLoopError(_) => "event_loop_error"
    ConfigurationError(_) => "configuration_error"
    LoggingInitializationFailed(..) => "logging_initialization_failed"
    UnsupportedNativeFeature(..) => "unsupported_native_feature"
    RuntimeOperationFailed(..) => "runtime_operation_failed"
    CommandExtensionLifecycleError(_) => "command_extension_lifecycle_error"
    LifecycleHookError(_) => "lifecycle_hook_error"
    EntryLoadError(_) => "entry_load_error"
    BridgeStartupError(_) => "bridge_startup_error"
    BridgeRuntimeError(_) => "bridge_runtime_error"
    CleanupFailed(..) => "cleanup_failed"
    UnexpectedTaskFailure(..) => "unexpected_task_failure"
  }
}

///|
pub(all) struct ContentPublication {
  stage : (@engine.ContentArtifact) -> Unit raise
  commit : (String) -> Unit raise
  abort : () -> Unit raise
}

///|
pub(all) struct ContentPublisher {
  guarantee : PublicationGuarantee
  write_bytes : Bool
  begin : (Array[String]) -> ContentPublication raise
}

///|
pub(all) struct ContentResult {
  report : @engine.ContentReport
  validated : Array[ValidatedProject]
  committed : Array[String]
  publication_error : String?
  cancelled : Bool
}

///|
pub fn ContentResult::successful(self : ContentResult) -> Bool {
  self.report.successful() && self.publication_error is None && !self.cancelled
}

///|
fn content_size(content : @data.Content) -> Int32 {
  match content {
    Text(text) => @utf8.encode(text[:]).length()
    Binary(bytes) => bytes.length()
  }
}

///|
pub fn Host::run_content(
  self : Host,
  engine : @engine.Engine,
  plan : @engine.Plan,
  publisher : ContentPublisher,
  read_bytes~ : ((String) -> Bytes raise)? = None,
) -> ContentResult raise {
  if plan.requires_byte_read() && read_bytes is None {
    raise @config.Invalid(
      "host.byte_read_required: Ion binary input requires a byte reader",
    )
  }
  let boundaries = plan.boundaries()
  if plan.requires_byte_write() && !publisher.write_bytes {
    raise @config.Invalid(
      "host.byte_write_required: Ion binary output requires a byte publisher",
    )
  }
  let content = Map([])
  let mut bytes = 0
  for path in plan.sources() {
    if (self.cancelled)() {
      raise @config.Invalid("Cancelled")
    }
    let binary = boundaries.any(b => b.source == path && b.read_bytes)
    let value = if binary {
      @data.Binary(read_bytes.unwrap()(path))
    } else {
      @data.Text((self.input.read)(path))
    }
    bytes = bytes + content_size(value)
    if bytes > self.limits.max_bytes {
      raise @config.Invalid("Source byte limit exceeded")
    }
    content[path] = value
  }
  (self.event)(Phase("execute"))
  self.metadata_sessions.begin()
  let report = engine.execute_content(
    plan,
    fn(path, _) raise {
      match content.get(path) {
        Some(value) => value
        None => raise @config.Invalid("Missing source snapshot: " + path)
      }
    },
    cancelled=self.cancelled,
  )
  let cleanup_error = self.metadata_sessions.dispose(FinishExecution)
  for diagnostic in report.diagnostics {
    (self.event)(Diagnostic(diagnostic))
  }
  for project in report.projects {
    (self.event)(Generated(project))
  }
  let mut validated = []
  let committed = []
  let mut publication_error = cleanup_error
  let mut cancelled = (self.cancelled)()
  if report.successful() && !cancelled && publication_error is None {
    let mut transaction : ContentPublication? = None
    try {
      if report.artifacts.length() + report.projects.length() >
        self.limits.max_files {
        raise @config.Invalid("Artifact entry limit exceeded")
      }
      bytes = 0
      for artifact in report.artifacts {
        bytes += content_size(artifact.content)
        if bytes > self.limits.max_bytes {
          raise @config.Invalid("Artifact byte limit exceeded")
        }
      }
      validated = self.validate_libraries(report)
      if report.artifacts.length() + report.projects.length() >
        self.limits.max_files {
        raise @config.Invalid("Artifact entry limit exceeded")
      }
      for value in validated {
        (self.event)(Validated(value))
      }
      bytes = 0
      for artifact in report.artifacts {
        bytes = bytes + content_size(artifact.content)
        if bytes > self.limits.max_bytes {
          raise @config.Invalid("Artifact byte limit exceeded")
        }
      }
      let publication = (publisher.begin)(plan.destinations())
      transaction = Some(publication)
      for artifact in report.artifacts {
        (publication.stage)(artifact)
      }
      for destination in plan.destinations() {
        if (self.cancelled)() {
          cancelled = true
          raise @config.Invalid("Cancelled")
        }
        (self.event)(Phase("publish " + destination))
        (publication.commit)(destination)
        committed.push(destination)
        (self.event)(Published(destination))
      }
    } catch {
      error => publication_error = Some(error_message(error))
    }
    cancelled = cancelled || (self.cancelled)()
    if transaction is Some(publication) {
      (publication.abort)() catch {
        error =>
          publication_error = Some(
            publication_error.unwrap_or("") +
            " Publication cleanup failed: " +
            error_message(error),
          )
      }
    }
  }
  { report, validated, committed, publication_error, cancelled, }
}

///|
pub fn ContentPublisher::memory(
  outputs : Map[String, @data.Content],
) -> ContentPublisher {
  {
    guarantee: AtomicTask,
    write_bytes: true,
    begin: fn(destinations) {
      let staged : Map[String, @data.Content] = Map([])
      {
        stage: fn(artifact) raise {
          let path = @workspace.normalize(artifact.path)
          if path != artifact.path ||
            !destinations.any(d => @workspace.within(d, path) && d != path) {
            raise @config.Invalid("Artifact outside publication")
          }
          if staged.contains(path) {
            raise @config.Invalid("Duplicate output path: " + path)
          }
          staged[path] = artifact.content
        },
        commit: fn(destination) raise {
          if !destinations.contains(destination) {
            raise @config.Invalid("Invalid publication destination")
          }
          for path in outputs.keys().collect() {
            if @workspace.within(destination, path) {
              outputs.remove(path)
            }
          }
          for path, value in staged {
            if @workspace.within(destination, path) {
              outputs[path] = value
            }
          }
        },
        abort: fn() { staged.clear() },
      }
    },
  }
}

///|
/// Explicit text adapter reports its byte limitation before reading sources.
pub fn ContentPublisher::text(publisher : Publisher) -> ContentPublisher {
  {
    guarantee: publisher.guarantee,
    write_bytes: false,
    begin: fn(destinations) raise {
      let transaction = (publisher.begin)(destinations)
      {
        stage: fn(artifact) raise {
          let content = match artifact.content {
            Text(text) => text
            Binary(_) =>
              raise @config.Invalid(
                "host.byte_write_required: Text publisher received binary content",
              )
          }
          (transaction.stage)({
            path: artifact.path,
            source: artifact.source,
            content,
          })
        },
        commit: transaction.commit,
        abort: transaction.abort,
      }
    },
  }
}

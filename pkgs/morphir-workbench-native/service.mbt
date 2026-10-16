///|
struct Record {
  identity : Json
  mut last_pid : Int32
  mut child : @process.Process?
  mut task : @async.Task[Unit]?
  mut stop : String
  mut exited : Bool
  mut done : Bool
  mut captured : Json?
  mut peak : Double
}

///|
pub struct Service {
  priv group : @async.TaskGroup[Unit]
  priv executable : String
  priv host : @jobs.Host
  priv offer : Json
  priv records : Map[String, Record]
  priv queue : Array[Record]
  priv deadline : Int32
  priv memory : Double
  priv mut active : Int32
  priv mut closed : Bool
  priv mut uncertain : Bool
}

///|
/// The embedding host supplies its own executable, never renderer input.
pub fn Service::new(
  group : @async.TaskGroup[Unit],
  executable : String,
  session : String,
  deadline~ : Int32 = 30000,
  memory~ : Double = 268435456.0,
) -> Service raise {
  guard supported() &&
    deadline > 0 &&
    deadline <= 30000 &&
    memory > 0.0 &&
    memory <= 268435456.0 else {
    raise Invalid("workbench.native_resources")
  }
  let offer : Json = {
    "profile": "morphir/workbench/jobs",
    "contractVersion": "0.1.0-draft.1",
    "hostId": "native-" + pid().to_string() + "-" + now().to_int64().to_string(),
    "sessionId": session,
    "providerId": "moonbit-scheme",
    "operations": ["query", "cancel"],
  }
  {
    group,
    executable,
    host: @jobs.Host::new(offer.stringify()),
    offer,
    records: Map([]),
    queue: [],
    deadline,
    memory,
    active: 0,
    closed: false,
    uncertain: false,
  }
}

///|
fn field(value : Json, name : String) -> Json raise {
  guard value is Object(fields) && fields.get(name) is Some(value) else {
    raise Invalid("workbench.native_shape")
  }
  value
}

///|
fn text(value : Json) -> String raise {
  guard value is String(value) else { raise Invalid("workbench.native_shape") }
  value
}

///|
fn Service::command(self : Service, command : Json) -> Json raise {
  let reply = self.host.handle(command.stringify())
  guard field(reply, "ok") == Json::boolean(true) else {
    raise Invalid(text(field(reply, "code")))
  }
  field(reply, "value")
}

///|
fn response(status : Int32, value : Json) -> Json {
  { "status": status, "source": value.stringify() }
}

///|
/// Business bodies stay raw until the shared duplicate-aware host decoder.
pub fn Service::request(self : Service, path : String, body : String?) -> Json {
  try {
    guard !self.uncertain else {
      raise Invalid("workbench.worker_unconfirmed_exit")
    }
    guard !self.closed else { raise Invalid("workbench.native_closed") }
    if path == "session" {
      guard body == None else { raise Invalid("workbench.native_shape") }
      return response(200, {
        "profile": "morphir/workbench/host",
        "contractVersion": "0.1.0-draft.1",
        "offer": self.offer,
      })
    }
    guard ["submit", "query", "cancel", "release"].contains(path) &&
      body is Some(body) else {
      raise Invalid("workbench.native_operation")
    }
    let value = self.command({ "op": path, "body": body })
    self.apply(path, body, value)
    response(200, value)
  } catch {
    error => {
      let code = match error {
        Invalid(code) => code
        _ => "workbench.native_failure"
      }
      let status = if [
          "workbench.host_capacity", "workbench.host_already_claimed", "workbench.host_not_terminal",
        ].contains(code) {
        409
      } else if [
          "workbench.host_unknown_job", "workbench.host_cancel_unavailable",
        ].contains(code) {
        404
      } else if code.contains("limit") || code.contains("budget") {
        413
      } else if code == "workbench.native_closed" ||
        code == "workbench.worker_unconfirmed_exit" {
        503
      } else {
        400
      }
      response(status, {
        "error": {
          "code": code,
          "message": if code == "workbench.worker_unconfirmed_exit" {
            "The native worker exit could not be confirmed. The job remains nonterminal."
          } else {
            "The native host rejected this job request."
          },
        },
      })
    }
  }
}

///|
fn failure(code : String) -> Json {
  {
    "stage": "evaluate",
    "code": code,
    "message": "The native worker did not complete evaluation.",
  }
}

///|
fn evidence(code : String, cancelled~ : Bool = false) -> Json {
  let outcome : Json = if cancelled {
    { "status": "cancelled" }
  } else {
    { "status": "failed", "failure": failure(code) }
  }
  {
    "contractVersion": "0.1.0-draft.5",
    "calls": [{ "id": "workbench", "outcome": outcome }],
    "cleanup": null,
    "extensions": null,
  }
}

///|
fn Record::stop(self : Record, reason : String) -> Unit {
  if self.stop == "" {
    self.stop = reason
  }
  if self.child is Some(child) {
    child.cancel()
  }
}

///|
fn Service::complete(self : Service, record : Record, outcomes : Json) -> Unit {
  try {
    // Bound the final business receipt, including identity/envelope overhead.
    let previous = self.command({
      "op": "query",
      "body": (
        { "contractVersion": "0.1.0-draft.1", "identity": record.identity } :
        Json).stringify(),
    })
    guard previous is Object(fields) else {
      raise Invalid("workbench.worker_outcomes")
    }
    fields["state"] = Json::string("terminal")
    fields["sequence"] = Json::number(2147483647)
    fields["outcomes"] = outcomes
    let bounded = try {
      ignore(@reply.success("job.query", Json::object(fields)))
      true
    } catch {
      _ => false
    }
    let outcomes = if !bounded {
      evidence("workbench.worker_output_limit")
    } else {
      outcomes
    }
    ignore(
      self.command({
        "op": "complete",
        "identity": record.identity,
        "outcomes": outcomes,
      }),
    )
    record.done = true
  } catch {
    _ =>
      try {
        ignore(
          self.command({
            "op": "complete",
            "identity": record.identity,
            "outcomes": evidence("workbench.worker_outcomes"),
          }),
        )
        record.done = true
      } catch {
        _ => self.uncertain = true
      }
  }
}

///|
fn Service::drain(self : Service) -> Unit {
  while !self.closed &&
        !self.uncertain &&
        self.active < 2 &&
        !self.queue.is_empty() {
    let record = self.queue.remove(0)
    if record.done {
      continue
    }
    self.active += 1
    record.task = Some(self.group.spawn(async fn() { self.run(record) }))
  }
}

///|
async fn Service::run(self : Service, record : Record) -> Unit {
  if record.stop != "" {
    self.complete(record, evidence("", cancelled=true))
    self.active -= 1
    self.drain()
    return
  }
  let mut code = -1
  try {
    let request = self.command({ "op": "claim", "identity": record.identity })
    let input = frame(request.stringify())
    @async.with_task_group(async fn(group) {
      let (stdin, writer) = @process.write_to_process()
      defer writer.close()
      let (reader, stdout) = @process.read_from_process()
      defer reader.close()
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let child = @process.spawn(
        group,
        self.executable,
        ["--morphir-native-worker"],
        stdin~,
        stdout~,
        stderr~,
        inherit_env=false,
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
      record.child = Some(child)
      record.last_pid = child.pid
      if record.stop != "" {
        child.cancel()
      }
      let started = now()
      group.spawn_bg(no_wait=true, async fn() {
        try {
          writer.write(input)
          writer.close()
        } catch {
          _ => record.stop("workbench.worker_input")
        }
      })
      let output = group.spawn(async fn() {
        try {
          let n = frame_length(reader.read_exactly(4))
          let source = @utf8.decode(reader.read_exactly(n))
          let value = @jobs.decode(source)
          // Typed and structural evidence admission precedes result capture.
          ignore(@protocol.Outcomes::from_json(value))
          record.captured = Some(value)
          if reader.read_some(max_len=1) != None {
            record.stop("workbench.worker_trailing_output")
          }
        } catch {
          _ => record.stop("workbench.worker_frame")
        }
      })
      let error_output = group.spawn(async fn() {
        try {
          let mut total = 0
          while errors.read_some(max_len=4096) is Some(chunk) {
            total += chunk.length()
            if total > 65536 {
              record.stop("workbench.worker_stderr_limit")
              break
            }
          }
        } catch {
          _ => record.stop("workbench.worker_stderr")
        }
      })
      group.spawn_bg(no_wait=true, async fn() {
        let mut missing_samples = 0
        while !record.exited {
          if now() < started {
            record.stop("workbench.worker_measurement")
          }
          if now() - started >= self.deadline.to_double() {
            record.stop("workbench.worker_deadline")
          }
          let resident = rss(child.pid)
          if resident > record.peak {
            record.peak = resident
          }
          if resident > self.memory {
            record.stop("workbench.worker_memory")
          }
          // OS process removal can precede the async exit notification. Give
          // that notification time to arrive before reporting missing metrics.
          missing_samples = if resident < 0.0 { missing_samples + 1 } else { 0 }
          if missing_samples >= 3 && child.try_wait() == None {
            record.stop("workbench.worker_measurement")
          }
          @async.sleep(20)
        }
      })
      code = child.wait()
      record.exited = true
      output.wait()
      error_output.wait()
    })
  } catch {
    _ => {
      if record.child is Some(_) && !record.exited {
        self.uncertain = true
      }
      if record.stop == "" {
        record.stop = "workbench.worker_start"
      }
    }
  }
  if record.child is None || record.exited {
    let outcomes = match record.captured {
      Some(Object(fields)) => {
        if (code != 0 && record.stop == "") ||
          (
            record.stop != "" &&
            record.stop != "cancel" &&
            record.stop != "shutdown"
          ) {
          fields["cleanup"] = {
            "stage": "cleanup",
            "code": "workbench.worker_cleanup",
            "message": "The native worker failed during cleanup.",
          }
        }
        Json::object(fields)
      }
      _ =>
        if record.stop == "cancel" || record.stop == "shutdown" {
          evidence("", cancelled=true)
        } else {
          evidence(
            if record.stop != "" {
              record.stop
            } else {
              "workbench.worker_crash"
            },
          )
        }
    }
    self.complete(record, outcomes)
    record.captured = None
    record.child = None
    self.active -= 1
    self.drain()
  }
}

///|
pub fn Service::close(self : Service) -> Unit {
  self.closed = true
  for record in self.records.values() {
    if !record.done {
      record.stop("shutdown")
      if record.task is None {
        self.complete(record, evidence("", cancelled=true))
      }
    }
  }
  self.queue.clear()
}

///|
pub async fn Service::shutdown(self : Service) -> Unit {
  self.close()
  @async.protect_from_cancel(async fn() {
    for record in self.records.values() {
      if record.task is Some(task) {
        task.wait()
      }
    }
  })
  guard !self.uncertain && self.active == 0 else {
    raise Invalid("workbench.worker_unconfirmed_exit")
  }
}

///|
pub fn Service::stats(self : Service) -> Json {
  let mut peak = 0.0
  let mut captured = 0
  let mut completed = 0
  let children : Array[Json] = []
  for record in self.records.values() {
    if record.last_pid > 0 {
      children.push({
        "pid": record.last_pid,
        "exited": record.exited,
        "residentBytes": rss(record.last_pid),
      })
    }
    if record.captured is Some(_) {
      captured += 1
    }
    if record.done {
      completed += 1
    }
    if record.peak > peak {
      peak = record.peak
    }
  }
  {
    "active": self.active,
    "retained": self.records.length(),
    "closed": self.closed,
    "uncertain": self.uncertain,
    "peakResidentBytes": peak,
    "captured": captured,
    "completed": completed,
    "children": children,
    "queued": self.queue.length(),
  }
}

///|
fn Service::apply(
  self : Service,
  path : String,
  body : String,
  value : Json,
) -> Unit raise {
  if path == "submit" {
    let identity = field(value, "identity")
    let record : Record = {
      identity,
      last_pid: 0,
      child: None,
      task: None,
      stop: "",
      exited: false,
      done: false,
      captured: None,
      peak: 0.0,
    }
    self.records[text(field(identity, "jobId"))] = record
    self.queue.push(record)
    self.drain()
  } else if path == "cancel" {
    if self.records.get(text(field(field(value, "identity"), "jobId")))
      is Some(record) &&
      !record.done {
      record.stop("cancel")
      if record.task is None {
        self.complete(record, evidence("", cancelled=true))
        let mut index = 0
        while index < self.queue.length() {
          if self.queue[index].done {
            ignore(self.queue.remove(index))
          } else {
            index += 1
          }
        }
      }
    }
  } else if path == "release" {
    let identity = field(@jobs.decode(body), "identity")
    self.records.remove(text(field(identity, "jobId")))
  }
}

///|
/// A fresh view of the actual service authority, stable for its lifetime.
pub fn Service::offer(self : Service) -> Json {
  @jobs.decode(self.offer.stringify()) catch {
    _ => abort("Native service offer")
  }
}

///|
fn native_code(code : String) -> @reply.Code {
  if [
      "workbench.host_capacity", "workbench.host_already_claimed", "workbench.host_not_terminal",
    ].contains(code) {
    @reply.Conflict
  } else if ["workbench.host_unknown_job", "workbench.host_cancel_unavailable"].contains(
      code,
    ) {
    @reply.NotFound
  } else if code.contains("limit") || code.contains("budget") {
    @reply.Limit
  } else {
    @reply.InvalidRequest
  }
}

///|
/// Only the owner's explicit rejected command proves no effect. After owner
/// acceptance, scheduling, cancellation and reply publication may have occurred.
pub fn Service::native_request(
  self : Service,
  operation : String,
  payload : Json,
) -> Bytes {
  if self.closed || self.uncertain {
    return @reply.failure(@reply.Unavailable, @reply.NoEffect)
  }
  let path = match operation {
    "job.submit" => "submit"
    "job.query" => "query"
    "job.cancel" => "cancel"
    "job.release" => "release"
    _ => return @reply.failure(@reply.InvalidRequest, @reply.NoEffect)
  }
  try {
    let body = payload.stringify()
    let result = self.host.handle(
      ({ "op": path, "body": body } : Json).stringify(),
    )
    if field(result, "ok") == Json::boolean(false) {
      // The shared owner validates and constructs receipts before mutating its
      // state. A returned rejection is the explicit pre-commit branch.
      return @reply.failure(
        native_code(text(field(result, "code"))),
        @reply.NoEffect,
      )
    }
    guard field(result, "ok") == Json::boolean(true) else {
      raise Invalid("workbench.native_shape")
    }
    let value = field(result, "value")
    self.apply(path, body, value)
    @reply.success(operation, value)
  } catch {
    _ => @reply.failure(@reply.Unavailable, @reply.UnknownEffect)
  }
}

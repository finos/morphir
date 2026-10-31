///|
/// The guest end of a message port: it reports numbered events and the
/// guest's exit to the host.
priv struct GuestEnd {
  target : PortTarget
  mut sequence : Int32
}

///|
fn GuestEnd::post(self : GuestEnd, event : @guest.WorkerEvent) -> Unit {
  self.sequence += 1
  self.target.post_event(event.to_json(sequence=self.sequence).stringify())
}

///|
fn GuestEnd::finish(self : GuestEnd, code : Int32) -> Unit {
  self.post(Exited(code~))
  self.target.exit(code)
}

///|
fn optional(value : Int32) -> Int32? {
  if value > 0 {
    Some(value)
  } else {
    None
  }
}

///|
/// The event and exit status of a module that did not load, as in the Node
/// worker-thread entry.
fn load_failure(error : @worker.LaunchError) -> (@guest.WorkerEvent, Int32) {
  match error {
    AbiUnsupported(name) =>
      (Refused(code=AbiUnsupported, message="the module imports \{name}"), 3)
    ExportMissing(name~, signature~) =>
      (
        Refused(
          code=AbiUnsupported,
          message="the module does not export \{name} as \{signature}",
        ),
        3,
      )
    MemoryAboveCeiling(initial~, ceiling~) =>
      (
        Fault(
          MemoryLimit(
            "the module's initial memory of \{initial} pages is above the ceiling of \{ceiling} pages",
          ),
        ),
        1,
      )
    AbiMismatch(declared~, classified~) =>
      (
        Refused(
          code=AbiMismatch,
          message="the Web Worker was started for \{declared}; the module is \{classified}",
        ),
        3,
      )
    WasmFeatureUnsupported(feature~) =>
      (
        Refused(
          code=WasmFeatureUnsupported,
          message="the module needs \{feature.unwrap_or("a WASM feature")} that the engine does not have",
        ),
        3,
      )
    error =>
      (Fault(Failure("the guest did not load: \{@debug.to_string(error)}")), 1)
  }
}

///|
/// Loads the guest of a start message and reports that it started, or
/// reports why it did not load and exits.
fn GuestEnd::load(self : GuestEnd, data : StartData) -> &@guest.Guest? {
  let abi = @worker.WasmAbi::parse(data.abi()) catch {
    _ => {
      self.post(Fault(Failure("the host gave an unknown ABI profile")))
      self.finish(1)
      return None
    }
  }
  let host = @worker.Limits::host()
  let limits = @worker.Limits::new(
    request_bytes=optional(data.number("requestBytes")).unwrap_or(
      host.request_bytes,
    ),
    response_bytes=optional(data.number("responseBytes")).unwrap_or(
      host.response_bytes,
    ),
    model=host.model,
  ) catch {
    _ => host
  }
  let call = optional(data.number("callMs")).map(deadline_ms => {
    @guest.CallBounds::new(deadline_ms~, instructions=None)
  })
  // A browser guest has no file system, so its workspace has no root.
  let services = @guest.GuestServices::new(workspace_root="", output=item => {
    self.post(Output(item))
  })
  let bytes = data.module_bytes()
  let guest = @guest.load(
    bytes,
    declared=abi,
    call?,
    limits~,
    ceiling=@wasm.MemoryCeiling::restricted(),
    services~,
  ) catch {
    error => {
      let (event, code) = load_failure(error)
      self.post(event)
      self.finish(code)
      return None
    }
  }
  self.post(
    Started(
      abi~,
      module_sha256=@worker.Sha256::of(bytes),
      build_identity="",
      bounds=@guest.engine_bounds(),
    ),
  )
  Some(guest)
}

///|
/// Serves one guest on `target`: loads the module of the start message,
/// then answers each MEP message until `exit`.
fn serve(target : PortTarget) -> Unit {
  let end = { target, sequence: 0, }
  let mut guest : &@guest.Guest? = None
  target.serve(data => if guest is None { guest = end.load(data) }, message => {
    guard guest is Some(loaded) else { return }
    try loaded.exchange(message) catch {
      Faulted(fault) => {
        end.post(Fault(fault))
        end.finish(1)
      }
    } noraise {
      Response(response) => end.target.post_response(response)
      Notified => ()
      Exit => end.finish(0)
    }
  })
}

///|
/// Serves one guest in the Web Worker that runs this code. The entry module
/// of `worker/browser/entry` calls it.
pub fn serve_worker_scope() -> Unit {
  serve(worker_scope())
}

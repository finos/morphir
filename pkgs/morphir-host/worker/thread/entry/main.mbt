///|
/// What the host gives a thread when it starts it.
#external
priv type WorkerData

///|
extern "js" fn worker_data() -> WorkerData =
  #| () => process.getBuiltinModule('node:worker_threads').workerData

///|
extern "js" fn WorkerData::abi(self : WorkerData) -> String =
  #| (data) => data.abi

///|
extern "js" fn WorkerData::module_bytes(self : WorkerData) -> Bytes =
  #| (data) => data.module

///|
/// A text of the data, or "" when it is not set.
extern "js" fn WorkerData::text(self : WorkerData, name : String) -> String =
  #| (data, name) => typeof data[name] === 'string' ? data[name] : ''

///|
/// A number of the data, or 0 when it is not set.
extern "js" fn WorkerData::number(self : WorkerData, name : String) -> Int32 =
  #| (data, name) => Number.isInteger(data[name]) ? data[name] : 0

///|
/// Sends one report event, as `morphir/command-event` JSON text.
extern "js" fn post_event(text : String) -> Unit =
  #| (text) => process.getBuiltinModule('node:worker_threads').parentPort.postMessage({kind: 'event', text})

///|
/// Sends one response.
extern "js" fn post_response(bytes : Bytes) -> Unit =
  #| (bytes) => process.getBuiltinModule('node:worker_threads').parentPort.postMessage({kind: 'response', bytes})

///|
/// Calls `handle` with the bytes of each message from the host.
extern "js" fn on_message(handle : (Bytes) -> Unit) -> Unit =
  #| (handle) => process.getBuiltinModule('node:worker_threads').parentPort.on('message', (bytes) => handle(bytes))

///|
/// Ends the thread with a status, after the events it posted.
extern "js" fn exit_thread(code : Int32) -> Unit =
  #| (code) => process.exit(code)

///|
priv struct Thread {
  mut sequence : Int32
}

///|
fn Thread::post(self : Thread, event : @guest.WorkerEvent) -> Unit {
  self.sequence += 1
  post_event(event.to_json(sequence=self.sequence).stringify())
}

///|
fn Thread::finish(self : Thread, code : Int32) -> Unit {
  self.post(Exited(code~))
  exit_thread(code)
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
fn main {
  let thread = { sequence: 0, }
  let data = worker_data()
  let abi = @worker.WasmAbi::parse(data.abi()) catch {
    _ => {
      thread.post(Fault(Failure("the host gave an unknown ABI profile")))
      thread.finish(1)
      return
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
  let ceiling = match optional(data.number("memoryPages")) {
    Some(pages) =>
      @wasm.MemoryCeiling::of_pages(pages) catch {
        _ => @wasm.MemoryCeiling::restricted()
      }
    None => @wasm.MemoryCeiling::restricted()
  }
  // The host made the workspace: a private, empty directory for this guest,
  // which it removes when the thread has stopped.
  let workspace_root = data.text("workspaceRoot")
  let services = @guest.GuestServices::new(workspace_root~, output=item => {
    thread.post(Output(item))
  })
  let bytes = data.module_bytes()
  let guest = @guest.load(
    bytes,
    declared=abi,
    call?,
    limits~,
    ceiling~,
    services~,
  ) catch {
    AbiUnsupported(name) => {
      thread.post(
        Refused(code=AbiUnsupported, message="the module imports \{name}"),
      )
      thread.finish(3)
      return
    }
    ExportMissing(name~, signature~) => {
      thread.post(
        Refused(
          code=AbiUnsupported,
          message="the module does not export \{name} as \{signature}",
        ),
      )
      thread.finish(3)
      return
    }
    MemoryAboveCeiling(initial~, ceiling~) => {
      thread.post(
        Fault(
          MemoryLimit(
            "the module's initial memory of \{initial} pages is above the ceiling of \{ceiling} pages",
          ),
        ),
      )
      thread.finish(1)
      return
    }
    AbiMismatch(declared~, classified~) => {
      thread.post(
        Refused(
          code=AbiMismatch,
          message="the thread was started for \{declared}; the module is \{classified}",
        ),
      )
      thread.finish(3)
      return
    }
    WasmFeatureUnsupported(feature~) => {
      thread.post(
        Refused(
          code=WasmFeatureUnsupported,
          message="the module needs \{feature.unwrap_or("a WASM feature")} that the engine does not have",
        ),
      )
      thread.finish(3)
      return
    }
    error => {
      thread.post(
        Fault(Failure("the guest did not load: \{@debug.to_string(error)}")),
      )
      thread.finish(1)
      return
    }
  }
  thread.post(
    Started(
      abi~,
      module_sha256=@worker.Sha256::of(bytes),
      build_identity="",
      bounds=@guest.engine_bounds(),
    ),
  )
  on_message(message => {
    try guest.exchange(message) catch {
      Faulted(fault) => {
        thread.post(Fault(fault))
        thread.finish(1)
      }
    } noraise {
      Response(response) => post_response(response)
      Notified => ()
      Exit => thread.finish(0)
    }
  })
}

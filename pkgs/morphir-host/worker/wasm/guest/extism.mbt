///|
/// The most bytes of IR that one session's cache holds, keys and values.
const IR_CACHE_BYTES : Int32 = 16777216

///|
/// The most entries that one session's IR cache holds.
const IR_CACHE_ENTRIES : Int32 = 1024

///|
/// The most bytes of Extism variables that one session holds.
const VARIABLE_BYTES : Int32 = 1048576

///|
/// An `extism-kernel-v1` guest: one plugin instance for the session. Each
/// request is one `handle` call with the request bytes as input, and the
/// response is the kernel output. Notifications are not delivered; `exit`
/// ends the instance. The host functions follow the WASM-4 policy.
pub struct ExtismGuest {
  priv plugin : @extism.Plugin
  priv handle : @extism.ExportName
  priv output : (GuestOutput) -> Unit
  priv request_limit : Int32
  priv mut state : State
}

///|
fn ExtismGuest::fail(
  self : ExtismGuest,
  fault : @worker.GuestFault,
) -> GuestError {
  self.state = Failed
  Faulted(fault)
}

///|
fn log_level(level : @extism.LogLevel) -> LogLevel {
  match level {
    Trace => Trace
    Debug => Debug
    Info => Info
    Warn => Warn
    Error => Error
  }
}

///|
fn host_error(name : String, text : String) -> @engine.HostError {
  HostError("\{name}: \{text}")
}

///|
fn read_text(
  context : @extism.CallContext,
  name : String,
  offset : Int64,
) -> String raise @engine.HostError {
  let bytes = context.read(@extism.Handle::parse(offset)) catch {
    _ => raise host_error(name, "no block at \{offset}")
  }
  @utf8.decode(bytes) catch {
    _ => raise host_error(name, "the text is not valid UTF-8")
  }
}

///|
fn allocate(
  context : @extism.CallContext,
  name : String,
  bytes : Bytes,
) -> Array[@engine.Value] raise @engine.HostError {
  let handle = context.allocate(bytes[:]) catch {
    _ =>
      raise host_error(
        name,
        "the kernel has no room for \{bytes.length()} bytes",
      )
  }
  [I64(handle.offset())]
}

///|
/// A store into the IR cache that would go over one of its limits.
priv suberror CacheLimit {
  CacheLimit(String)
} derive(Debug)

///|
/// The IR cache of one session, bounded by its bytes (the UTF-8 bytes of
/// the keys and the bytes of the values) and by its number of entries.
priv struct IrCache {
  values : Map[String, Bytes]
  byte_limit : Int32
  entry_limit : Int32
  mut bytes : Int32
}

///|
fn IrCache::new(bytes~ : Int32, entries~ : Int32) -> IrCache {
  { values: Map([]), byte_limit: bytes, entry_limit: entries, bytes: 0, }
}

///|
fn IrCache::size(key : String, value : Bytes) -> Int32 {
  @utf8.encode(key).length() + value.length()
}

///|
/// Stores `value` under `key`, or refuses a store that would hold more than
/// the byte limit or the entry limit. A refused store changes nothing.
fn IrCache::store(
  self : IrCache,
  key : String,
  value : Bytes,
) -> Unit raise CacheLimit {
  let previous = match self.values.get(key) {
    Some(old) => IrCache::size(key, old)
    None => {
      guard self.values.length() < self.entry_limit else {
        raise CacheLimit("the IR cache has \{self.entry_limit} entries")
      }
      0
    }
  }
  let bytes = self.bytes - previous + IrCache::size(key, value)
  guard bytes <= self.byte_limit else {
    raise CacheLimit("the IR cache is over \{self.byte_limit} bytes")
  }
  self.bytes = bytes
  self.values[key] = value
}

///|
fn IrCache::get(self : IrCache, key : String) -> Bytes? {
  self.values.get(key)
}

///|
/// The four Morphir host functions in `extism:host/user`, as for restricted
/// generation in the Rust host: the workspace is an empty private directory,
/// the IR cache lives only for the session and `morphir_log` becomes output.
fn morphir_functions(
  services : GuestServices,
) -> Array[@extism.HostFunction] raise @extism.NameError {
  let user = @extism.Namespace::parse(@wasm.extism_user_namespace)
  let cache = IrCache::new(bytes=IR_CACHE_BYTES, entries=IR_CACHE_ENTRIES)
  let function = (name, params, results, body) => {
    @extism.HostFunction::new(
      user,
      @extism.FunctionName::parse(name),
      @engine.Signature::new(params, results),
      body,
    )
  }
  [
    function("morphir_get_workspace_info", [], [I64], (context, _) => {
      let info : Json = { "root": services.workspace_root, "output_dir": "" }
      allocate(
        context,
        "morphir_get_workspace_info",
        @utf8.encode(info.stringify()),
      )
    }),
    function("morphir_cache_ir", [I64, I64], [], (context, args) => {
      let name = "morphir_cache_ir"
      guard args is [I64(key), I64(ir)] else {
        raise host_error(name, "bad arguments")
      }
      let key = read_text(context, name, key)
      let value = context.read(@extism.Handle::parse(ir)) catch {
        _ => raise host_error(name, "no block at \{ir}")
      }
      cache.store(key, value) catch {
        CacheLimit(text) => raise host_error(name, text)
      }
      []
    }),
    function("morphir_get_cached_ir", [I64], [I64], (context, args) => {
      let name = "morphir_get_cached_ir"
      guard args is [I64(key)] else { raise host_error(name, "bad arguments") }
      let key = read_text(context, name, key)
      allocate(context, name, cache.get(key).unwrap_or(b"null"))
    }),
    function("morphir_log", [I64, I64], [], (context, args) => {
      let name = "morphir_log"
      guard args is [I64(level), I64(message)] else {
        raise host_error(name, "bad arguments")
      }
      (services.output)(
        MorphirLog(
          level=read_text(context, name, level),
          read_text(context, name, message),
        ),
      )
      []
    }),
  ]
}

///|
/// The random bytes of one `random_get`: `count` bytes from `source`, or no
/// bytes, which the sandbox answers with an error code, for a count that is
/// negative or above the memory ceiling. The source does not run then.
fn random_bytes(
  count : Int32,
  ceiling : @wasm.MemoryCeiling,
  source : (Int32) -> Bytes,
) -> Bytes {
  guard count >= 0 &&
    count.to_int64() <= ceiling.pages().to_int64() * @wasm.PAGE_BYTES.to_int64() else {
    return b""
  }
  source(count)
}

///|
/// A monotonic clock over a source of milliseconds that may move backwards,
/// as a wall clock does: the time since the start never gets smaller.
priv struct MonotonicClock {
  source : () -> UInt64
  started : UInt64
  mut last : UInt64
}

///|
fn MonotonicClock::new(source : () -> UInt64) -> MonotonicClock {
  { source, started: source(), last: 0UL, }
}

///|
/// The milliseconds since the start. A reading below the last one gives the
/// last one, so no subtraction underflows.
fn MonotonicClock::elapsed_ms(self : MonotonicClock) -> UInt64 {
  let now = (self.source)()
  if now >= self.started && now - self.started > self.last {
    self.last = now - self.started
  }
  self.last
}

///|
/// The WASI preview 1 sandbox of WASM-4: no preopens, empty arguments,
/// environment and stdin, the host's clocks and random bytes, and stdout and
/// stderr as output. `random_get` gives at most the memory ceiling.
fn sandbox(
  services : GuestServices,
  ceiling : @wasm.MemoryCeiling,
) -> @wasi.Sandbox {
  let random = @random.Rand()
  let monotonic = MonotonicClock::new(() => @env.now())
  let nanoseconds = (milliseconds : UInt64) => milliseconds * 1000000UL
  @wasi.Sandbox::new()
  .clock({
    time: id => {
      match id {
        Realtime => nanoseconds(@env.now())
        _ => nanoseconds(monotonic.elapsed_ms())
      }
    },
    resolution: _ => nanoseconds(1UL),
  })
  .random(count => {
    random_bytes(count, ceiling, count => {
      Bytes::makei(count, _ => {
        random.uint(limit=256).reinterpret_as_int().to_byte()
      })
    })
  })
  .stdout(bytes => (services.output)(Stdout(bytes.to_owned())))
  .stderr(bytes => (services.output)(Stderr(bytes.to_owned())))
}

///|
fn ExtismGuest::load(
  prepared : @wasm.PreparedModule,
  call~ : CallBounds,
  limits~ : @worker.Limits,
  ceiling~ : @wasm.MemoryCeiling,
  services~ : GuestServices,
) -> ExtismGuest raise @worker.LaunchError {
  let (budget, deadline) = call.engine()
  try {
    let pages = @engine.PageCount::parse(ceiling.pages())
    let plugin_limits = @extism.Limits::default()
      .plugin_memory(pages)
      .deadline(deadline)
    let plugin_limits = match budget {
      Some(budget) => plugin_limits.budget(budget)
      None => plugin_limits
    }
    let policy = @extism.Policy::default()
      .config(Empty)
      .variables(Session(@extism.ByteLimit::parse(VARIABLE_BYTES.to_int64())))
      .logging(
        Sink(Info, (level, text) => {
          (services.output)(Log(log_level(level), text))
        }),
      )
      .http(Deny)
    let mut manifest = @extism.Manifest::new(prepared.module_.bytes())
      .limits(plugin_limits)
      .policy(policy)
      .wasi(sandbox(services, ceiling))
    for function in morphir_functions(services) {
      manifest = manifest.register(function)
    }
    let plugin = @extism.Plugin::load(manifest)
    {
      plugin,
      handle: @extism.ExportName::parse(@wasm.handle_export),
      output: services.output,
      request_limit: limits.request_bytes,
      state: Ready,
    }
  } catch {
    @extism.UnlinkedImport(module_name, name)
    | @extism.WrongSignature(module_name, name) =>
      raise AbiUnsupported(@worker.ImportName::new(module_name, name))
    @extism.LoadError::Engine(FeatureUnsupported(feature)) =>
      raise WasmFeatureUnsupported(feature=Some(feature.name()))
    error =>
      raise LaunchFailed("the guest did not load: \{@debug.to_string(error)}")
  }
}

///|
/// The guest fault for a plugin call error.
fn ExtismGuest::call_fault(
  self : ExtismGuest,
  error : @extism.CallError,
) -> @worker.GuestFault {
  match error {
    Plugin(code, text) =>
      Failure("the guest set an error (\{code}): \{cut_message(text)}")
    Exit(code) => Failure("the guest exited with code \{code} during a call")
    Denied({ function, method_, url, }) => {
      if function == "http_request" {
        (self.output)(
          RefusedHttp(verb=method_.unwrap_or("GET"), url=url.unwrap_or("")),
        )
      }
      Failure("\{function} was refused: the guest has no network access")
    }
    HostFunction(name, text) => Failure("host function \{name} failed: \{text}")
    MemoryLimit(kind) =>
      MemoryLimit("\{@debug.to_string(kind)} reached its ceiling")
    Limit(name) => Failure("the guest reached the limit \{name}")
    Engine(error) | Initialization(error) => call_fault(error)
    UnknownExport(name) => Failure("the module exports no function \{name}")
  }
}

///|
/// Whether a message is a notification, and whether it is `exit`.
fn notification(request : Bytes) -> (Bool, Bool) raise @json.ParseError {
  guard @json.parse(@utf8.decode_lossy(request)) is Object(fields) else {
    return (false, false)
  }
  if fields.contains("id") {
    return (false, false)
  }
  (true, fields.get("method") is Some(String("morphir.exit")))
}

///|
pub extend ExtismGuest with Guest::{exchange}

///|
/// Calls `handle` once for a request, with the request as input, and returns
/// the kernel output. A notification is not delivered; `exit` ends the
/// instance.
pub impl Guest for ExtismGuest with fn exchange(self, request) {
  match self.state {
    Ready => ()
    Exited => raise Faulted(Failure("the guest has exited"))
    Failed => raise Faulted(Failure("the guest failed before"))
  }
  guard request.length() <= self.request_limit else {
    raise self.fail(Failure("the request is over \{self.request_limit} bytes"))
  }
  guard valid_utf8(request) else {
    raise self.fail(Failure("the request is not valid UTF-8"))
  }
  let (is_notification, is_exit) = notification(request) catch {
    _ => raise self.fail(Failure("the message is not JSON"))
  }
  if is_exit {
    self.state = Exited
    return Exit
  }
  if is_notification {
    return Notified
  }
  let response = self.plugin.call(self.handle, request[:]) catch {
    error => raise self.fail(self.call_fault(error))
  }
  guard response.length() > 0 else {
    raise self.fail(Failure("the guest gave no response to a request"))
  }
  guard valid_utf8(response) else {
    raise self.fail(Failure("the response is not valid UTF-8"))
  }
  Response(response)
}

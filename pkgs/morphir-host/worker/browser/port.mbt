///|
/// The absolute URL of the Web Worker entry module that
/// `worker/browser/entry` builds.
pub struct EntryUrl {
  priv href : String
} derive(Eq)

///|
pub extend EntryUrl with Eq::{equal, not_equal}

///|
/// The normalized URL, or "" when `text` is not an absolute URL.
extern "js" fn absolute_url(text : String) -> String =
  #| (text) => { try { return new URL(text).href; } catch { return ''; } }

///|
/// Refuses a relative URL: a Web Worker resolves one against the page, which
/// the launcher does not know.
pub fn EntryUrl::parse(text : String) -> EntryUrl raise @worker.LaunchError {
  let href = absolute_url(text)
  guard href != "" else {
    raise LaunchFailed(
      "the Web Worker entry module URL is not an absolute URL: \{text}",
    )
  }
  { href, }
}

///|
pub impl Show for EntryUrl with fn output(self, logger) {
  logger.write_string(self.href)
}

///|
pub extend EntryUrl with Show::{to_string, output}

///|
/// One end of a message port: a Web Worker or its global scope, or a
/// `MessagePort` in the tests. Each has `postMessage`, `onmessage` and either
/// `terminate` or `close`.
#external
priv type PortTarget

///|
/// Starts the entry module in a new Web Worker, or gives `null` with the
/// reason in `error[0]`.
extern "js" fn start_web_worker(
  entry : String,
  error : FixedArray[String],
) -> PortTarget =
  #| (entry, error) => {
  #|   try { return new Worker(entry, {name: 'morphir-wasm-guest'}); }
  #|   catch (cause) { error[0] = cause?.message ?? String(cause); return null; }
  #| }

///|
/// The host end of a message port and the events that the host waits for.
#external
priv type HostPort

///|
/// Listens on `target`. `on_event` receives each event of the worker: kind 0
/// a response, 1 a report event as JSON text, 2 the guest's exit with its
/// code as text, 3 an error of the worker with its message.
extern "js" fn HostPort::over(
  target : PortTarget,
  on_event : (Int32, Bytes, String) -> Unit,
) -> HostPort =
  #| (target, onEvent) => {
  #|   const none = new Uint8Array(0);
  #|   const port = {target, done: false};
  #|   target.onmessage = ({data}) => {
  #|     if (port.done) return;
  #|     if (data?.kind === 'response' && data.bytes instanceof Uint8Array) onEvent(0, data.bytes, '');
  #|     else if (data?.kind === 'event' && typeof data.text === 'string') onEvent(1, none, data.text);
  #|     else if (data?.kind === 'exit' && Number.isInteger(data.code)) {
  #|       port.done = true; onEvent(2, none, String(data.code));
  #|     }
  #|   };
  #|   target.onmessageerror = () => { if (!port.done) onEvent(3, none, 'a message of the worker could not be read'); };
  #|   target.onerror = (event) => {
  #|     event?.preventDefault?.();
  #|     if (!port.done) onEvent(3, none, event?.message || 'the Web Worker failed to load or run its entry module');
  #|   };
  #|   return port;
  #| }

///|
/// Gives the guest its module and limits. These are the launcher's options,
/// not MEP messages.
extern "js" fn HostPort::start(
  self : HostPort,
  abi : String,
  module_ : Bytes,
  request_bytes : Int32,
  response_bytes : Int32,
  call_ms : Int32,
) -> Unit =
  #| (port, abi, module, requestBytes, responseBytes, callMs) => {
  #|   port.target.postMessage({kind: 'start', abi, module, requestBytes, responseBytes, callMs});
  #| }

///|
/// Sends one whole MEP message.
extern "js" fn HostPort::post(self : HostPort, bytes : Bytes) -> Unit =
  #| (port, bytes) => { if (!port.done) port.target.postMessage({kind: 'message', bytes}); }

///|
/// Terminates the Web Worker at once. A Web Worker has no exit event, so
/// the termination is final when this returns.
extern "js" fn HostPort::terminate(self : HostPort) -> Unit =
  #| (port) => {
  #|   if (port.done) return;
  #|   port.done = true;
  #|   if (typeof port.target.terminate === 'function') port.target.terminate();
  #|   else port.target.close();
  #| }

///|
/// The global scope of the Web Worker that runs this code.
extern "js" fn worker_scope() -> PortTarget =
  #| () => globalThis

///|
/// What the host gives a guest when it starts it.
#external
priv type StartData

///|
extern "js" fn StartData::abi(self : StartData) -> String =
  #| (data) => typeof data.abi === 'string' ? data.abi : ''

///|
extern "js" fn StartData::module_bytes(self : StartData) -> Bytes =
  #| (data) => data.module instanceof Uint8Array ? data.module : new Uint8Array(0)

///|
/// A number of the data, or 0 when it is not set.
extern "js" fn StartData::number(self : StartData, name : String) -> Int32 =
  #| (data, name) => Number.isInteger(data[name]) ? data[name] : 0

///|
/// Calls `start` with the start message and `handle` with the bytes of each
/// MEP message from the host.
extern "js" fn PortTarget::serve(
  self : PortTarget,
  start : (StartData) -> Unit,
  handle : (Bytes) -> Unit,
) -> Unit =
  #| (target, start, handle) => {
  #|   target.onmessage = ({data}) => {
  #|     if (target.__morphirExited) return;
  #|     if (data?.kind === 'start') start(data);
  #|     else if (data?.kind === 'message' && data.bytes instanceof Uint8Array) handle(data.bytes);
  #|   };
  #| }

///|
extern "js" fn PortTarget::post_event(self : PortTarget, text : String) -> Unit =
  #| (target, text) => target.postMessage({kind: 'event', text})

///|
extern "js" fn PortTarget::post_response(
  self : PortTarget,
  bytes : Bytes,
) -> Unit =
  #| (target, bytes) => target.postMessage({kind: 'response', bytes})

///|
/// Reports the guest's exit to the host and closes this end. A Web Worker
/// stops after the messages that it posted.
extern "js" fn PortTarget::exit(self : PortTarget, code : Int32) -> Unit =
  #| (target, code) => { target.__morphirExited = true; target.postMessage({kind: 'exit', code}); target.close(); }

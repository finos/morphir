///|
/// A Node child process and the events that the host waits for. The JS object
/// records the exit status when the `exit` event arrives.
#external
priv type Child

///|
/// Starts `program` in a new process group (`detached: true`) with three
/// pipes, a hidden window on Windows, the given working directory and an
/// environment that holds only `SystemRoot` on Windows and nothing elsewhere.
/// On Windows libuv adds the variables that the README lists.
/// The promise resolves on the `spawn` event and rejects on a start failure.
/// Every stderr chunk goes to `on_stderr` as it arrives.
///
/// Each pipe has an `error` listener, so a pipe fault cannot crash the host;
/// the first fault is kept for the channel. On Unix the `exit` listener
/// signals the worker's group in the same tick as the reap: while a member
/// remains, its group ID cannot be reused. After that the host never signals
/// the group again.
extern "js" fn Child::spawn(
  program : String,
  args : FixedArray[String],
  cwd : String,
  on_stderr : (Bytes) -> Unit,
) -> @js_async.Promise[Child] =
  #| (program, args, cwd, onStderr) => new Promise((resolve, reject) => {
  #|   const {spawn} = process.getBuiltinModule('node:child_process');
  #|   const env = process.platform === 'win32' && process.env.SystemRoot ? {SystemRoot: process.env.SystemRoot} : {};
  #|   let child;
  #|   try {
  #|     child = spawn(program, Array.from(args), {cwd, env, detached: true, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true});
  #|   } catch (error) { reject(error); return; }
  #|   const handle = {child, pid: 0, status: null, sweep: -1, groupSignals: 0, fault: '', inputClosed: false};
  #|   const fault = (name, error) => {
  #|     if (!handle.fault) handle.fault = `the worker's ${name} pipe failed: ${error?.message ?? String(error)}`;
  #|   };
  #|   handle.exit = new Promise(done => child.once('exit', (code, signal) => {
  #|     handle.status = {code, signal};
  #|     if (process.platform !== 'win32' && child.pid > 0) {
  #|       handle.groupSignals++;
  #|       try { process.kill(-child.pid, 'SIGKILL'); handle.sweep = 0; }
  #|       catch (error) { handle.sweep = error.code === 'ESRCH' ? 1 : 2; }
  #|     }
  #|     done();
  #|   }));
  #|   handle.stderrDone = new Promise(done => child.stderr.once('close', done));
  #|   // A closed input is the worker's choice, not a transport fault.
  #|   const closed = new Set(['EPIPE', 'ERR_STREAM_DESTROYED', 'ERR_STREAM_WRITE_AFTER_END']);
  #|   child.stdin.on('error', error => { if (closed.has(error?.code)) handle.inputClosed = true; else fault('stdin', error); });
  #|   child.stdout.on('error', error => fault('stdout', error));
  #|   child.stderr.on('error', error => fault('stderr', error));
  #|   child.stderr.on('data', chunk => onStderr(new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.length)));
  #|   child.once('spawn', () => { handle.pid = child.pid; child.on('error', () => {}); resolve(handle); });
  #|   child.once('error', error => reject(error));
  #| })

///|
/// The first pipe fault, or "" when there is none.
extern "js" fn Child::fault_text(self : Child) -> String =
  #| (handle) => handle.fault

///|
/// The first pipe fault, as the text of `TransportFailed`.
fn Child::fault(self : Child) -> String? {
  match self.fault_text() {
    "" => None
    text => Some(text)
  }
}

///|
/// The result of the group signal that the `exit` listener sent: -1 before the
/// exit or on Windows, 0 when it signalled members, 1 when the group was
/// already empty, 2 when the system refused it (macOS refuses a group that
/// holds only zombies).
extern "js" fn Child::sweep(self : Child) -> Int32 =
  #| (handle) => handle.sweep

///|
/// Sends SIGKILL to the worker's group while the worker has not exited, so the
/// worker itself holds the group ID: 0 when it was signalled, 1 when the group
/// no longer exists, 2 when the host may not signal it. After the exit it
/// sends nothing and returns 1: the `exit` listener has swept the group.
extern "js" fn Child::signal_group(self : Child) -> Int32 =
  #| (handle) => {
  #|   if (handle.status) return 1;
  #|   handle.groupSignals++;
  #|   try { process.kill(-handle.pid, 'SIGKILL'); return 0; }
  #|   catch (error) { return error.code === 'ESRCH' ? 1 : 2; }
  #| }

///|
extern "js" fn Child::pid(self : Child) -> Int32 =
  #| (handle) => handle.pid

///|
/// The worker's stdout as a web stream (`Readable.toWeb`).
extern "js" fn Child::stdout(self : Child) -> @js_async.JsReadableStream =
  #| (handle) => process.getBuiltinModule('node:stream').Readable.toWeb(handle.child.stdout)

///|
/// Writes bytes to the worker's stdin. The promise resolves with 0 when Node
/// has written them, 1 when the worker has closed its input and 2 on another
/// write error, which the handle keeps as its fault. It rejects on an abort.
extern "js" fn Child::write(
  self : Child,
  bytes : Bytes,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Int32] =
  #| (handle, bytes, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   try {
  #|     handle.child.stdin.write(bytes, error => {
  #|       signal.removeEventListener('abort', abort);
  #|       if (!error) { resolve(0); return; }
  #|       if (['EPIPE', 'ERR_STREAM_DESTROYED', 'ERR_STREAM_WRITE_AFTER_END'].includes(error.code)) { resolve(1); return; }
  #|       if (!handle.fault) handle.fault = `the worker's stdin pipe failed: ${error.message}`;
  #|       resolve(2);
  #|     });
  #|   } catch (error) {
  #|     signal.removeEventListener('abort', abort);
  #|     if (!handle.fault) handle.fault = `the worker's stdin pipe failed: ${error.message}`;
  #|     resolve(2);
  #|   }
  #| })

///|
/// Discards the worker's stdout from now on, in Node itself: the stream
/// flows into a listener that drops each chunk. `Readable.toWeb` pauses the
/// stream while its queue is full and resumes it only when the host reads,
/// so without this a worker that writes after the end of its input could
/// block on a full pipe. A `receive` that waits now ends at the end of
/// stdout, and the channel refuses it because it is stopping.
extern "js" fn Child::discard_output(self : Child) -> Unit =
  #| (handle) => {
  #|   const stdout = handle.child.stdout;
  #|   stdout.removeAllListeners('data');
  #|   stdout.on('data', () => {});
  #|   stdout.resume();
  #| }

///|
/// Ends the worker's stdin, so the worker reads the end of its input.
extern "js" fn Child::end_input(self : Child) -> Unit =
  #| (handle) => { try { handle.child.stdin.end(); } catch {} }

///|
/// Resolves when the worker has exited, or at once if it already has.
extern "js" fn Child::exited(
  self : Child,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   handle.exit.then(() => { signal.removeEventListener('abort', abort); resolve(undefined); });
  #| })

///|
/// Resolves when the worker's stderr has closed.
extern "js" fn Child::stderr_closed(
  self : Child,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   handle.stderrDone.then(() => { signal.removeEventListener('abort', abort); resolve(undefined); });
  #| })

///|
/// The exit code, or -1 when the worker has not exited or exited by a signal.
extern "js" fn Child::exit_code(self : Child) -> Int32 =
  #| (handle) => handle.status && handle.status.code !== null ? handle.status.code : -1

///|
/// The number of the signal that ended the worker, or 0.
extern "js" fn Child::exit_signal(self : Child) -> Int32 =
  #| (handle) => {
  #|   const name = handle.status && handle.status.signal;
  #|   if (!name) return 0;
  #|   return process.getBuiltinModule('node:os').constants.signals[name] ?? 0;
  #| }

///|
extern "js" fn host_is_windows() -> Bool =
  #| () => process.platform === 'win32'

///|
/// Whether the process group still has a member, a zombie included. The probe
/// is signal 0, which sends nothing. The host probes only after a signal that
/// found members, and stops at the first `ESRCH`, so the group ID cannot have
/// been reused.
extern "js" fn group_present(pid : Int32) -> Bool =
  #| (pid) => {
  #|   try { process.kill(-pid, 0); return true; }
  #|   catch (error) { return error.code !== 'ESRCH'; }
  #| }

///|
/// Runs `taskkill /PID pid /T /F` and resolves with its exit code, or -1 when
/// it cannot start.
extern "js" fn kill_tree(
  pid : Int32,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Int32] =
  #| (pid, signal) => new Promise((resolve, reject) => {
  #|   const {spawn} = process.getBuiltinModule('node:child_process');
  #|   const taskkill = (process.env.SystemRoot || 'C:\\Windows') + '\\System32\\taskkill.exe';
  #|   const killer = spawn(taskkill, ['/PID', String(pid), '/T', '/F'], {stdio: 'ignore', windowsHide: true});
  #|   const abort = () => { killer.kill(); reject(signal.reason); };
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   killer.once('error', () => { signal.removeEventListener('abort', abort); resolve(-1); });
  #|   killer.once('exit', code => { signal.removeEventListener('abort', abort); resolve(code ?? -1); });
  #| })

///|
/// Removes a directory tree once. Returns whether the path no longer exists.
extern "js" fn remove_directory_once(path : String) -> Bool =
  #| (path) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   try { fs.rmSync(path, {recursive: true, force: true}); } catch {}
  #|   return !fs.existsSync(path);
  #| }

///|
/// Removes a directory tree and retries for at most `REMOVE_RETRY_MS`: on
/// Windows a file stays in use for a short time after its process has exited.
/// Returns whether the directory is gone.
async fn remove_directory(path : String) -> Bool {
  let started = @async.now()
  while !remove_directory_once(path) {
    guard @async.now() - started < @process.REMOVE_RETRY_MS.to_int64() else {
      return false
    }
    @async.sleep(50)
  }
  true
}

///|
/// The result of reading an artifact without following a symbolic link.
#external
priv type ArtifactRead

///|
/// Opens the artifact with `O_NOFOLLOW` (and `O_NONBLOCK`, so a FIFO cannot
/// block), checks with `fstat` that it is a regular file within `limit`
/// bytes, and reads it through the same descriptor with `fs.promises`, so a
/// large artifact does not block the event loop. Windows has no
/// `O_NOFOLLOW`; there the host refuses a link that `lstat` reports.
extern "js" fn read_artifact(
  path : String,
  limit : Int32,
) -> @js_async.Promise[ArtifactRead] =
  #| async (path, limit) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   let file;
  #|   try {
  #|     if (process.platform === 'win32') {
  #|       if ((await fs.promises.lstat(path)).isSymbolicLink()) return {problem: 1};
  #|       file = await fs.promises.open(path, 'r');
  #|     } else {
  #|       const {O_RDONLY, O_NOFOLLOW, O_NONBLOCK} = fs.constants;
  #|       file = await fs.promises.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  #|     }
  #|     const stat = await file.stat();
  #|     if (!stat.isFile()) return {problem: 2};
  #|     if (stat.size > limit) return {problem: 3};
  #|     const bytes = await file.readFile();
  #|     if (bytes.length > limit) return {problem: 3};
  #|     return {problem: 0, bytes: new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.length)};
  #|   } catch (error) {
  #|     return error.code === 'ELOOP' ? {problem: 1} : {problem: 4, detail: String(error.message)};
  #|   } finally {
  #|     if (file !== undefined) { try { await file.close(); } catch {} }
  #|   }
  #| }

///|
/// 0 when the read succeeded, 1 a symbolic link, 2 not a regular file, 3 too
/// large, 4 unreadable.
extern "js" fn ArtifactRead::problem_code(self : ArtifactRead) -> Int32 =
  #| (read) => read.problem

///|
extern "js" fn ArtifactRead::detail(self : ArtifactRead) -> String =
  #| (read) => read.detail ?? ''

///|
extern "js" fn ArtifactRead::bytes(self : ArtifactRead) -> Bytes =
  #| (read) => read.bytes

///|
/// Creates a private directory (mode 0700) in the staging layout: an empty
/// `work` directory and a `bin` directory (both 0700) that holds a new file
/// `name` that only its owner can read and execute. Resolves with the
/// directory, or "" when a step fails; a failed step leaves no directory
/// behind.
extern "js" fn write_private_copy(
  name : String,
  bytes : Bytes,
  bin : String,
  work : String,
) -> @js_async.Promise[String] =
  #| async (name, bytes, bin, work) => {
  #|   const fs = process.getBuiltinModule('node:fs'), os = process.getBuiltinModule('node:os'), path = process.getBuiltinModule('node:path');
  #|   let directory = '';
  #|   try {
  #|     directory = await fs.promises.mkdtemp(path.join(await fs.promises.realpath(os.tmpdir()), 'morphir-worker-'));
  #|     await fs.promises.mkdir(path.join(directory, work), {mode: 0o700});
  #|     await fs.promises.mkdir(path.join(directory, bin), {mode: 0o700});
  #|     await fs.promises.writeFile(path.join(directory, bin, name), bytes, {mode: 0o500, flag: 'wx'});
  #|     return directory;
  #|   } catch {
  #|     if (directory) { try { await fs.promises.rm(directory, {recursive: true, force: true}); } catch {} }
  #|     return '';
  #|   }
  #| }

///|
/// The operating system and the architecture of the Node host as an index:
/// 1 aarch64 macOS, 2 x86_64 macOS, 3 aarch64 Linux, 4 x86_64 Linux,
/// 5 aarch64 Windows, 6 x86_64 Windows, or 0.
extern "js" fn host_machine_code() -> Int32 =
  #| () => {
  #|   const arch = {arm64: 0, x64: 1}[process.arch];
  #|   const os = {darwin: 1, linux: 3, win32: 5}[process.platform];
  #|   return arch === undefined || os === undefined ? 0 : os + arch;
  #| }

///|
/// Whether a regular file exists at `path`, after links.
extern "js" fn file_present(path : String) -> Bool =
  #| (path) => {
  #|   try { return process.getBuiltinModule('node:fs').statSync(path).isFile(); } catch { return false; }
  #| }

///|
/// Lets the host exit while a worker whose stop it could not confirm still
/// runs: destroys the worker's pipes and drops Node's reference to it.
extern "js" fn Child::release(self : Child) -> Unit =
  #| (handle) => {
  #|   for (const stream of [handle.child.stdin, handle.child.stdout, handle.child.stderr]) { try { stream.destroy(); } catch {} }
  #|   handle.child.unref();
  #| }

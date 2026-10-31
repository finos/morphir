///|
#cfg(platform="windows")
#external
priv type WinWorker

///|
#cfg(platform="windows")
#borrow(path, problem)
extern "C" fn read_artifact_ffi(
  path : Bytes,
  limit : Int64,
  problem : FixedArray[Int32],
) -> Bytes = "morphir_worker_read_artifact"

///|
#cfg(platform="windows")
#borrow(path, command, cwd, error)
extern "C" fn spawn_ffi(
  path : Bytes,
  command : Bytes,
  cwd : Bytes,
  error : FixedArray[Int32],
) -> WinWorker = "morphir_worker_win_spawn"

///|
#cfg(platform="windows")
extern "C" fn worker_pid_ffi(worker : WinWorker) -> Int32 = "morphir_worker_win_pid"

///|
#cfg(platform="windows")
extern "C" fn worker_end_ffi(worker : WinWorker, index : Int32) -> @types.Fd = "morphir_worker_win_end"

///|
#cfg(platform="windows")
extern "C" fn hand_over_ffi(worker : WinWorker, streams : Int32) -> Unit = "morphir_worker_win_hand_over"

///|
#cfg(platform="windows")
extern "C" fn terminate_job_ffi(worker : WinWorker) -> Int32 = "morphir_worker_win_terminate"

///|
#cfg(platform="windows")
extern "C" fn active_processes_ffi(worker : WinWorker) -> Int32 = "morphir_worker_win_active"

///|
#cfg(platform="windows")
extern "C" fn release_worker_ffi(worker : WinWorker) -> Unit = "morphir_worker_win_release"

///|
/// A NUL-terminated UTF-16 string for a Windows call.
#cfg(platform="windows")
fn os_text(text : String) -> Bytes raise @worker.LaunchError {
  guard !text.contains_char('\u0000') else {
    raise LaunchFailed("a worker argument or path holds a NUL character")
  }
  let buffer = @buffer.Buffer::Buffer()
  for unit in text.to_array() {
    // `String` holds UTF-16; write each code unit little-endian.
    let code = unit.to_int()
    if code > 0xFFFF {
      let high = 0xD800 + ((code - 0x10000) >> 10)
      let low = 0xDC00 + ((code - 0x10000) & 0x3FF)
      buffer
      ..write_byte((high & 0xFF).to_byte())
      .write_byte((high >> 8).to_byte())
      buffer
      ..write_byte((low & 0xFF).to_byte())
      .write_byte((low >> 8).to_byte())
    } else {
      buffer
      ..write_byte((code & 0xFF).to_byte())
      .write_byte((code >> 8).to_byte())
    }
  }
  buffer..write_byte(b'\x00').write_byte(b'\x00')
  buffer.to_bytes()
}

///|
/// Windows has no C library loaders to find, so detection asks for no file.
#cfg(platform="windows")
fn file_present(_path : String) -> Bool {
  false
}

///|
#cfg(platform="windows")
fn read_artifact(path : String) -> Bytes raise @worker.LaunchError {
  let problem : FixedArray[Int32] = [0, 0]
  let bytes = read_artifact_ffi(
    os_text(path),
    @shared.ARTIFACT_LIMIT_BYTES.to_int64(),
    problem,
  )
  match problem[0] {
    0 => bytes
    code => raise ArtifactUnreadable(artifact_problem(code, problem[1]))
  }
}

///|
/// A worker's job object. Closing it terminates anything left in it.
#cfg(platform="windows")
priv struct Job {
  worker : WinWorker
  mut released : Bool
}

///|
#cfg(platform="windows")
impl Tree for Job with fn terminate(self) {
  if !self.released {
    ignore(terminate_job_ffi(self.worker))
  }
}

///|
#cfg(platform="windows")
impl Tree for Job with fn kill(self) {
  if !self.released {
    ignore(terminate_job_ffi(self.worker))
  }
}

///|
#cfg(platform="windows")
impl Tree for Job with fn state(self) {
  guard !self.released else { return Gone }
  match active_processes_ffi(self.worker) {
    0 => Gone
    count if count > 0 => Live
    code => Unknown(code)
  }
}

///|
#cfg(platform="windows")
impl Tree for Job with fn release(self) {
  if !self.released {
    self.released = true
    release_worker_ffi(self.worker)
  }
}

///|
/// Starts the staged copy in a new job object with kill-on-close. The worker
/// joins the job before it runs code, and inherits only its three pipe ends.
#cfg(platform="windows")
fn Job::start(
  staged : @shared.StagedArtifact,
  args : Array[String],
) -> Job raise @worker.LaunchError {
  let executable = staged.executable()
  let command = os_text(windows_command_line(executable, args[:]))
  let error : FixedArray[Int32] = [0]
  let worker = spawn_ffi(
    os_text(executable),
    command,
    os_text(staged.working_directory()),
    error,
  )
  if error[0] != 0 {
    raise LaunchFailed("CreateProcessW failed with error \{error[0]}")
  }
  { worker, released: false, }
}

///|
/// Makes streams of the host's pipe ends with `wrap`, one at a time; see
/// `wrap_ends`. Anonymous pipes are synchronous; `RawFdStream` reads and
/// writes them in the event loop's worker threads. It registers nothing with
/// the event loop on Windows, so a failed wrap leaves its handle open, and
/// `hand_over_ffi` closes it with the other ends left. If a wrap fails, the
/// job stops and is released.
#cfg(platform="windows")
async fn Job::spawned(
  self : Job,
  wrap~ : async (@types.Fd) -> @raw_fd.RawFdStream = wrap_end,
) -> Spawned raise @worker.LaunchError {
  let worker = self.worker
  let ends = FixedArray::makei(3, i => worker_end_ffi(worker, i))
  // A cancellation takes effect after the hand-over, in the caller.
  let (input, output, errors) = @async.protect_from_cancel(() => {
    wrap_ends(ends, wrap~, close_from=streams => hand_over_ffi(worker, streams))
  }) catch {
    error => {
      Tree::kill(self)
      Tree::release(self)
      raise LaunchFailed("cannot open the worker's pipes: \{error}")
    }
  }
  hand_over_ffi(worker, 3)
  {
    pid: worker_pid_ffi(worker),
    tree: self,
    stop_method: JobTermination,
    input,
    output,
    errors,
    close_streams: () => {
      input.close()
      output.close()
      errors.close()
    },
    close_input: () => input.close(),
  }
}

///|
/// Starts the staged copy in a new job object; see `Job::start`.
#cfg(platform="windows")
async fn spawn(
  staged : @shared.StagedArtifact,
  args : Array[String],
) -> Spawned raise @worker.LaunchError {
  Job::start(staged, args).spawned()
}

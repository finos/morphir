///|
#cfg(not(platform="windows"))
#borrow(path, problem)
extern "C" fn read_artifact_ffi(
  path : Bytes,
  limit : Int64,
  problem : FixedArray[Int32],
) -> Bytes = "morphir_worker_read_artifact"

///|
#cfg(not(platform="windows"))
#borrow(path, args, cwd, host, identity, pid)
extern "C" fn spawn_ffi(
  path : Bytes,
  args : FixedArray[Bytes],
  count : Int32,
  cwd : Bytes,
  host : FixedArray[Int32],
  identity : FixedArray[Int64],
  pid : FixedArray[Int32],
) -> Int32 = "morphir_worker_spawn"

///|
#cfg(not(platform="windows"))
extern "C" fn close_end_ffi(fd : Int32, device : Int64, inode : Int64) -> Unit = "morphir_worker_close_end"

///|
#cfg(not(platform="windows"))
extern "C" fn signal_group_ffi(pgid : Int32, terminate : Bool) -> Int32 = "morphir_worker_signal_group"

///|
#cfg(not(platform="windows"))
extern "C" fn group_state_ffi(pgid : Int32) -> Int32 = "morphir_worker_group_state"

///|
/// The errno of an exec of a file that a process holds open for writing.
#cfg(not(platform="windows"))
const ETXTBSY : Int32 = 26

///|
/// A NUL-terminated UTF-8 string for a C call.
#cfg(not(platform="windows"))
fn os_text(text : String) -> Bytes raise @worker.LaunchError {
  guard !text.contains_char('\u0000') else {
    raise LaunchFailed("a worker argument or path holds a NUL character")
  }
  let buffer = @buffer.Buffer::Buffer()
  buffer.write_bytes(@utf8.encode(text))
  buffer.write_byte(b'\x00')
  buffer.to_bytes()
}

///|
#cfg(not(platform="windows"))
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
/// A worker's process group. Its ID is the PID of the worker, its leader.
#cfg(not(platform="windows"))
priv struct ProcessGroup {
  pgid : Int32
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn terminate(self) {
  ignore(signal_group_ffi(self.pgid, true))
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn kill(self) {
  ignore(signal_group_ffi(self.pgid, false))
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn state(self) {
  match group_state_ffi(self.pgid) {
    0 | 1 => Gone
    2 => Live
    code => Unknown(code)
  }
}

///|
#cfg(not(platform="windows"))
impl Tree for ProcessGroup with fn release(_self) {
  ()
}

///|
/// The host's ends of a worker's three pipes, before they become streams:
/// stdin, stdout and stderr, each with the device and inode that it had when
/// the stub made it.
#cfg(not(platform="windows"))
priv struct HostEnds {
  fds : FixedArray[Int32]
  identity : FixedArray[Int64]
}

///|
/// Closes every end from `index` that is still the host's pipe end. A wrap
/// that failed may have closed its end already.
#cfg(not(platform="windows"))
fn HostEnds::close_from(self : HostEnds, index : Int32) -> Unit {
  for i in index..<3 {
    close_end_ffi(self.fds[i], self.identity[2 * i], self.identity[2 * i + 1])
  }
}

///|
/// Makes streams of the host's ends with `wrap`. See `wrap_ends`.
#cfg(not(platform="windows"))
async fn HostEnds::streams(
  self : HostEnds,
  wrap~ : async (Int32) -> @raw_fd.RawFdStream,
) -> (@raw_fd.RawFdStream, @raw_fd.RawFdStream, @raw_fd.RawFdStream) {
  wrap_ends(self.fds, wrap~, close_from=index => self.close_from(index))
}

///|
/// Starts the staged copy as the leader of a new process group, with three
/// pipes, no other descriptor, an empty environment and the private working
/// directory. The C stub makes the pipes, so the worker's ends are never
/// registered with the host's event loop; the host wraps only its own ends,
/// with `wrap`.
#cfg(not(platform="windows"))
async fn spawn(
  staged : @shared.StagedArtifact,
  args : Array[String],
  wrap~ : async (Int32) -> @raw_fd.RawFdStream = wrap_end,
) -> Spawned {
  let executable = staged.executable()
  let argv = FixedArray::make(args.length() + 1, b"")
  argv[0] = os_text(executable)
  for i, argument in args {
    argv[i + 1] = os_text(argument)
  }
  let ends = HostEnds::{ fds: [-1, -1, -1], identity: FixedArray::make(6, 0L), }
  let pid : FixedArray[Int32] = [0]
  let path = os_text(executable)
  let cwd = os_text(staged.working_directory())
  let deadline = @async.now() + TEXT_BUSY_RETRY_MS.to_int64()
  let mut pause = 5
  let mut error = spawn_ffi(
    path,
    argv,
    argv.length(),
    cwd,
    ends.fds,
    ends.identity,
    pid,
  )
  // A failed spawn leaves no process and no descriptor, so it can run again.
  while error == ETXTBSY && @async.now() < deadline {
    @async.sleep(pause)
    pause = @cmp.minimum(pause * 2, 100)
    error = spawn_ffi(
      path,
      argv,
      argv.length(),
      cwd,
      ends.fds,
      ends.identity,
      pid,
    )
  }
  let group = ProcessGroup::{ pgid: pid[0], }
  // Until the worker is handed over, any way out stops its group and reaps
  // the leader, so that the caller can remove the private directory. The
  // stub starts no process when it reports an error, but a PID is reaped in
  // every case.
  let mut handed_over = false
  defer (if !handed_over && pid[0] > 0 {
    @async.protect_from_cancel(() => {
      Tree::kill(group)
      ignore(Leader::new(pid[0]).wait_for(@shared.STOP_CONFIRM_MS))
    })
  })
  if error != 0 {
    raise @worker.LaunchError::LaunchFailed(
      "posix_spawn failed with errno \{error}",
    )
  }
  let (input, output, errors) = @async.protect_from_cancel(() => {
    ends.streams(wrap~)
  }) catch {
    error =>
      raise @worker.LaunchError::LaunchFailed(
        "cannot open the worker's pipes: \{error}",
      )
  }
  handed_over = true
  {
    pid: pid[0],
    tree: group,
    stop_method: GroupSignal,
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

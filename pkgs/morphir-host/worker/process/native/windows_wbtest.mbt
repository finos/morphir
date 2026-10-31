// White-box Windows tests. They run only on Windows, in the deliberate
// Windows run of task 2.3.

///|
#cfg(platform="windows")
#borrow(pids)
extern "C" fn processes_ffi(
  worker : WinWorker,
  pids : FixedArray[Int32],
  capacity : Int32,
) -> Int32 = "morphir_worker_win_processes"

///|
/// The IDs of the processes in the job, or none after it is released.
#cfg(platform="windows")
fn Job::processes(self : Job) -> Array[Int32] {
  guard !self.released else { return [] }
  let pids = FixedArray::make(256, 0)
  let count = processes_ffi(self.worker, pids, pids.length())
  Array::makei(@cmp.maximum(count, 0), i => pids[i])
}

///|
#cfg(platform="windows")
#borrow(path, file)
extern "C" fn open_unshared_ffi(
  path : Bytes,
  file : FixedArray[UInt64],
) -> Int32 = "morphir_worker_win_open_unshared"

///|
#cfg(platform="windows")
extern "C" fn close_file_ffi(file : UInt64) -> Unit = "morphir_worker_win_close_file"

///|
/// A file that the test holds open with no sharing, so that no one can
/// delete it.
#cfg(platform="windows")
priv struct UnsharedFile(UInt64)

///|
/// Creates the file `path` and opens it with no sharing.
#cfg(platform="windows")
fn UnsharedFile::hold(path : String) -> UnsharedFile raise {
  let file : FixedArray[UInt64] = [0]
  let error = open_unshared_ffi(os_text(path), file)
  guard error == 0 else { fail("cannot open \{path}: Windows error \{error}") }
  UnsharedFile(file[0])
}

///|
#cfg(platform="windows")
fn UnsharedFile::release(self : UnsharedFile) -> Unit {
  close_file_ffi(self.0)
}

///|
/// A verified file artifact for a system program.
#cfg(platform="windows")
async fn system_artifact(path : String) -> @worker.ArtifactRef {
  @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Windows)),
    @worker.Sha256::of(@fs.read_file(path).binary()),
  )
}

///|
/// Starts `cmd.exe` from a staged copy with the given arguments.
#cfg(platform="windows")
async fn start_cmd(
  staged : @shared.StagedArtifact,
  args : Array[String],
) -> ProcessChannel {
  ProcessChannel::new(
    Job::start(staged, args).spawned(),
    staged,
    @worker.Limits::host(),
    grace_ms=@shared.EXIT_GRACE_MS,
    confirm_ms=@shared.STOP_CONFIRM_MS,
  )
}

///|
/// The IDs of the `PING.EXE` processes that run on the host.
#cfg(platform="windows")
async fn ping_processes(system_root : String) -> Array[Int32] {
  let (_, listing) = @process.collect_stdout(
    system_root + "\\System32\\tasklist.exe",
    ["/FI", "IMAGENAME eq PING.EXE", "/FO", "CSV", "/NH"],
  )
  let pids = []
  for line in listing.text().split("\n") {
    // "PING.EXE","1234","Console","1","4,000 K"
    let fields = line.trim().split(",").to_array()
    guard fields is [image, pid, ..] && image.to_upper() == "\"PING.EXE\"" else {
      continue
    }
    let digits = pid.trim(chars="\"")
    let value = @string.parse_int(digits) catch { _ => continue }
    pids.push(value)
  }
  pids
}

///|
#cfg(platform="windows")
async test "cancellation terminates the worker's job and every process in it" {
  let system_root = @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows")
  let cmd = system_root + "\\System32\\cmd.exe"
  let ping = system_root + "\\System32\\PING.EXE"
  // PING processes that ran before the test are not the worker's.
  let before = ping_processes(system_root)
  let staged = stage(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse(cmd, Windows)),
      @worker.Sha256::of(@fs.read_file(cmd).binary()),
    ),
  )
  // Whatever the outcome, the test leaves no private directory behind.
  defer ignore(remove_staged(staged))
  let job = Job::start(staged, [
    "/d",
    "/c",
    "start /b \{ping} -n 300 127.0.0.1 >nul & \{ping} -n 300 127.0.0.1 >nul",
  ])
  let channel = ProcessChannel::new(
    job.spawned(),
    staged,
    @worker.Limits::host(),
    grace_ms=@shared.EXIT_GRACE_MS,
    confirm_ms=@shared.STOP_CONFIRM_MS,
  )
  // A failed check still stops the job before the directory goes.
  defer ignore(channel.abort(Cancelled))
  // Wait until both PING grandchildren run.
  let deadline = @async.now() + 10000L
  let mut pings = []
  while @async.now() < deadline {
    pings = ping_processes(system_root).filter(pid => !before.contains(pid))
    if pings.length() >= 2 {
      break
    }
    @async.sleep(50)
  }
  let members = job.processes()
  assert_true(pings.length() >= 2, msg="PING processes: \{pings.length()}")
  assert_true(members.contains(channel.pid()))
  for pid in pings {
    assert_true(members.contains(pid), msg="PING \{pid} is not in the job")
  }
  let stop = channel.abort(Cancelled)
  assert_eq(stop.status, Terminated(Cancelled))
  assert_eq(stop.stop_method, JobTermination)
  for pid in members {
    assert_false(process_alive(pid), msg="process \{pid} of the job runs")
  }
  let left = ping_processes(system_root).filter(pid => !before.contains(pid))
  assert_eq(left, [])
}

///|
#cfg(platform="windows")
async test "an artifact without an extension is staged as .exe and runs" {
  let system_root = @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows")
  let cmd = system_root + "\\System32\\cmd.exe"
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  // A copy of cmd.exe whose name has no extension.
  let original = directory + "\\worker"
  @fs.write_file(original, @fs.read_file(cmd).binary())
  let staged = stage(system_artifact(original))
  defer ignore(remove_staged(staged))
  assert_true(
    staged.executable().has_suffix("\\bin\\worker.exe"),
    msg=staged.executable(),
  )
  assert_true(@fs.exists(staged.executable()))
  let channel = start_cmd(staged, ["/d", "/c", "exit 3"])
  defer ignore(channel.abort(Cancelled))
  let stop = channel.close()
  assert_eq(stop.status, Exited(code=3))
  assert_false(@fs.exists(staged.directory()))
}

///|
/// Waits at most 10 seconds until no process of the job runs.
#cfg(platform="windows")
async fn wait_until_empty(job : Job) -> Unit {
  let deadline = @async.now() + 10000L
  while Tree::state(job) is (Live | Unknown(_)) && @async.now() < deadline {
    @async.sleep(20)
  }
}

///|
#cfg(platform="windows")
async test "a private directory that cannot be removed makes the stop unconfirmed" {
  let system_root = @env.get_env_var("SystemRoot").unwrap_or("C:\\Windows")
  let staged = stage(system_artifact(system_root + "\\System32\\cmd.exe"))
  defer ignore(remove_staged(staged))
  let job = Job::start(staged, ["/d", "/c", "exit 0"])
  let channel = ProcessChannel::new(
    job.spawned(),
    staged,
    @worker.Limits::host(),
    grace_ms=@shared.EXIT_GRACE_MS,
    confirm_ms=@shared.STOP_CONFIRM_MS,
  )
  defer ignore(channel.abort(Cancelled))
  // The worker has exited and its job is empty before the close, so the
  // close reports ExitedAfterExit: no process of the job was left to stop.
  wait_until_empty(job)
  assert_true(Tree::state(job) is Gone, msg="the job still has a process")
  // The worker's working directory keeps an entry that the host cannot
  // remove: the test holds it open with no sharing, as the Node test does.
  let kept = UnsharedFile::hold(staged.working_directory() + "\\kept")
  let mut held = true
  // Release the file, then remove the directory, whatever the outcome.
  defer (if held { kept.release() })
  let started = @async.now()
  let stop = channel.close()
  let waited = @async.now() - started
  kept.release()
  held = false
  assert_true(@fs.exists(staged.directory()))
  assert_true(remove_staged(staged), msg="the directory stays after release")
  assert_eq(stop.status, Unconfirmed(GraceExpired))
  assert_eq(stop.stop_method, ExitedAfterExit)
  // The host retried the removal for its bound.
  assert_true(waited >= (@shared.REMOVE_RETRY_MS - 100).to_int64())
}

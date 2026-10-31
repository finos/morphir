// The shared launcher conformance suite against the native launcher on
// Windows. It runs only on Windows, in the deliberate Windows run of task 2.3.
//
// Windows has no POSIX shell for `fixtures/conformance.sh`, so the fixture is
// the Node fixture `worker/process/node/fixtures/worker.mjs`, which speaks the
// same protocol. The artifact is `node.exe`: the launcher stages a private
// copy of it, starts that copy in a new job object with only `SystemRoot` in
// its environment and gives it the script as its first argument. The suite
// then tests framed stdio over the anonymous pipes, the environment, the
// deadline, cancellation, the exit grace period and job termination.

///|
/// The native launcher on Windows, started on `node.exe` with the Node
/// fixture script.
#cfg(platform="windows")
priv struct WindowsFixture {
  /// The Node executable, as a verified file artifact.
  node : @worker.ArtifactRef
  /// The absolute path of the Node fixture script.
  script : String
}

///|
#cfg(platform="windows")
impl @conformance.Fixture for WindowsFixture with fn start(
  self,
  flags,
  args,
  limits,
) {
  let spec = @worker.WorkerSpec::new(
    self.node,
    Process(
      platform=@native.host_machine().unwrap().platforms()[0],
      args=[self.script, ..flags.map(flag => flag.argument()), ..args],
    ),
  )
  @native.ProcessLauncher::new().launch(spec, limits)
}

///|
#cfg(platform="windows")
impl @conformance.Fixture for WindowsFixture with fn alive(_self, pid) {
  @native.process_alive(pid)
}

///|
#cfg(platform="windows")
impl @conformance.Fixture for WindowsFixture with fn ownership(_self) {
  Job
}

///|
/// The launcher passes only `SystemRoot`.
#cfg(platform="windows")
impl @conformance.Fixture for WindowsFixture with fn documented_environment(
  _self,
) {
  ["SystemRoot"]
}

///|
/// None. The descriptor case does not apply on Windows: the Node fixture
/// cannot list the handles that it inherited, so it answers `fds` with
/// `null`. The stub gives the worker only its three pipe ends, through
/// `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`.
#cfg(platform="windows")
impl @conformance.Fixture for WindowsFixture with fn held_open(_self) {
  []
}

///|
/// The directory entries of `PATH`, without quotes and with a trailing
/// separator.
#cfg(platform="windows")
fn search_path() -> Array[String] {
  let entries = []
  for entry in @env.get_env_var("PATH").unwrap_or("").split(";") {
    let directory = entry.trim(chars="\" ")
    guard directory != "" else { continue }
    entries.push(
      if directory.has_suffix("\\") {
        directory.to_owned()
      } else {
        "\{directory}\\"
      },
    )
  }
  entries
}

///|
/// The Node executable that runs the fixture: `MORPHIR_TEST_NODE` when it is
/// set, or else the program that the first `node.exe` on `PATH` runs. A
/// version manager can put a shim named `node.exe` on `PATH`, so the test asks
/// that program for `process.execPath`.
#cfg(platform="windows")
async fn node_executable() -> String {
  if @env.get_env_var("MORPHIR_TEST_NODE") is Some(path) && path != "" {
    return @fs.realpath(path)
  }
  for directory in search_path() {
    let candidate = "\{directory}node.exe"
    guard @fs.exists(candidate) else { continue }
    let (status, out) = @process.collect_stdout(candidate, [
      "-p", "process.execPath",
    ])
    let path = out.text().trim().to_owned()
    guard status == 0 && path != "" else {
      fail("\{candidate} does not report its executable")
    }
    return @fs.realpath(path)
  }
  fail("no node.exe on PATH; set MORPHIR_TEST_NODE to the Node executable")
}

///|
#cfg(platform="windows")
async test "the native launcher passes the launcher conformance suite with the Node fixture" {
  let path = node_executable()
  // The test computes the digest once. For each worker, the launcher reads,
  // checks and stages node.exe again.
  let node = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Windows)),
    @worker.Sha256::of(@fs.read_file(path).binary()),
  )
  let script = @fs.realpath("worker/process/node/fixtures/worker.mjs")
  // The worker must not see the user's environment.
  @env.set_env_var("MORPHIR_HOME", "C:\\Users\\user\\.morphir")
  @env.set_env_var("MORPHIR_TOKEN", "secret-token")
  @conformance.check(WindowsFixture::{ node, script, })
}

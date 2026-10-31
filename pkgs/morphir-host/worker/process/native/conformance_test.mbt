///|
/// Runs the shared launcher conformance suite against the native launcher on
/// Linux and macOS, with the POSIX sh fixture `fixtures/conformance.sh`. On
/// Windows, `conformance_windows_test.mbt` runs the suite with the Node fixture.
#cfg(not(platform="windows"))
priv struct NativeFixture {
  /// Files that the host holds open while it starts workers.
  held : Array[String]
}

///|
#cfg(not(platform="windows"))
impl @conformance.Fixture for NativeFixture with fn start(
  _self,
  flags,
  args,
  limits,
) {
  let path = @fs.realpath("worker/process/native/fixtures/conformance.sh")
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Posix)),
    @worker.Sha256::of(@fs.read_file(path).binary()),
  )
  let spec = @worker.WorkerSpec::new(
    artifact,
    Process(
      platform=@native.host_machine().unwrap().platforms()[0],
      args=[..flags.map(flag => flag.argument()), ..args],
    ),
  )
  @native.ProcessLauncher::new().launch(spec, limits)
}

///|
#cfg(not(platform="windows"))
impl @conformance.Fixture for NativeFixture with fn alive(_self, pid) {
  @native.process_alive(pid)
}

///|
#cfg(not(platform="windows"))
impl @conformance.Fixture for NativeFixture with fn ownership(_self) {
  Group
}

///|
#cfg(not(platform="windows"))
impl @conformance.Fixture for NativeFixture with fn documented_environment(
  _self,
) {
  []
}

///|
#cfg(not(platform="windows"))
impl @conformance.Fixture for NativeFixture with fn held_open(self) {
  self.held
}

///|
/// The status of a file as "device:inode", as the fixture reports it.
#cfg(not(platform="windows"))
async fn identity(path : String) -> String {
  let format = match @async.platform {
    MacOS => ["-L", "-f", "%d:%i", path]
    _ => ["-L", "-c", "%d:%i", path]
  }
  let (_, out) = @process.collect_stdout("/usr/bin/stat", format)
  out.text().trim().to_owned()
}

///|
#cfg(not(platform="windows"))
async test "the native launcher passes the launcher conformance suite" {
  @env.set_env_var("MORPHIR_HOME", "/home/user/.morphir")
  @env.set_env_var("MORPHIR_TOKEN", "secret-token")
  // Hold a file open for the whole suite: no worker may inherit it.
  let path = @fs.realpath("worker/process/native/README.mbt.md")
  let held = @fs.open(path, mode=ReadOnly)
  defer held.close()
  @conformance.check(NativeFixture::{ held: [identity(path)], })
}

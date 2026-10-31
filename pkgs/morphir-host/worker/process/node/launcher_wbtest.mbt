///|
extern "js" fn write_file(path : String, text : String) -> Unit =
  #| (path, text) => process.getBuiltinModule('node:fs').writeFileSync(path, text, {mode: 0o700})

///|
extern "js" fn read_file(path : String) -> Bytes =
  #| (path) => { const b = process.getBuiltinModule('node:fs').readFileSync(path); return new Uint8Array(b.buffer, b.byteOffset, b.length); }

///|
extern "js" fn make_link(target : String, path : String) -> Unit =
  #| (target, path) => process.getBuiltinModule('node:fs').symlinkSync(target, path)

///|
fn host_path(text : String) -> @worker.ArtifactPath raise {
  let style = host_platform().unwrap().path_style()
  @worker.ArtifactPath::parse(text, style)
}

///|
/// A small executable that runs the fixture worker, and the arguments that
/// come before the fixture's own. Windows cannot start a script without a
/// shell, so there the artifact is the Node executable.
fn fixture_artifact(directory : String) -> (String, Array[String]) {
  if host_is_windows() {
    (node_executable(), [fixture_script()])
  } else {
    let path = join_path(directory, "fixture-worker")
    write_file(
      path,
      "#!/bin/sh\nexec '\{node_executable()}' '\{fixture_script()}' \"$@\"\n",
    )
    (path, [])
  }
}

///|
fn file_artifact(path : String) -> @worker.ArtifactRef raise {
  @worker.ArtifactRef::new(
    File(host_path(path)),
    @worker.Sha256::of(read_file(path)),
  )
}

///|
fn exit_message() -> @worker.Message {
  @worker.Message::new({ "jsonrpc": "2.0", "method": "exit" })
}

///|
async fn echo(channel : &@worker.Channel) -> Json {
  channel.send(
    @worker.Message::new({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "echo",
      "params": "hi",
    }),
  )
  channel.receive().json()
}

///|
async fn launch_error(
  action : async () -> Unit raise @worker.LaunchError,
) -> @worker.LaunchError? {
  action() catch {
    error => return Some(error)
  }
  None
}

///|
async test "the worker runs the verified copy, not a replaced original" {
  let directory = make_test_directory()
  let (path, args) = fixture_artifact(directory)
  let artifact = file_artifact(path)
  let staged = stage(artifact)
  assert_true(staged.executable() != path)
  assert_true(path_exists(staged.executable()))
  if !host_is_windows() {
    // Replace the original after verification; the copy still runs.
    write_file(path, "#!/bin/sh\nexit 7\n")
  }
  let channel = NodeProcessChannel::start(staged, args)
  assert_eq(echo(channel), { "jsonrpc": "2.0", "id": 1, "result": "hi" })
  channel.send(exit_message())
  debug_inspect(channel.close().status, content="Exited(code=0)")
  // The host removes the private directory after the stop.
  assert_false(path_exists(staged.directory()))
  ignore(remove_directory(directory))
}

///|
async test "an artifact named work stages into bin, apart from the working directory" {
  guard !host_is_windows() else { return }
  let directory = make_test_directory()
  let path = join_path(directory, "work/work")
  write_file(
    path,
    "#!/bin/sh\nexec '\{node_executable()}' '\{fixture_script()}' \"$@\"\n",
  )
  let staged = stage(file_artifact(path))
  assert_eq(
    staged.executable(),
    join_path(join_path(staged.directory(), "bin"), "work"),
  )
  assert_eq(staged.working_directory(), join_path(staged.directory(), "work"))
  let channel = NodeProcessChannel::start(staged, [])
  assert_eq(echo(channel), { "jsonrpc": "2.0", "id": 1, "result": "hi" })
  channel.send(exit_message())
  debug_inspect(channel.close().status, content="Exited(code=0)")
  assert_false(path_exists(staged.directory()))
  ignore(remove_directory(directory))
}

///|
async test "a replaced original no longer matches its digest" {
  guard !host_is_windows() else { return }
  let directory = make_test_directory()
  let (path, _) = fixture_artifact(directory)
  let artifact = file_artifact(path)
  write_file(path, "#!/bin/sh\nexit 7\n")
  let refused = launch_error(() => ignore(stage(artifact)))
  guard refused is Some(DigestMismatch(expected~, actual~)) &&
    expected == artifact.sha256 &&
    actual == @worker.Sha256::of(read_file(path)) else {
    fail("a replaced artifact was not refused")
  }
  ignore(remove_directory(directory))
}

///|
async test "staging refuses links, directories and artifacts in memory" {
  let directory = make_test_directory()
  let (path, _) = fixture_artifact(directory)
  if !host_is_windows() {
    let link = join_path(directory, "link")
    make_link(path, link)
    let artifact = @worker.ArtifactRef::new(
      File(host_path(link)),
      @worker.Sha256::of(read_file(path)),
    )
    debug_inspect(
      launch_error(() => ignore(stage(artifact))),
      content="Some(ArtifactUnreadable(SymbolicLink))",
    )
  }
  let artifact = @worker.ArtifactRef::new(
    File(host_path(directory)),
    @worker.Sha256::of(b""),
  )
  debug_inspect(
    launch_error(() => ignore(stage(artifact))),
    content="Some(ArtifactUnreadable(NotRegularFile))",
  )
  let artifact = @worker.ArtifactRef::new(
    Memory(b"bytes"),
    @worker.Sha256::of(b"bytes"),
  )
  debug_inspect(
    launch_error(() => ignore(stage(artifact))),
    content="Some(RuntimeUnavailable(supported=[Process]))",
  )
  let artifact = @worker.ArtifactRef::new(
    File(host_path(join_path(directory, "missing"))),
    @worker.Sha256::of(b""),
  )
  guard launch_error(() => ignore(stage(artifact)))
    is Some(ArtifactUnreadable(Unreadable(..))) else {
    fail("a missing artifact was not unreadable")
  }
  ignore(remove_directory(directory))
}

///|
async test "the launcher starts a process worker on the host platform" {
  let directory = make_test_directory()
  let (path, args) = fixture_artifact(directory)
  let platform = host_platform().unwrap()
  let spec = @worker.WorkerSpec::new(
    file_artifact(path),
    Process(platform~, args~),
  )
  let channel = NodeProcessLauncher::new().launch(spec, @worker.Limits::host())
  assert_eq(echo(channel), { "jsonrpc": "2.0", "id": 1, "result": "hi" })
  channel.send(exit_message())
  let stop = channel.close()
  debug_inspect(stop.status, content="Exited(code=0)")
  debug_inspect(stop.stop_method, content="ExitedAfterExit")
  ignore(remove_directory(directory))
}

///|
async test "the launcher refuses a WASM runtime and another platform" {
  let directory = make_test_directory()
  let (path, _) = fixture_artifact(directory)
  let artifact = file_artifact(path)
  let refused = try {
    ignore(
      NodeProcessLauncher::new().launch(
        @worker.WorkerSpec::new(artifact, Wasm(abi=None)),
        @worker.Limits::host(),
      ),
    )
    false
  } catch {
    @worker.LaunchError::RuntimeUnavailable(supported=[Process]) => true
    _ => false
  }
  assert_true(refused)
  let other : @worker.Platform = if host_platform() == Some(X86_64PcWindowsMsvc) {
    Aarch64AppleDarwin
  } else {
    X86_64PcWindowsMsvc
  }
  let refused = try {
    ignore(
      NodeProcessLauncher::new().launch(
        @worker.WorkerSpec::new(artifact, Process(platform=other, args=[])),
        @worker.Limits::host(),
      ),
    )
    None
  } catch {
    @worker.LaunchError::PlatformMismatch(platform) => Some(platform)
    _ => None
  }
  assert_eq(refused, Some(other))
  ignore(remove_directory(directory))
}

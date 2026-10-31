///|
/// The Node executable that runs the fixture worker. Tests need Node; the
/// launcher itself does not.
extern "js" fn node_executable() -> String =
  #| () => process.execPath

///|
/// The fixture script. `moon test` runs in the module root.
extern "js" fn fixture_script() -> String =
  #| () => process.getBuiltinModule('node:path').resolve('worker/process/node/fixtures/worker.mjs')

///|
/// Creates a private directory with an empty `work` directory in it, or
/// returns "" when it cannot.
extern "js" fn make_test_directory() -> String =
  #| () => {
  #|   const fs = process.getBuiltinModule('node:fs'), os = process.getBuiltinModule('node:os'), path = process.getBuiltinModule('node:path');
  #|   try {
  #|     const directory = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'morphir-worker-test-'));
  #|     fs.mkdirSync(path.join(directory, 'work'));
  #|     return directory;
  #|   } catch { return ''; }
  #| }

///|
extern "js" fn join_path(directory : String, name : String) -> String =
  #| (directory, name) => process.getBuiltinModule('node:path').join(directory, name)

///|
extern "js" fn path_exists(path : String) -> Bool =
  #| (path) => process.getBuiltinModule('node:fs').existsSync(path)

///|
extern "js" fn process_alive(pid : Int32) -> Bool =
  #| (pid) => {
  #|   try { process.kill(pid, 0); return true; }
  #|   catch (error) { return error.code !== 'ESRCH'; }
  #| }

///|
extern "js" fn set_host_variable(name : String, value : String) -> Unit =
  #| (name, value) => { process.env[name] = value; }

///|
/// Writes the fixture worker once as a script that starts with `#!` and the
/// Node executable, so that Unix runs it without a shell. Returns its path.
extern "js" fn shebang_fixture() -> String =
  #| () => {
  #|   const fs = process.getBuiltinModule('node:fs'), os = process.getBuiltinModule('node:os'), path = process.getBuiltinModule('node:path');
  #|   if (globalThis.morphirShebangFixture) return globalThis.morphirShebangFixture;
  #|   const directory = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'morphir-worker-fixture-'));
  #|   const script = path.join(directory, 'fixture-worker.mjs');
  #|   const source = fs.readFileSync(path.resolve('worker/process/node/fixtures/worker.mjs'), 'utf8');
  #|   fs.writeFileSync(script, `#!${process.execPath}\n${source}`, {mode: 0o700});
  #|   process.once('exit', () => { try { fs.rmSync(directory, {recursive: true, force: true}); } catch {} });
  #|   return (globalThis.morphirShebangFixture = script);
  #| }

///|
/// Opens a marker file once and keeps it open while the tests run. Returns
/// its identity, `device:inode`.
extern "js" fn hold_marker() -> String =
  #| () => {
  #|   const fs = process.getBuiltinModule('node:fs'), os = process.getBuiltinModule('node:os'), path = process.getBuiltinModule('node:path');
  #|   if (globalThis.morphirMarker) return globalThis.morphirMarker;
  #|   const directory = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'morphir-worker-marker-'));
  #|   const fd = fs.openSync(path.join(directory, 'marker'), 'w+');
  #|   const stat = fs.fstatSync(fd, {bigint: true});
  #|   process.once('exit', () => { try { fs.closeSync(fd); fs.rmSync(directory, {recursive: true, force: true}); } catch {} });
  #|   return (globalThis.morphirMarker = `${stat.dev}:${stat.ino}`);
  #| }

///|
/// A staged artifact for tests that runs the Node executable in place. The
/// verified bytes are a marker, so the tests do not hash or copy Node.
fn test_staged() -> @process.StagedArtifact raise {
  let directory = make_test_directory()
  guard directory != "" else { fail("cannot create a test directory") }
  let marker = b"node fixture"
  let artifact = @worker.ArtifactRef::new(
    Memory(marker),
    @worker.Sha256::of(marker),
  )
  @process.VerifiedArtifact::check(marker, artifact).staged(
    directory~,
    executable=node_executable(),
    working_directory=join_path(directory, "work"),
  )
}

///|
/// The npm CLI's worker environment on Windows, as the README documents it:
/// `SystemRoot`, which the launcher passes, and the variables that libuv adds
/// to a child's environment on Windows when the host has them.
let windows_environment : Array[String] = [
  "SystemRoot", "HOMEDRIVE", "HOMEPATH", "LOGONSERVER", "PATH", "SYSTEMDRIVE", "TEMP",
  "USERDOMAIN", "USERNAME", "USERPROFILE", "WINDIR",
]

///|
/// The Node fixture for the shared conformance suite.
struct NodeFixture {}

///|
impl @conformance.Fixture for NodeFixture with fn start(
  _self,
  flags,
  args,
  limits,
) {
  let script = fixture_script()
  guard path_exists(script) else { fail("missing fixture worker \{script}") }
  let argv = flags.map(flag => flag.argument())
  argv.append(args)
  if host_is_windows() {
    // Windows cannot start a script without a shell; Node runs in place.
    NodeProcessChannel::start(test_staged(), [script, ..argv], limits~)
  } else {
    // The launcher's own staging, on a script that Unix runs directly.
    let staged = stage(file_artifact(shebang_fixture()))
    NodeProcessChannel::start(staged, argv, limits~)
  }
}

///|
impl @conformance.Fixture for NodeFixture with fn alive(_self, pid) {
  process_alive(pid)
}

///|
impl @conformance.Fixture for NodeFixture with fn ownership(_self) {
  match Tree::host() {
    Group => Group
    RootTree => RootTree
  }
}

///|
impl @conformance.Fixture for NodeFixture with fn documented_environment(_self) {
  match host_machine().map(machine => machine.os()) {
    Some(Windows) => windows_environment
    // macOS adds this variable to every process that has none.
    Some(MacOs) => ["__CF_USER_TEXT_ENCODING"]
    _ => []
  }
}

///|
impl @conformance.Fixture for NodeFixture with fn held_open(_self) {
  [hold_marker()]
}

///|
async test "Node process launcher passes the launcher conformance suite" {
  // The worker must not see the user's environment.
  set_host_variable("MORPHIR_HOME", "/home/user/.morphir")
  set_host_variable("MORPHIR_TEST_TOKEN", "secret")
  @conformance.check(NodeFixture::{ })
}

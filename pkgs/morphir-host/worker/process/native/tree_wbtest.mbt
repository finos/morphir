///|
/// A tree that the host signals but that never reports itself gone, like a
/// process stuck in the kernel.
priv struct Stuck {
  inner : &Tree
}

///|
impl Tree for Stuck with fn terminate(self) {
  self.inner.terminate()
}

///|
impl Tree for Stuck with fn kill(self) {
  self.inner.kill()
}

///|
impl Tree for Stuck with fn state(_self) {
  Live
}

///|
impl Tree for Stuck with fn release(self) {
  self.inner.release()
}

///|
#cfg(not(platform="windows"))
async test "a tree that cannot be confirmed gone is an unconfirmed stop" {
  let path = @fs.realpath("worker/process/native/fixtures/worker.sh")
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Posix)),
    @worker.Sha256::of(@fs.read_file(path).binary()),
  )
  let staged = stage(artifact)
  let spawned = spawn(staged, ["stubborn"])
  let channel = ProcessChannel::new(
    { ..spawned, tree: Stuck::{ inner: spawned.tree, }, },
    staged,
    @worker.Limits::host(),
    grace_ms=2000,
    confirm_ms=300,
  )
  let stop = channel.abort(Deadline)
  assert_true(stop.status is Unconfirmed(Deadline))
  // The host keeps the private directory while the tree may still use it.
  assert_true(@fs.exists(staged.directory()))
  assert_true(spawned.tree.state() is Gone)
  unstage(staged)
}

///|
async test "stop_tree kills a tree that outlives the gentle step" {
  let calls = []
  let tree : &Tree = Stuck::{ inner: Recorder::{ calls, }, }
  let confirmed = stop_tree(tree, _ => false, confirm_ms=20)
  assert_true(!confirmed)
  assert_eq(calls, ["terminate", "kill"])
}

///|
priv struct Recorder {
  calls : Array[String]
}

///|
impl Tree for Recorder with fn terminate(self) {
  self.calls.push("terminate")
}

///|
impl Tree for Recorder with fn kill(self) {
  self.calls.push("kill")
}

///|
impl Tree for Recorder with fn state(_self) {
  Gone
}

///|
impl Tree for Recorder with fn release(_self) {
  ()
}

///|
/// A tree whose members exit `delay_ms` after the gentle step, as processes
/// that clean up on `SIGTERM` do. It counts the checks of its state.
priv struct Slow {
  calls : Array[String]
  delay_ms : Int64
  mut gone_at : Int64?
  mut checks : Int32
}

///|
fn Slow::new(calls : Array[String], delay_ms~ : Int64) -> Slow {
  { calls, delay_ms, gone_at: None, checks: 0, }
}

///|
impl Tree for Slow with fn terminate(self) {
  self.calls.push("terminate")
  self.gone_at = Some(@async.now() + self.delay_ms)
}

///|
impl Tree for Slow with fn kill(self) {
  self.calls.push("kill")
  self.gone_at = Some(@async.now())
}

///|
impl Tree for Slow with fn state(self) {
  self.checks += 1
  match self.gone_at {
    Some(time) if @async.now() >= time => Gone
    _ => Live
  }
}

///|
impl Tree for Slow with fn release(_self) {
  ()
}

///|
async test "stop_tree gives the rest of the tree time to exit after the leader" {
  let calls = []
  let tree = Slow::new(calls, delay_ms=50L)
  // The leader exits at once; its grandchild needs 50 ms after SIGTERM.
  assert_true(stop_tree(tree, _ => true, confirm_ms=1000))
  assert_eq(calls, ["terminate"])
}

///|
async test "stop_tree kills members that outlive the leader's grace" {
  let calls = []
  let tree = Slow::new(calls, delay_ms=10000L)
  let started = @async.now()
  assert_true(stop_tree(tree, _ => true, confirm_ms=1000))
  assert_eq(calls, ["terminate", "kill"])
  assert_true(@async.now() - started >= TERM_GRACE_MS.to_int64())
}

///|
async test "the confirmation polls less often while a tree stays" {
  let tree = Slow::new([], delay_ms=10000L)
  Tree::terminate(tree)
  assert_false(confirm_gone(tree, confirm_ms=300))
  // At a fixed 5 ms the confirmation would check about 60 times.
  assert_true(tree.checks <= 15, msg="\{tree.checks} checks")
}

///|
/// After the first, gentle stop step, the leader gets this long before the
/// host kills the whole tree.
pub const TERM_GRACE_MS : Int32 = 200

///|
/// The first pause between two checks of whether a stopped tree is gone.
/// Each pause doubles, to at most `CONFIRM_POLL_MAX_MS`: on Linux a check
/// reads the status of every process in `/proc`.
const CONFIRM_POLL_MS : Int32 = 5

///|
/// The longest pause between two checks of whether a stopped tree is gone.
const CONFIRM_POLL_MAX_MS : Int32 = 50

///|
/// After the tree has stopped, the host reads the rest of stderr for at most
/// this long.
const STDERR_FINISH_MS : Int32 = 200

///|
/// Whether a worker's process tree still runs. A tree with only zombies left
/// is gone: a zombie runs no code and holds no open file.
priv enum TreeState {
  Gone
  Live
  Unknown(Int32)
}

///|
/// What the host can do to the process tree of one worker. The Unix tree is a
/// process group and the Windows tree is a job object.
priv trait Tree {
  /// The first stop step: `SIGTERM` to the group, or job termination.
  fn terminate(Self) -> Unit
  /// The last stop step: `SIGKILL` to the group, or job termination.
  fn kill(Self) -> Unit
  fn state(Self) -> TreeState
  /// Closes the host's handles to the tree, after it stopped.
  fn release(Self) -> Unit
}

///|
/// Polls until the tree is gone or `confirm_ms` passes.
async fn confirm_gone(tree : &Tree, confirm_ms~ : Int32) -> Bool noraise {
  let deadline = @async.now() + confirm_ms.to_int64()
  let mut pause = CONFIRM_POLL_MS
  while tree.state() is (Live | Unknown(_)) {
    let left = deadline - @async.now()
    if left <= 0L {
      return false
    }
    @async.sleep(@cmp.minimum(pause.to_int64(), left).to_int())
    pause = @cmp.minimum(pause * 2, CONFIRM_POLL_MAX_MS)
  }
  true
}

///|
/// Stops a tree: the gentle step, `TERM_GRACE_MS` for the leader and then
/// `TERM_GRACE_MS` for the rest of the tree, the kill step if a process
/// remains, and the confirmation. `leader_exited` waits at most the given
/// time for the leader to exit and reaps it.
async fn stop_tree(
  tree : &Tree,
  leader_exited : async (Int32) -> Bool noraise,
  confirm_ms~ : Int32,
) -> Bool noraise {
  tree.terminate()
  if !leader_exited(TERM_GRACE_MS) ||
    !confirm_gone(tree, confirm_ms=TERM_GRACE_MS) {
    tree.kill()
  }
  ignore(leader_exited(confirm_ms))
  confirm_gone(tree, confirm_ms~)
}

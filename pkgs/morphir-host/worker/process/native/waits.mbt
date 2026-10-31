///|
/// The exit status of a worker's leader process. Callers take turns, so one
/// `waitpid` runs at a time, and the first status found is kept for every
/// later call. A cancelled or expired wait leaves the leader to the next
/// caller.
priv struct Leader {
  pid : Int32
  turn : @async.Mutex
  mut status : Int32?
}

///|
fn Leader::new(pid : Int32) -> Leader {
  { pid, turn: @async.Mutex(), status: None, }
}

///|
/// Waits at most `ms` for the leader to exit. The wait reaps it. The status
/// is the exit code, or the negative signal number.
async fn Leader::wait_for(self : Leader, ms : Int32) -> Int32? noraise {
  if self.status is Some(_) {
    return self.status
  }
  let waited = @async.with_timeout_opt(ms, () => self.reap()) catch {
    _ => None
  }
  match waited {
    Some(status) => status
    None => None
  }
}

///|
/// Waits for the leader to exit, with no bound, and reaps it.
async fn Leader::wait(self : Leader) -> Int32? noraise {
  if self.status is Some(_) {
    return self.status
  }
  self.reap() catch {
    _ => None
  }
}

///|
/// Takes the turn and reaps the leader, unless an earlier caller did.
async fn Leader::reap(self : Leader) -> Int32? {
  self.turn.acquire()
  defer self.turn.release()
  if self.status is None {
    self.status = Some(@process.wait_pid(self.pid))
  }
  self.status
}

///|
/// Reads a worker's stderr into its tail. Callers take turns, so one task
/// reads the pipe at a time; a cancelled reader leaves the rest to the next
/// caller.
priv struct StderrDrain {
  errors : &@io.Reader
  buffer : @shared.StderrBuffer
  turn : @async.Mutex
  mut ended : Bool
}

///|
fn StderrDrain::new(errors : &@io.Reader) -> StderrDrain {
  {
    errors,
    buffer: @shared.StderrBuffer::new(),
    turn: @async.Mutex(),
    ended: false,
  }
}

///|
/// Reads until the end of stderr. A read error ends the drain too: stderr is
/// diagnostics only.
async fn StderrDrain::run(self : StderrDrain) -> Unit noraise {
  if self.ended {
    return
  }
  self.turn.acquire()
  defer self.turn.release()
  while !self.ended {
    let chunk = self.errors.read_some(max_len=READ_CHUNK_BYTES) catch {
      _ => None
    }
    match chunk {
      Some(bytes) => self.buffer.write(bytes)
      None => self.ended = true
    }
  }
}

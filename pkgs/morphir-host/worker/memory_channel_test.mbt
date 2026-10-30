///|
fn request(id : Int32) -> @worker.Message {
  @worker.Message::new({ "jsonrpc": "2.0", "id": id, "method": "morphir.ping" })
}

///|
async test "messages arrive in the order they were sent" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  channel.send(request(1))
  channel.send(request(2))
  assert_eq(worker.receive().json(), request(1).json())
  assert_eq(worker.receive().json(), request(2).json())
  worker.send(request(3))
  worker.send(request(4))
  assert_eq(channel.receive().json(), request(3).json())
  assert_eq(channel.receive().json(), request(4).json())
}

///|
async test "a receive waits for the peer" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let message = worker.receive()
      worker.send(message)
    })
    channel.send(request(7))
    assert_eq(channel.receive().json(), request(7).json())
  })
}

///|
async test "a worker that exits ends the stream after its last message" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  worker.send(request(1))
  worker.exit(code=0)
  assert_eq(channel.receive().json(), request(1).json())
  guard (Ok(channel.receive()) catch { e => Err(e) })
    is Err(@worker.WorkerClosed) else {
    fail("read past the end of the stream")
  }
  guard (Ok(channel.send(request(2))) catch { e => Err(e) })
    is Err(@worker.WorkerClosed) else {
    fail("wrote to an exited worker")
  }
}

///|
async test "close waits for the worker to exit and keeps its stderr" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      guard (Ok(worker.receive()) catch { e => Err(e) })
        is Err(@worker.WorkerClosed) else {
        fail("worker did not see the end of its input")
      }
      worker.write_stderr(b"bye")
      worker.exit(code=3)
    })
    let stop = channel.close()
    assert_eq(stop.status, Exited(code=3))
    assert_eq(stop.stop_method, ExitedAfterExit)
    assert_true(stop.stderr.bytes() == b"bye")
  })
  guard (Ok(channel.send(request(1))) catch { e => Err(e) })
    is Err(@worker.Stopped) else {
    fail("sent on a closed channel")
  }
}

///|
async test "close stops a worker that ignores exit after the grace period" {
  let (channel, _worker) = @worker.MemoryChannel::pair(grace_ms=10)
  let stop = channel.close()
  assert_eq(stop.status, Terminated(GraceExpired))
  assert_eq(stop.stop_method, ThreadTermination)
}

///|
async test "abort stops the worker at once" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  channel.send(request(1))
  let stop = channel.abort(Deadline)
  assert_eq(stop.status, Terminated(Deadline))
  guard (Ok(channel.receive()) catch { e => Err(e) }) is Err(@worker.Stopped) else {
    fail("received after abort")
  }
  guard (Ok(worker.receive()) catch { e => Err(e) })
    is Err(@worker.WorkerClosed) else {
    fail("worker kept its input after abort")
  }
  guard (Ok(worker.send(request(2))) catch { e => Err(e) })
    is Err(@worker.Stopped) else {
    fail("an aborted worker could still send")
  }
  // A second stop reports the first one.
  assert_eq(channel.close(), stop)
}

///|
async test "an abort during the close grace period wins" {
  let (channel, _worker) = @worker.MemoryChannel::pair(grace_ms=5000)
  let started = @async.now()
  @async.with_task_group(group => {
    let closing = group.spawn(() => channel.close())
    group.spawn_bg(() => {
      @async.sleep(20)
      ignore(channel.abort(Deadline))
    })
    let stop = closing.wait()
    assert_eq(stop.status, Terminated(Deadline))
  })
  // The abort woke the close; it did not wait for the grace period.
  assert_true(@async.now() - started < 2000L)
  assert_eq(channel.close().status, Terminated(Deadline))
}

///|
async test "a cancelled receive raises the cancellation, not a channel error" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let converted = Ref(false)
  let result = @async.with_timeout_opt(20, () => {
    channel.receive() catch {
      @worker.WorkerClosed | @worker.Stopped as error => {
        converted.val = true
        raise error
      }
      error => raise error
    }
  })
  assert_true(result is None)
  assert_false(converted.val)
  // The channel is still usable: the cancellation was not a stop.
  worker.send(request(9))
  assert_eq(channel.receive().json(), request(9).json())
}

///|
async test "a launcher returns a channel for a specification" {
  let (channel, worker) = @worker.MemoryChannel::pair()
  let launcher = @worker.MemoryLauncher::new(channel)
  let spec = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(b"guest"), @worker.Sha256::of(b"guest")),
    Wasm(abi=Some(MorphirBytesV1)),
  )
  let launched : &@worker.Channel = launcher.launch(spec)
  launched.send(request(5))
  assert_eq(worker.receive().json(), request(5).json())
  guard (Ok(launcher.launch(spec)) catch { e => Err(e) })
    is Err(@worker.LaunchFailed(_)) else {
    fail("launched a second worker from one channel")
  }
}

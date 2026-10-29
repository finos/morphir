///|
async test "desktop embedder shutdown revokes files then confirms execution cleanup" {
  @async.with_task_group(group => {
    let events = []
    let execution : Ref[@async.Task[Unit]?] = Ref(None)
    let entered = Ref(false)
    let changed = @async.CondVar::Cond()
    let memory = @logging.MemoryLogger::new()
    let host = @desktop_host.create(
      @configuration.build([]),
      memory,
      start_workspace=fn() { events.push("workspace.start") },
      stop_workspace=fn() { events.push("workspace.stop") },
      start_executions=fn() {
        events.push("executions.start")
        execution.val = Some(
          group.spawn(async fn() {
            entered.val = true
            changed.broadcast()
            defer events.push("execution.end")
            @async.sleep(60000)
          }),
        )
      },
      stop_executions=() => {
        guard execution.val is Some(task) else { fail("missing execution") }
        task.cancel()
        task.wait() catch {
          @async.WaitedTaskAlreadyCancelled => ()
          error => raise error
        }
        events.push("executions.stop")
      },
    )
    let controller = @desktop_host.start(group, host)
    while !entered.val {
      changed.wait()
    }
    let outcome = controller.shutdown()
    assert_true(outcome.stop_reason() is Embedder)
    assert_eq(outcome.exit_code().to_int(), 0)
    assert_eq(outcome.failures().length(), 0)
    assert_eq(events, [
      "executions.start", "workspace.start", "workspace.stop", "execution.end", "executions.stop",
    ])
    ignore(controller.shutdown())
    assert_eq(events.length(), 5)
    assert_eq(memory.events().length(), 4)
  })
}

///|
async test "desktop startup failure stops started services and returns without waiting for readiness" {
  @async.with_task_group(group => {
    let events = []
    let host = @desktop_host.create(
      @configuration.build([]),
      @logging.null_logger(),
      start_workspace=() => fail("controlled startup failure"),
      stop_workspace=fn() { events.push("workspace.stop") },
      start_executions=fn() { events.push("executions.start") },
      stop_executions=fn() { events.push("executions.stop") },
    )
    let refused = try {
      ignore(@desktop_host.start(group, host))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
    assert_eq(events, ["executions.start", "executions.stop"])
  })
}

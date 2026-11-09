///|
#cfg(target="native")
test "unselected originals observer forwards the hosted stop callback" {
  if !process_supported() {
    return
  }
  let root = temporary()
  defer remove_dir(root)
  let ready = root + "/ready"
  defer remove_file(ready)
  let owner = originals_observer_start()
  defer owner.finish()
  let launches : Array[String] = []
  let launch_scope = ProcessScope::install(program => launches.push(program))
  defer launch_scope.close()
  let stop = InterruptionScope::install(() => {
    (kind(ready) catch { _ => 0 }) == 1
  })
  defer stop.close()
  let started = monotonic_seconds()
  let result = owner.process(
    "sh",
    [
      "-c",
      "trap 'printf stopped; exit 0' INT; touch '" +
      ready +
      "'; while :; do sleep 0.01; done",
    ],
    root,
    "",
    2000,
  )
  assert_true(monotonic_seconds() - started < 1.5)
  assert_eq(launches, ["sh"])
  assert_true(
    result is Object(fields) &&
    fields.get("exitCode") == Some(Json(0)) &&
    fields.get("stdout") == Some(Json("stopped")),
  )
}

///|
#cfg(not(target="wasm-gc"))
test "host interruption scopes restore the enclosing state and close once" {
  let outer = InterruptionScope::install(() => false)
  defer outer.close()
  assert_false(interruption_requested())
  let inner = InterruptionScope::install(() => true)
  assert_true(interruption_requested())
  inner.close()
  assert_false(interruption_requested())
  inner.close()
  assert_false(interruption_requested())
}

///|
#cfg(any(target="native", target="js"))
test "blocking child waits poll the host state and reclaim the child" {
  if system_type() == "windows" {
    return
  }
  let root = temporary()
  defer remove_dir(root)
  let pid_file = root + "/owned.pid"
  let script = root + "/owned.sh"
  defer remove_file(script)
  defer remove_file(pid_file)
  write(
    script,
    "trap 'exit 0' INT\necho $$ > '" +
    pid_file +
    "'\nwhile :; do sleep 0.01; done\n",
  )
  let started = monotonic_seconds()
  let scope = InterruptionScope::install(() => {
    (kind(pid_file) catch { _ => 0 }) == 1
  })
  defer scope.close()
  let reply = process("sh", [script], root, "", 1000)
  assert_true(monotonic_seconds() - started < 3.0)
  assert_true(interruption_requested())
  assert_true(
    reply is Object(fields) && fields.get("exitCode") == Some(Json::number(0.0)),
  )
  assert_eq(kind(pid_file), 1)
  let pid = read(pid_file).trim().to_owned()
  scope.close()
  let gone = process("kill", ["-0", pid], root, "", 1000)
  assert_true(
    gone is Object(fields) && fields.get("exitCode") == Some(Json::number(1.0)),
  )
}

///|
#cfg(any(target="native", target="js"))
test "directory enumeration polls the same typed host state" {
  let root = temporary()
  defer remove_dir(root)
  write(root + "/child", "data")
  defer remove_file(root + "/child")
  let scope = InterruptionScope::install(() => true)
  defer scope.close()
  let refused = try {
    ignore(list_bounded(root, 100))
    false
  } catch {
    Interrupted => true
    _ => false
  }
  assert_true(refused)
  // Finalizers still use the ordinary list API after a retained stop. They
  // must be able to enumerate scratch without consuming the stop request.
  assert_eq(list(root), ["child"])
  assert_true(interruption_requested())
}

///|
#cfg(any(target="js", target="native"))
test "process adapters preserve opaque argv and report one owned launch" {
  if system_type() == "windows" && !process_supported() {
    return
  }
  let root = temporary()
  defer remove_dir(root)
  let launches : Array[String] = []
  let scope = ProcessScope::install(program => launches.push(program))
  defer scope.close()
  let result = process(
    "node",
    [
      "-e", "process.stdout.write(JSON.stringify(process.argv.slice(1)))", "--",
      "", "--json", "--", "a b", "",
    ],
    root,
    "",
    5000,
  )
  assert_eq(launches, ["node"])
  assert_true(
    result is Object(fields) &&
    fields.get("exitCode") == Some(Json::number(0.0)),
  )
  guard result is Object(fields) && fields.get("stdout") is Some(String(text)) else {
    fail("missing child output")
  }
  assert_eq(
    @json.parse(text),
    Json::array(["", "--json", "--", "a b", ""].map(Json::string)),
  )
  scope.close()
  scope.close()
  process_started("closed")
  assert_eq(launches, ["node"])
}

///|
#cfg(target="js")
test "Node process bridge retains timeout and spawn failure statuses" {
  let root = temporary()
  defer remove_dir(root)
  let result = process("node", ["-e", "setTimeout(()=>{},10000)"], root, "", 50)
  assert_true(
    result is Object(fields) &&
    fields.get("exitCode") == Some(Json::number(124.0)),
  )
  let absent = process(root + "/missing-program", [], root, "", 1000)
  assert_true(
    absent is Object(fields) &&
    fields.get("exitCode") == Some(Json::number(-1.0)),
  )
}

///|
#cfg(target="js")
test "Node process bridge bounds captured output without truncating valid output" {
  let root = temporary()
  defer remove_dir(root)
  let exact = process(
    "node",
    ["-e", "process.stdout.write('x'.repeat(16777216))"],
    root,
    "",
    5000,
  )
  guard exact is Object(fields) && fields.get("stdout") is Some(String(text)) else {
    fail("child result")
  }
  assert_eq(fields.get("exitCode"), Some(Json(0)))
  assert_eq(text.length(), 16777216)
  let over = process(
    "node",
    ["-e", "process.stdout.write('x'.repeat(16777217))"],
    root,
    "",
    5000,
  )
  guard over is Object(fields) && fields.get("stderr") is Some(String(message)) else {
    fail("bounded child result")
  }
  assert_eq(fields.get("exitCode"), Some(Json(-1)))
  assert_true(message.contains("Process output exceeds 16 MiB"))
}

///|
#cfg(any(target="js", target="native"))
test "a cooperative helper receives its cancel file before signal escalation" {
  if !process_supported() {
    return
  }
  let root = temporary()
  defer remove_dir(root)
  let ready = root + "/ready"
  let stop = root + "/stop"
  defer remove_file(ready)
  defer remove_file(stop)
  let host = InterruptionScope::install(() => {
    if (kind(ready) catch { _ => 0 }) == 1 {
      write(stop, "stop") catch {
        _ => ()
      }
      true
    } else {
      false
    }
  })
  defer host.close()
  let delivery = CooperativeProcessScope::install(() => {
    (kind(stop) catch { _ => 0 }) == 1
  })
  defer delivery.close()
  let result = process(
    "node",
    [
      "-e", "const fs=require('fs');process.on('SIGINT',()=>process.exit(99));fs.writeFileSync(process.argv[1],'ready');setInterval(()=>{if(fs.existsSync(process.argv[2]))process.exit(7)},5)",
      ready, stop,
    ],
    root,
    "",
    5000,
  )
  guard result is Object(fields) else { fail("process result") }
  assert_eq(fields.get("exitCode"), Some(Json(7)))
  delivery.close()
  delivery.close()
  assert_true(process_stop_delivery() is Signal)
}

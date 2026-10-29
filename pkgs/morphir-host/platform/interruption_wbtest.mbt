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

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
#cfg(target="native")
test "native blocking child waits poll the host state and reclaim the child" {
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
    "echo $$ > '" +
    pid_file +
    "'\ntrap 'exit 0' INT\nwhile :; do sleep 0.01; done\n",
  )
  let started = monotonic_seconds()
  let scope = InterruptionScope::install(() => {
    monotonic_seconds() - started >= 0.15
  })
  defer scope.close()
  let reply = process("sh", [script], root, "", 10000)
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
#cfg(target="native")
test "native directory enumeration polls the same host state" {
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
    _ => true
  }
  assert_true(refused)
}

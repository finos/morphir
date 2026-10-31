///|
fn load(
  bytes : Bytes,
  call~ : @guest.CallBounds = @guest.CallBounds::for_abi(MorphirBytesV1),
) -> &@guest.Guest {
  @guest.load(bytes, declared=MorphirBytesV1, call~) catch {
    error => abort("the guest did not load: \{@debug.to_string(error)}")
  }
}

///|
/// What one exchange gave: the reply, or the guest fault.
fn exchange(guest : &@guest.Guest, request : Bytes) -> String {
  let reply = guest.exchange(request) catch {
    @guest.Faulted(Trap(text)) => return "trap \{text}"
    @guest.Faulted(MemoryLimit(_)) => return "memory-limit"
    @guest.Faulted(CallDeadline) => return "call-deadline"
    @guest.Faulted(BudgetExhausted) => return "budget-exhausted"
    @guest.Faulted(Failure(text)) => return "failure \{text}"
  }
  match reply {
    Response(bytes) => "response " + (@utf8.decode(bytes) catch { _ => "?" })
    Notified => "notified"
    Exit => "exit"
  }
}

///|
test "byte callback adapter: a positive result is the response of that length" {
  let guest = load(@fixtures.echo_guest())
  assert_eq(exchange(guest, b"{\"id\":1}"), "response {\"id\":1}")
  // The instance persists between calls.
  assert_eq(exchange(guest, b"[2]"), "response [2]")
}

///|
test "byte callback adapter: 0 is exit, -2 a notification, -1 a failure" {
  assert_eq(exchange(load(@fixtures.constant_guest(0)), b"{}"), "exit")
  assert_eq(exchange(load(@fixtures.constant_guest(-2)), b"{}"), "notified")
  let failed = exchange(load(@fixtures.constant_guest(-1)), b"{}")
  assert_true(failed.has_prefix("failure") && failed.contains("-1"))
  // Any other result is a failure.
  assert_true(
    exchange(load(@fixtures.constant_guest(-3)), b"{}").has_prefix("failure"),
  )
}

///|
test "byte callback adapter: exit and failure end the guest" {
  let guest = load(@fixtures.constant_guest(0))
  assert_eq(exchange(guest, b"{}"), "exit")
  assert_true(exchange(guest, b"{}").has_prefix("failure"))
  let guest = load(@fixtures.constant_guest(-1))
  ignore(exchange(guest, b"{}"))
  assert_true(exchange(guest, b"{}").has_prefix("failure"))
}

///|
test "byte callback adapter: the result must equal the bytes written" {
  let written = @fixtures.writing_guest(b"ab", 3)
  assert_true(exchange(load(written), b"{}").has_prefix("failure"))
  // Output with exit or a notification is a failure.
  let written = @fixtures.writing_guest(b"ab", 0)
  assert_true(exchange(load(written), b"{}").has_prefix("failure"))
}

///|
test "byte callback adapter: requests and responses must be valid UTF-8" {
  assert_true(
    exchange(load(@fixtures.echo_guest()), b"\xff\xfe").has_prefix("failure"),
  )
  let written = @fixtures.writing_guest(b"\xc3", 1)
  assert_true(exchange(load(written), b"{}").has_prefix("failure"))
  // A multi-byte character in one response is valid.
  let written = @fixtures.writing_guest(b"\xc3\xa9", 2)
  assert_eq(exchange(load(written), b"{}"), "response é")
}

///|
test "a trap fails the call with the trap" {
  let trapped = exchange(load(@fixtures.trapping_guest()), b"{}")
  assert_true(trapped.has_prefix("trap"))
}

///|
test "memory ceiling: a growth beyond 256 MiB fails the call" {
  // The guest declares no maximum, so the rewrite gives it the ceiling.
  assert_eq(
    exchange(load(@fixtures.growing_guest(4096)), b"{}"),
    "memory-limit",
  )
  // A growth within the ceiling is granted.
  assert_eq(
    exchange(load(@fixtures.growing_guest(15)), b"{}"),
    "failure the guest returned 1, but wrote 0 bytes",
  )
}

///|
test "the loader refuses a module of another profile before instantiation" {
  let refused = try
    @guest.load(@fixtures.echo_guest(), declared=ExtismKernelV1)
  catch {
    AbiMismatch(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(refused)
  let refused = try @guest.load(b"\x00asm\x01\x00\x00\x00\x01") catch {
    LaunchFailed(text) => text.contains("not valid WASM")
    _ => false
  } noraise {
    _ => false
  }
  assert_true(refused)
}

///|
/// Runs a conversation over a guest in this thread: each message that the
/// conversation sends goes to the guest, and each response comes back as an
/// event, until the conversation finishes or waits for a call.
fn drive(
  guest : &@guest.Guest,
  conversation : @worker.Conversation,
  step : @worker.Step,
) -> (@worker.Conversation, @worker.Step) {
  let mut conversation = conversation
  let mut step = step
  while true {
    let sends = match step {
      Exchange(sends~, ..) | Activated(sends~, _) | Answered(sends~, _) => sends
      Finished(_, ..) => break
    }
    let mut next = None
    for message in sends {
      let event : @worker.Event = try guest.exchange(message.to_bytes()) catch {
        @guest.Faulted(fault) => ChannelFailed(GuestFailed(fault))
      } noraise {
        Response(bytes) =>
          Received(
            @worker.Message::parse(bytes) catch {
              error =>
                abort(
                  "the guest sent an invalid message: \{@debug.to_string(error)}",
                )
            },
          )
        Notified | Exit => continue
      }
      next = Some(conversation.on(event))
      if event is ChannelFailed(_) {
        break
      }
    }
    guard next is Some((after, after_step)) else { break }
    conversation = after
    step = after_step
  }
  (conversation, step)
}

///|
test "byte callback adapter: the portable MoonBit guest describes itself" {
  // `mise run package:mep-extension` writes the guest; the qualification
  // sets MORPHIR_PORTABLE_GUEST to its model.wasm.
  guard @env.get_env_var("MORPHIR_PORTABLE_GUEST") is Some(path) else { return }
  let bytes = @fs.read_file_to_bytes(path)
  // The guest uses SIMD, which both engines run.
  let guest = load(bytes)
  let (conversation, step) = @worker.Conversation::probe()
  let (_, step) = drive(guest, conversation, step)
  guard step is Finished(Described(description), ..) else {
    fail(
      "the portable guest did not describe itself: \{@debug.to_string(step)}",
    )
  }
  assert_true(
    description.claims.languages
    .iter()
    .any(claim => claim.language_id.to_string() == "moonbit"),
  )
}

///|
test "byte callback adapter: -2 for a request is a failure, not a wait" {
  let request = b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.extension.describe\"}"
  let failed = exchange(load(@fixtures.constant_guest(-2)), request)
  assert_true(failed.has_prefix("failure") && failed.contains("-2"))
  // A notification may still answer -2.
  assert_eq(
    exchange(
      load(@fixtures.constant_guest(-2)),
      b"{\"jsonrpc\":\"2.0\",\"method\":\"morphir.initialized\"}",
    ),
    "notified",
  )
}

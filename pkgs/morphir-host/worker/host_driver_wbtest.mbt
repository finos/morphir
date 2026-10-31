///|
test "a failed pipe becomes a transport fault event with its message" {
  guard channel_event(TransportFailed("the worker's stdin pipe failed: EPIPE"))
    is ChannelFailed(TransportFailed(message)) &&
    message == "the worker's stdin pipe failed: EPIPE" else {
    fail("a failed pipe was not a transport fault")
  }
}

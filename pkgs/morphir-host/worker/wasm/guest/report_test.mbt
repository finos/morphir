///|
fn report_of(events : Array[@guest.WorkerEvent]) -> Bytes {
  let lines = events.mapi((index, event) => {
    event.to_json(sequence=index + 1).stringify()
  })
  @utf8.encode(lines.join("\n") + "\n")
}

///|
test "worker report: each event is a morphir/command-event line" {
  let line = @guest.WorkerEvent::Exited(code=0).to_json(sequence=3)
  guard line
    is {
      "profile": "morphir/command-event",
      "contractVersion": "0.1.0",
      "command": "extension worker",
      "event": "exited",
      "sequence": 3,
      "exitCode": 0,
      ..
    } else {
    fail("not a command event: \{line.stringify()}")
  }
}

///|
test "worker report: the host reads the last fault after the guest's output" {
  let stderr = report_of([
    Output(Stdout(b"a fault in the text: {\"event\":\"fault\"}")),
    Fault(Trap("unreachable")),
  ])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(GuestFailed(Trap("unreachable"))),
  )
  for
    fault in [
      @worker.GuestFault::MemoryLimit("grow"),
      CallDeadline,
      BudgetExhausted,
      Failure("handle returned -1"),
    ] {
    assert_eq(
      @guest.WorkerEvent::ending_in(report_of([Fault(fault)])),
      Some(GuestFailed(fault)),
    )
  }
}

///|
test "worker report: a refusal is read with its code" {
  let stderr = report_of([
    Refused(code=WorkerRuntimeMismatch, message="the worker is build b"),
  ])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(Refused(code=WorkerRuntimeMismatch, message="the worker is build b")),
  )
}

///|
test "worker report: a worker that exited or wrote no report gives nothing" {
  assert_eq(@guest.WorkerEvent::ending_in(report_of([Exited(code=0)])), None)
  assert_eq(@guest.WorkerEvent::ending_in(b"plain text\n"), None)
  // A truncated first line, as at the start of a stderr tail, is skipped.
  let stderr = b"ted\":\"x\"}\n" + report_of([Fault(CallDeadline)])
  assert_eq(
    @guest.WorkerEvent::ending_in(stderr),
    Some(GuestFailed(CallDeadline)),
  )
}

///|
test "worker report: event messages are cut to 4 KiB, so a fault line always parses" {
  let long = "é".repeat(40000)
  let line = @guest.WorkerEvent::Fault(Failure(long))
    .to_json(sequence=1)
    .stringify()
  assert_true(@utf8.encode(line).length() < 8192)
  // The fault line is whole at the end of a 64 KiB tail of guest output.
  let flood = report_of(
    Array::make(40, @guest.WorkerEvent::Output(Stdout(@utf8.encode(long)))),
  )
  let stderr = flood[flood.length() - 65536 + 8192:].to_owned() +
    @utf8.encode(line + "\n")
  guard @guest.WorkerEvent::ending_in(stderr)
    is Some(GuestFailed(Failure(text))) else {
    fail("the fault line did not parse")
  }
  assert_true(text.has_prefix("éé"))
  assert_true(@utf8.encode(text).length() <= @guest.EVENT_MESSAGE_BYTES)
  // A refusal and an output are cut the same way.
  let refused = @guest.WorkerEvent::Refused(code=AbiUnsupported, message=long)
    .to_json(sequence=2)
    .stringify()
  assert_true(@utf8.encode(refused).length() < 8192)
  let output = @guest.WorkerEvent::Output(Log(Info, long))
    .to_json(sequence=3)
    .stringify()
  assert_true(@utf8.encode(output).length() < 8192)
  assert_true(
    @guest.WorkerEvent::Fault(Failure(long)).to_text().length() < 8192,
  )
}

///|
test "output tail: keeps the newest 64 KiB of guest output and counts the dropped bytes" {
  let tail = @guest.OutputTail::new()
  let block = Bytes::make(16384, b'a')
  for _ in 0..<10 {
    tail.push(Stdout(block))
  }
  let (kept, dropped) = tail.drain()
  // Each output is cut to 4 KiB when it is reported: 4,093 bytes of text and
  // `…`. The cut bytes count as dropped; 10 cut outputs fit in the tail.
  assert_eq(kept.length(), 10)
  assert_eq(dropped, 10L * (8L + 16384L - 4093L))
  // The tail is empty after a drain.
  assert_eq(tail.drain(), ([], 0L))
  // Over 64 KiB of reported text, the oldest outputs are dropped.
  for index in 0..<100 {
    tail.push(Log(Info, index.to_string()))
    tail.push(Stderr(block))
  }
  let (kept, dropped) = tail.drain()
  let shown = kept.fold(init=0, (sum, item) => {
    sum +
    @utf8.encode(
      @guest.WorkerEvent::Output(item).to_json(sequence=1).stringify(),
    ).length()
  })
  // The kept output events, with their JSON envelopes, stay near the bound.
  assert_true(shown <= @guest.OUTPUT_TAIL_BYTES + kept.length() * 160)
  assert_true(kept.length() < 200 && dropped > 0L)
  // The newest output is kept, cut to what its report shows, and its report
  // does not change.
  assert_eq(
    kept[kept.length() - 1],
    Stderr(Bytes::make(@guest.EVENT_MESSAGE_BYTES, b'a')),
  )
  assert_eq(
    @guest.WorkerEvent::Output(kept[kept.length() - 1]).to_text(),
    @guest.WorkerEvent::Output(Stderr(block)).to_text(),
  )
  // Control characters count as JSON escapes, so they cannot swell a report.
  tail.push(Stdout(Bytes::make(65536, b'\x00')))
  let (kept, _) = tail.drain()
  let line = @guest.WorkerEvent::Output(kept[0]).to_json(sequence=1).stringify()
  assert_true(@utf8.encode(line).length() < @guest.EVENT_MESSAGE_BYTES + 200)
  // The dropped count is an output event of its own.
  let event = @guest.WorkerEvent::OutputDropped(bytes=dropped).to_json(
    sequence=1,
  )
  guard event is { "event": "output", "droppedBytes": Number(count, ..), .. } else {
    fail("not an output event: \{event.stringify()}")
  }
  assert_eq(count.to_int64(), dropped)
}

///|
test "output tail: keeps only the cut payloads of large outputs" {
  let tail = @guest.OutputTail::new()
  let large = Bytes::make(1048576, b'b')
  let text = String::make(1048576, 'c')
  let outputs : Array[@guest.GuestOutput] = [
    Stdout(large),
    Stderr(large),
    Log(Info, text),
    MorphirLog(level=text, text),
    RefusedHttp(verb="GET", url=text),
  ]
  for _ in 0..<3 {
    for output in outputs {
      tail.push(output)
    }
  }
  let (kept, _) = tail.drain()
  assert_eq(kept.length(), 15)
  for index, item in kept {
    let payload = match item {
      Stdout(bytes) | Stderr(bytes) => bytes.length()
      Log(_, text) => @utf8.encode(text).length()
      MorphirLog(level~, text) =>
        @utf8.encode(level).length() + @utf8.encode(text).length()
      RefusedHttp(verb~, url~) =>
        @utf8.encode(verb).length() + @utf8.encode(url).length()
    }
    // The tail keeps at most what the report shows of each payload.
    assert_true(payload <= 2 * @guest.EVENT_MESSAGE_BYTES)
    // The report of the kept output is the report of the original output.
    assert_eq(
      @guest.WorkerEvent::Output(item).to_text(),
      @guest.WorkerEvent::Output(outputs[index % 5]).to_text(),
    )
  }
}

///|
test "instruction budget: new accepts 1 to 9007199254740991 and refuses 0, -1 and 9007199254740992" {
  for count in [1L, 2147483648L, 5000000000L, 9007199254740991L] {
    assert_eq(@worker.InstructionBudget::new(count).count, count)
  }
  for count in [0L, -1L, 9007199254740992L] {
    guard (Ok(@worker.InstructionBudget::new(count)) catch { e => Err(e) })
      is Err(InvalidLimit(text)) else {
      fail("accepted an instruction budget of \{count}")
    }
    assert_eq(text, "call_instructions=\{count}")
  }
}

///|
test "instruction budget: parse reads decimal digits from 1 to 9007199254740991" {
  let accepted = [
    ("1", 1L),
    ("007", 7L),
    ("2147483648", 2147483648L),
    ("5000000000", 5000000000L),
    ("9007199254740991", 9007199254740991L),
  ]
  for pair in accepted {
    let (text, count) = pair
    assert_eq(@worker.InstructionBudget::parse(text).count, count)
  }
  let refused = [
    "0", "-1", "9007199254740992", "9223372036854775808", "1e9", "x", "+5", "0x10",
    "0b101", "1_000", " 5", "5 ", "",
  ]
  for text in refused {
    guard (Ok(@worker.InstructionBudget::parse(text)) catch { e => Err(e) })
      is Err(InvalidLimit(_)) else {
      fail("parsed the instruction budget \{@debug.to_string(text)}")
    }
  }
}

///|
test "instruction budget: limits hold 5000000000 on the model line and 1000000000 on MEP 0.1 and for a probe" {
  let host = @worker.Limits::host()
  assert_eq(host.call_instructions, @worker.InstructionBudget::new(5000000000L))
  let legacy = host.for_session(Legacy, Wasm(abi=Some(MorphirBytesV1)))
  assert_eq(legacy.call_instructions.count, 1000000000L)
  assert_eq(host.for_probe().call_instructions.count, 1000000000L)
  assert_eq(
    @worker.ExtismProfile::restricted().instructions,
    legacy.call_instructions,
  )
}

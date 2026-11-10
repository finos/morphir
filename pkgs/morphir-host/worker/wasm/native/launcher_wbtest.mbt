///|
/// The value of an option in the arguments that start a worker.
fn option_of(args : Array[String], name : String) -> String? {
  for index, arg in args {
    if arg == name && index + 1 < args.length() {
      return Some(args[index + 1])
    }
  }
  None
}

///|
test "worker options: each protocol line gives its budget, its frame and the deadline of the ABI" {
  let identity = BuildIdentity::parse("a".repeat(64))
  let host = @worker.Limits::host()
  let tuple = @worker.ModelTuple::new(
    GenerateModel,
    MorphirIr,
    MorphirJson,
    V0_1_0Draft1,
    V4_0_0,
  )
  let start = (abi : @worker.WasmAbi, offer : @worker.Offer) => {
    worker_options(
      abi,
      "guest.wasm",
      identity,
      None,
      host.for_session(offer, Wasm(abi=Some(abi))),
    ).to_args()
  }
  let model = start(MorphirBytesV1, Model([tuple]))
  assert_eq(option_of(model, "--instructions"), Some("5000000000"))
  assert_eq(option_of(model, "--request-bytes"), Some("6291456"))
  assert_eq(option_of(model, "--call-ms"), Some("10000"))
  let model = start(ExtismKernelV1, Model([tuple]))
  assert_eq(option_of(model, "--instructions"), Some("5000000000"))
  assert_eq(option_of(model, "--call-ms"), Some("30000"))
  let legacy = start(ExtismKernelV1, Legacy)
  assert_eq(option_of(legacy, "--instructions"), Some("1000000000"))
  assert_eq(option_of(legacy, "--request-bytes"), Some("4194304"))
  assert_eq(option_of(legacy, "--call-ms"), Some("30000"))
  let probe = worker_options(
    MorphirBytesV1,
    "guest.wasm",
    identity,
    None,
    host.for_probe(),
  ).to_args()
  assert_eq(option_of(probe, "--instructions"), Some("1000000000"))
}

///|
test "worker options: the bounds of the launcher replace the bounds of the session" {
  let identity = BuildIdentity::parse("a".repeat(64))
  let call = @guest.CallBounds::new(
    deadline_ms=300,
    instructions=Some(@worker.InstructionBudget::new(1000)),
  )
  let args = worker_options(
    MorphirBytesV1,
    "guest.wasm",
    identity,
    Some(call),
    @worker.Limits::host(),
  ).to_args()
  assert_eq(option_of(args, "--instructions"), Some("1000"))
  assert_eq(option_of(args, "--call-ms"), Some("300"))
}

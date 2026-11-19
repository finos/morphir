///|
async fn read_stdin() -> Bytes {
  let scratch = FixedArray::make(4096, b'\x00')
  let output = @buffer.Buffer()
  while true {
    let count = @stdio.stdin.read_into(
      scratch,
      max_len=Int32::min(4096, 16385 - output.length()),
    )
    if count == 0 {
      break
    }
    require(count <= 16384 - output.length(), "Request exceeds 16384 bytes")
    output.write_bytes(Bytes::from_array(scratch[:count])[:])
  }
  output.to_bytes()
}

///|
async fn run() -> Unit {
  // argparse owns arguments, including --json. The protocol always emits JSON.
  ignore(
    @argparse.Command(
      "native-reader-adapter",
      disable_help_flag=true,
      disable_help_subcommand=true,
      disable_version_flag=true,
      flags=[@argparse.FlagArg("json")],
    ).parse(argv=@env.args()[1:], env=Map([])),
  )
  let request = read_request(read_stdin())
  let files = capture(request.root)
  require(
    snapshot_digest(files) == request.snapshot,
    "Snapshot digest mismatch",
  )
  let facts = observe(request, files)
  require(
    snapshot_digest(capture(request.root)) == request.snapshot,
    "Snapshot changed during reads",
  )
  let response = "{\"scope\":\"native-reader-adapter\",\"caseId\":" +
    @wire.text(request.case_id).stringify() +
    ",\"binding\":" +
    request.binding +
    ",\"facts\":" +
    facts.stringify() +
    "}"
  let bytes = @utf8.encode(response)
  require(bytes.length() <= 65536, "Response exceeds 65536 bytes")
  @stdio.stdout.write(bytes[:])
}

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write(@utf8.encode(error.to_string() + "\n")[:])
      @env.exit(1)
    }
  }
}

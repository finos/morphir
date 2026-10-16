///|
async fn checked(
  program : String,
  args : Array[String],
  cwd~ : String,
  environment~ : Map[String, String] = {},
) -> String {
  let (code, out, err) = @async.with_timeout(120000, async fn() {
    @process.collect_output(program, args, cwd~, extra_env=environment)
  })
  guard code == 0 else {
    fail(program + " " + args.join(" ") + "\n" + out.text() + err.text())
  }
  out.text()
}

///|
async fn digest(path : String, cwd : String) -> String {
  checked(
    "node",
    [
      "-e", "process.stdout.write(require('crypto').createHash('sha256').update(require('fs').readFileSync(process.argv[1])).digest('hex'))",
      path,
    ],
    cwd~,
  )
  .trim()
  .to_owned()
}

///|
async fn exchange(
  guest : String,
  root : String,
  bytes : Bytes,
) -> (Int32, Bytes, String) {
  let path = root + "/stdin.bin"
  @fs.write_file(path, bytes)
  let input = @process.redirect_from_file(path)
  let (code, out, err) = @async.with_timeout(10000, async fn() {
    @process.collect_output(guest, [], stdin=input, cwd=root)
  })
  (code, out.binary(), err.text())
}

///|
async fn process_cases(guest : String, root : String) -> Unit {
  let buffer = @buffer.Buffer::Buffer()
  let requests : Array[Json] = [
    {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "morphir.extension.describe",
      "params": { "protocolVersions": ["0.1"] },
    },
    { "jsonrpc": "2.0", "id": 2, "method": "morphir.extension.capabilities" },
    {
      "jsonrpc": "2.0",
      "id": 3,
      "method": "morphir.initialize",
      "params": {
        "protocolVersions": ["0.1"],
        "host": { "name": "acceptance", "version": "1" },
      },
    },
    { "jsonrpc": "2.0", "method": "morphir.initialized" },
    { "jsonrpc": "2.0", "id": 4, "method": "morphir.ping" },
    { "jsonrpc": "2.0", "id": 5, "method": "morphir.shutdown" },
    { "jsonrpc": "2.0", "id": 6, "method": "morphir.ping" },
    { "jsonrpc": "2.0", "method": "morphir.exit" },
  ]
  for request in requests {
    buffer.write_bytes(@mep.encode_frame(request.stringify())[:])
  }
  let (code, out, err) = exchange(guest, root, buffer.to_bytes())
  assert_eq(code, 0)
  assert_eq(err, "")
  let decoder = @mep.Decoder::new()
  let responses = decoder
    .feed(out)
    .map(body => @wire.parse_bounded(@utf8.decode(body[:])))
  decoder.finish()
  assert_eq(responses.length(), 6)
  assert_eq(
    @wire.field(@wire.field(responses[0], "result"), "claimsVersion"),
    Json::string("0.1.0-draft.2"),
  )
  for i in [1, 5] {
    assert_eq(
      @wire.field(@wire.field(responses[i], "error"), "code"),
      Json::number(-32014.0),
    )
  }
  assert_eq(
    @wire.field(@wire.field(responses[2], "result"), "protocolVersion"),
    Json::string("0.1"),
  )
  assert_eq(
    @wire.field(@wire.field(responses[3], "result"), "ok"),
    Json::boolean(true),
  )
  assert_eq(@fs.readdir(root, include_hidden=true), ["stdin.bin"])
  // Transport refusal must not leak diagnostics onto protocol stdout.
  for
    input in [
      b"Content-Length: 4\r\n\r\nx", b"Content-Length: 16777217\r\n\r\n", b"Content-Length: 1\r\nContent-Length: 1\r\n\r\nx",
      b"stdout log\r\n\r\n",
    ] {
    let (code, out, err) = exchange(guest, root, input)
    assert_true(code != 0)
    assert_eq(out, b"")
    assert_true(err.has_prefix("morphir-moonbit:"))
  }
}

///|
async fn installed_case(
  host : String,
  guest : String,
  platform : String,
  root : String,
  repository : String,
  evidence : String,
) -> Json {
  let home = root + "/home"
  let environment = { "MORPHIR_HOME": home }
  let host_call = async fn(args : Array[String]) {
    checked(host, ["--no-banner"] + args, cwd=root, environment~)
  }
  ignore(
    host_call([
      "extension",
      "bundle",
      "--executable",
      guest,
      "--extension-id",
      "morphir-moonbit",
      "--short-id",
      "moonbit",
      "--version",
      "0.1.0",
      "--platform",
      platform,
      "--output",
      root + "/bundle",
    ]),
  )
  ignore(host_call(["extension", "repository", "init", root + "/index"]))
  ignore(
    host_call([
      "extension",
      "repository",
      "add",
      "qualification",
      "--directory",
      root + "/index",
    ]),
  )
  ignore(
    host_call([
      "extension",
      "repository",
      "publish",
      "qualification",
      "--bundle",
      root + "/bundle",
    ]),
  )
  ignore(
    host_call([
      "extension", "install", "morphir-moonbit", "--repository", "qualification",
      "--version", "0.1.0",
    ]),
  )
  let catalog = @fs.read_file(home + "/catalog/extensions.json").json()
  let extensions = @wire.array(@wire.field(catalog, "extensions"))
  assert_eq(extensions.length(), 1)
  assert_eq(@wire.field(extensions[0], "claimCheck"), Json::string("probed"))
  assert_eq(@wire.field(extensions[0], "probeSource"), Json::string("describe"))
  let input = @fixtures.input()
  @fs.write_file(root + "/model.json", @ir_json.write(input))
  @fs.write_file(
    root + "/morphir.toml",
    "[project]\nname = \"example\"\nversion = \"0.0.0\"\nsource_directory = \"src\"\n[frontend]\nlanguage = \"moonbit\"\n",
  )
  ignore(
    host_call([
      "generate",
      "--target",
      "moonbit",
      "--input",
      root + "/model.json",
      "--output",
      root + "/generated",
      "--json",
    ]),
  )
  let expected = @generator.generate(@generator.Input::new("mep", input))
  for artifact in expected.artifacts {
    let actual = @fs.read_file(root + "/generated/" + artifact.path)
    match artifact.content {
      Text(text) => assert_eq(actual.text(), text)
      Binary(bytes) => {
        assert_eq(actual.binary(), bytes)
        assert_true(!@binary.read_binary(bytes[:]).is_empty())
      }
    }
  }
  // Use the checked-in SDK as an explicit workspace member. No SDK download.
  @fs.mkdir(root + "/consumer")
  @fs.write_file(
    root + "/consumer/moon.mod",
    "name = \"mep/consumer\"\nversion = \"0.0.0\"\nimport { " +
    Json::string(expected.project.module_name + "@0.0.0").stringify() +
    ", }\n",
  )
  @fs.write_file(
    root + "/consumer/moon.pkg",
    "pkgtype(kind: \"executable\")\nimport { " +
    Json::string(expected.project.module_name).stringify() +
    " @generated, }\n",
  )
  @fs.write_file(
    root + "/consumer/main.mbt",
    "///|\nfn main raise {\n  assert_true(@generated.ready())\n  assert_true(@generated.copy())\n  assert_true(!@generated.wanted())\n  println(\"Boolean consumer passed\")\n}\n",
  )
  let members = [
    root + "/generated",
    repository + "/pkgs/morphir-sdk",
    root + "/consumer",
  ]
  @fs.write_file(
    root + "/moon.work",
    "members = [" +
    members.map(p => Json::string(p).stringify()).join(",") +
    "]\n",
  )
  ignore(
    checked(
      "moon",
      ["build", "--target", "native", "generated", "consumer"],
      cwd=root,
    ),
  )
  let consumer = checked(
    "moon",
    ["run", "--target", "native", "consumer"],
    cwd=root,
  )
  assert_true(consumer.contains("Boolean consumer passed"))
  @fs.write_file(
    evidence + "/bundle-release.json",
    @fs.read_file(root + "/bundle/release.json"),
  )
  @fs.write_file(evidence + "/installed-catalog.json", catalog.stringify())
  @fs.write_file(
    evidence + "/symbols.ionb",
    @fs.read_file(root + "/generated/symbols.10n"),
  )
  @fs.write_file(evidence + "/model.json", @fs.read_file(root + "/model.json"))
  // The installed backend must also refuse an unsupported option through the real host.
  let (code, _, _) = @process.collect_output(
    host,
    [
      "--no-banner",
      "generate",
      "--target",
      "moonbit",
      "--input",
      root + "/model.json",
      "--option",
      "unknown=true",
      "--json",
    ],
    cwd=root,
    extra_env=environment,
  )
  assert_true(code != 0)
  {
    "installed": true,
    "claimCheck": "probed",
    "ionSidecarPreserved": true,
    "consumer": "passed",
    "unsupportedOptionsRefused": true,
  }
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 4 else {
    fail("guest, repository and evidence root required")
  }
  let guest = @fs.realpath(args[1])
  let repository = @fs.realpath(args[2])
  @fs.mkdir(args[3], recursive=true, allow_exist=true)
  let evidence = @fs.realpath(args[3])
  let root = @fs.tmpdir(prefix="morphir-mep-acceptance-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/process")
  process_cases(guest, root + "/process")
  let mut installation : Json = {
    "installed": false,
    "reason": "explicit pinned host not supplied",
  }
  let mut host_digest = ""
  let platform = @env.get_env_var("MORPHIR_MEP_PLATFORM").unwrap_or("")
  if @env.get_env_var("MORPHIR_MEP_HOST") is Some(path) {
    let host = @fs.realpath(path)
    guard @env.get_env_var("MORPHIR_MEP_HOST_SHA256") is Some(expected) &&
      expected.length() == 64 &&
      platform != "" else {
      fail("Explicit host SHA256 and platform are required")
    }
    host_digest = digest(host, repository)
    guard host_digest == expected else {
      fail("Host executable digest differs from its pin")
    }
    @fs.mkdir(root + "/installed")
    installation = installed_case(
      host,
      guest,
      platform,
      root + "/installed",
      repository,
      evidence,
    )
    assert_eq(digest(host, repository), host_digest)
  }
  let receipt : Json = {
    "profile": "morphir_moonbit_mep_p2_v1",
    "sourceRevision": checked("git", ["rev-parse", "HEAD"], cwd=repository)
    .trim()
    .to_owned(),
    "sourceDirty": checked("git", ["status", "--porcelain"], cwd=repository).trim() !=
    "",
    "guestSha256": digest(guest, repository),
    "hostSha256": host_digest,
    "platform": platform,
    "processCases": "passed",
    "installation": installation,
  }
  let ion = @ion_json.to_ion(receipt)
  @fs.write_file(evidence + "/receipt.ionb", @binary.write_binary([ion]))
  @fs.write_file(evidence + "/receipt.ion", @ion_text.write_ion(ion))
  @fs.write_file(evidence + "/receipt.json", receipt.stringify())
  println(receipt.stringify())
}

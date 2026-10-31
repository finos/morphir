///|
/// The refusal message of `host` for a process built for `platform`, or
/// `None` when the host admits it.
fn refusal(host : @worker.HostPlatform, platform : @worker.Platform) -> String? {
  try host.admit(Process(platform~, args=[])) catch {
    Refusal(code=PlatformMismatch, message~) => Some(message)
    Refusal(code~, ..) => Some("unexpected \{code}")
  } noraise {
    _ => None
  }
}

///|
test "a glibc Linux host runs a gnu artifact" {
  let machine = @worker.Machine::new(Linux, X86_64, libcs=[Glibc])
  assert_true(machine.runs(X86_64UnknownLinuxGnu))
  assert_eq(refusal(Native(machine), X86_64UnknownLinuxGnu), None)
}

///|
test "a musl-only Linux host runs a musl artifact" {
  let machine = @worker.Machine::new(Linux, Aarch64, libcs=[Musl])
  assert_true(machine.runs(Aarch64UnknownLinuxMusl))
  assert_eq(refusal(Node(machine), Aarch64UnknownLinuxMusl), None)
}

///|
test "a musl-only Linux host refuses a gnu artifact and names what it has" {
  let machine = @worker.Machine::new(Linux, X86_64, libcs=[Musl])
  assert_false(machine.runs(X86_64UnknownLinuxGnu))
  assert_eq(
    refusal(Native(machine), X86_64UnknownLinuxGnu),
    Some("this host runs x86_64 Linux with musl; the artifact needs glibc"),
  )
}

///|
test "a Linux host with both loaders runs gnu and musl artifacts" {
  let machine = @worker.Machine::new(Linux, X86_64, libcs=[Musl, Glibc, Musl])
  assert_eq(machine.libcs(), [Glibc, Musl])
  assert_eq(machine.platforms(), [X86_64UnknownLinuxGnu, X86_64UnknownLinuxMusl])
  assert_eq(machine.to_string(), "x86_64 Linux with glibc and musl")
}

///|
test "an architecture mismatch is refused" {
  let machine = @worker.Machine::new(Linux, X86_64, libcs=[Glibc, Musl])
  assert_false(machine.runs(Aarch64UnknownLinuxGnu))
  assert_eq(
    refusal(Native(machine), Aarch64UnknownLinuxGnu),
    Some(
      "this host runs x86_64 Linux with glibc and musl; the artifact is built for aarch64-unknown-linux-gnu",
    ),
  )
}

///|
test "macOS and Windows hosts run exactly their own triple" {
  let mac = @worker.Machine::of(Aarch64AppleDarwin)
  assert_eq(mac, @worker.Machine::new(MacOs, Aarch64))
  assert_eq(mac.platforms(), [Aarch64AppleDarwin])
  assert_eq(refusal(Native(mac), Aarch64AppleDarwin), None)
  assert_eq(
    refusal(Native(mac), X86_64AppleDarwin),
    Some(
      "this host runs aarch64 macOS; the artifact is built for x86_64-apple-darwin",
    ),
  )
  assert_eq(
    refusal(Native(mac), Aarch64UnknownLinuxGnu),
    Some(
      "this host runs aarch64 macOS; the artifact is built for aarch64-unknown-linux-gnu",
    ),
  )
  let windows = @worker.Machine::of(X86_64PcWindowsMsvc)
  assert_eq(windows.platforms(), [X86_64PcWindowsMsvc])
  assert_eq(windows.path_style(), Windows)
  assert_eq(refusal(Node(windows), X86_64PcWindowsMsvc), None)
  assert_true(refusal(Node(windows), Aarch64PcWindowsMsvc) is Some(_))
  // A C library environment belongs to Linux only.
  assert_eq(@worker.Machine::new(Windows, X86_64, libcs=[Glibc]), windows)
}

///|
test "each platform's own machine runs it" {
  for
    platform in [
      @worker.Platform::Aarch64AppleDarwin,
      X86_64AppleDarwin,
      Aarch64UnknownLinuxGnu,
      X86_64UnknownLinuxGnu,
      Aarch64UnknownLinuxMusl,
      X86_64UnknownLinuxMusl,
      Aarch64PcWindowsMsvc,
      X86_64PcWindowsMsvc,
    ] {
    assert_eq(@worker.Machine::of(platform).platforms(), [platform])
  }
}

///|
test "detection finds a C library from its dynamic loader only" {
  let under = (files : Array[String]) => (path : String) => files.contains(path)
  assert_eq(
    @worker.Machine::detect(
      Linux,
      X86_64,
      present=under(["/lib64/ld-linux-x86-64.so.2"]),
    ).libcs(),
    [Glibc],
  )
  assert_eq(
    @worker.Machine::detect(
      Linux,
      Aarch64,
      present=under(["/lib/ld-musl-aarch64.so.1"]),
    ).libcs(),
    [Musl],
  )
  assert_eq(
    @worker.Machine::detect(
      Linux,
      Aarch64,
      present=under(["/lib/ld-linux-aarch64.so.1", "/lib/ld-musl-aarch64.so.1"]),
    ).libcs(),
    [Glibc, Musl],
  )
  // The loader of another architecture does not count.
  let bare = @worker.Machine::detect(
    Linux,
    X86_64,
    present=under(["/lib/ld-musl-aarch64.so.1", "/lib/ld-linux-aarch64.so.1"]),
  )
  assert_eq(bare.libcs(), [])
  assert_eq(bare.platforms(), [])
  assert_eq(bare.to_string(), "x86_64 Linux with no C library loader")
  // macOS and Windows look at no files.
  assert_eq(
    @worker.Machine::detect(MacOs, X86_64, present=_ => abort("looked")),
    @worker.Machine::of(X86_64AppleDarwin),
  )
}

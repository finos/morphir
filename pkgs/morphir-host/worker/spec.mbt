///|
/// A SHA-256 digest: 64 lowercase hexadecimal digits.
pub struct Sha256 {
  priv hex : String
} derive(Eq, Debug)

///|
pub extend Sha256 with Eq::{equal, not_equal}

///|
pub extend Sha256 with @debug.Debug::{to_repr}

///|
pub fn Sha256::parse(text : String) -> Sha256 raise ValueError {
  guard text.length() == 64 &&
    text.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    raise InvalidSha256(text)
  }
  { hex: text, }
}

///|
/// The digest of bytes the host has already read.
pub fn Sha256::of(bytes : Bytes) -> Sha256 {
  { hex: @identity.sha256(bytes), }
}

///|
pub impl Show for Sha256 with fn output(self, logger) {
  logger.write_string(self.hex)
}

///|
pub extend Sha256 with Show::{to_string, output}

///|
/// How a host platform writes absolute paths.
pub(all) enum PathStyle {
  Posix
  Windows
} derive(Eq, Debug)

///|
pub extend PathStyle with Eq::{equal, not_equal}

///|
pub extend PathStyle with @debug.Debug::{to_repr}

///|
/// An absolute artifact location in the style of the host platform. A POSIX
/// path starts with `/`. A Windows path has a drive (`C:\x` or `C:/x`) or
/// names a server (`\\server\share`). Relative paths are refused because a
/// worker has no working directory of the caller; on Windows a root-relative
/// path (`\x`) and `\\` without a server are relative to the current drive.
pub struct ArtifactPath {
  priv text : String
} derive(Eq, Debug)

///|
pub extend ArtifactPath with Eq::{equal, not_equal}

///|
pub extend ArtifactPath with @debug.Debug::{to_repr}

///|
fn windows_absolute(text : String) -> Bool {
  match text.to_array()[:] {
    [c, ':', '\\' | '/', ..] => c.is_ascii_alphabetic()
    ['\\', '\\', .. rest] =>
      rest is [first, ..] && first != '\\' && first != '/'
    _ => false
  }
}

///|
pub fn ArtifactPath::parse(
  text : String,
  style : PathStyle,
) -> ArtifactPath raise ValueError {
  let absolute = match style {
    Posix => text.has_prefix("/")
    Windows => windows_absolute(text)
  }
  guard absolute && !text.contains_char('\u0000') else {
    raise InvalidArtifactPath(text)
  }
  { text, }
}

///|
pub impl Show for ArtifactPath with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ArtifactPath with Show::{to_string, output}

///|
/// Where the artifact bytes come from: a file, or bytes the caller already
/// holds, as in a browser host that has no file system.
pub(all) enum ArtifactSource {
  File(ArtifactPath)
  Memory(Bytes)
} derive(Eq, Debug)

///|
pub extend ArtifactSource with Eq::{equal, not_equal}

///|
pub extend ArtifactSource with @debug.Debug::{to_repr}

///|
/// An artifact and the digest its bytes must have when the host runs them.
pub struct ArtifactRef {
  source : ArtifactSource
  sha256 : Sha256
} derive(Eq, Debug)

///|
pub extend ArtifactRef with Eq::{equal, not_equal}

///|
pub extend ArtifactRef with @debug.Debug::{to_repr}

///|
pub fn ArtifactRef::new(
  source : ArtifactSource,
  sha256 : Sha256,
) -> ArtifactRef {
  { source, sha256, }
}

///|
/// A host platform that a process artifact is built for, named by its Rust
/// and LLVM target triple, as in release descriptors and
/// `MORPHIR_MEP_PLATFORM`.
pub(all) enum Platform {
  Aarch64AppleDarwin
  X86_64AppleDarwin
  Aarch64UnknownLinuxGnu
  X86_64UnknownLinuxGnu
  Aarch64UnknownLinuxMusl
  X86_64UnknownLinuxMusl
  Aarch64PcWindowsMsvc
  X86_64PcWindowsMsvc
} derive(Eq, Compare, Debug)

///|
pub extend Platform with Eq::{equal, not_equal}

///|
pub extend Platform with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Platform with @debug.Debug::{to_repr}

///|
let platforms : Array[Platform] = [
  Aarch64AppleDarwin,
  X86_64AppleDarwin,
  Aarch64UnknownLinuxGnu,
  X86_64UnknownLinuxGnu,
  Aarch64UnknownLinuxMusl,
  X86_64UnknownLinuxMusl,
  Aarch64PcWindowsMsvc,
  X86_64PcWindowsMsvc,
]

///|
/// Decodes a target triple. Only the eight triples above are accepted.
pub fn Platform::parse(text : String) -> Platform raise ValueError {
  match platforms.search_by(platform => platform.to_string() == text) {
    Some(index) => platforms[index]
    None => raise UnknownPlatform(text)
  }
}

///|
pub fn Platform::path_style(self : Platform) -> PathStyle {
  match self {
    Aarch64PcWindowsMsvc | X86_64PcWindowsMsvc => Windows
    _ => Posix
  }
}

///|
pub impl Show for Platform with fn output(self, logger) {
  logger.write_string(
    match self {
      Aarch64AppleDarwin => "aarch64-apple-darwin"
      X86_64AppleDarwin => "x86_64-apple-darwin"
      Aarch64UnknownLinuxGnu => "aarch64-unknown-linux-gnu"
      X86_64UnknownLinuxGnu => "x86_64-unknown-linux-gnu"
      Aarch64UnknownLinuxMusl => "aarch64-unknown-linux-musl"
      X86_64UnknownLinuxMusl => "x86_64-unknown-linux-musl"
      Aarch64PcWindowsMsvc => "aarch64-pc-windows-msvc"
      X86_64PcWindowsMsvc => "x86_64-pc-windows-msvc"
    },
  )
}

///|
pub extend Platform with Show::{to_string, output}

///|
/// The closed set of WASM guest ABIs the host can adapt.
pub(all) enum WasmAbi {
  ExtismKernelV1
  MorphirBytesV1
} derive(Eq, Debug)

///|
pub extend WasmAbi with Eq::{equal, not_equal}

///|
pub extend WasmAbi with @debug.Debug::{to_repr}

///|
pub fn WasmAbi::parse(text : String) -> WasmAbi raise ValueError {
  match text {
    "extism-kernel-v1" => ExtismKernelV1
    "morphir-bytes-v1" => MorphirBytesV1
    _ => raise UnknownWasmAbi(text)
  }
}

///|
pub impl Show for WasmAbi with fn output(self, logger) {
  logger.write_string(
    match self {
      ExtismKernelV1 => "extism-kernel-v1"
      MorphirBytesV1 => "morphir-bytes-v1"
    },
  )
}

///|
pub extend WasmAbi with Show::{to_string, output}

///|
/// How the host runs an artifact. Process arguments are opaque and are passed
/// to the worker unchanged. A WASM ABI, when declared, must agree with the
/// ABI classified from the module.
pub(all) enum WorkerRuntime {
  Process(platform~ : Platform, args~ : Array[String])
  Wasm(abi~ : WasmAbi?)
} derive(Eq, Debug)

///|
pub extend WorkerRuntime with Eq::{equal, not_equal}

///|
pub extend WorkerRuntime with @debug.Debug::{to_repr}

///|
/// The kind of a runtime, without its details.
pub fn WorkerRuntime::kind(self : WorkerRuntime) -> RuntimeKind {
  match self {
    Process(..) => Process
    Wasm(..) => Wasm
  }
}

///|
/// The kinds of worker a host can start.
pub(all) enum RuntimeKind {
  Process
  Wasm
} derive(Eq, Compare, Debug)

///|
pub extend RuntimeKind with Eq::{equal, not_equal}

///|
pub extend RuntimeKind with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend RuntimeKind with @debug.Debug::{to_repr}

///|
pub impl Show for RuntimeKind with fn output(self, logger) {
  logger.write_string(
    match self {
      Process => "process"
      Wasm => "wasm"
    },
  )
}

///|
pub extend RuntimeKind with Show::{to_string, output}

///|
/// The only input from which the host starts a worker. Its parts are
/// validated, so a specification always has a digest and exactly one runtime.
pub struct WorkerSpec {
  artifact : ArtifactRef
  runtime : WorkerRuntime
} derive(Eq, Debug)

///|
pub extend WorkerSpec with Eq::{equal, not_equal}

///|
pub extend WorkerSpec with @debug.Debug::{to_repr}

///|
pub fn WorkerSpec::new(
  artifact : ArtifactRef,
  runtime : WorkerRuntime,
) -> WorkerSpec {
  let runtime = match runtime {
    // A copy, so that the caller cannot change the arguments later.
    Process(platform~, args~) =>
      WorkerRuntime::Process(platform~, args=args.copy())
    Wasm(..) => runtime
  }
  { artifact, runtime, }
}

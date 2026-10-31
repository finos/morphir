///|
/// The version of the contract between a WASM launcher and its worker mode:
/// the arguments, the frames and the stderr report.
pub const WORKER_CONTRACT : String = "morphir-wasm-worker/0.1.0"

///|
/// The version of the host library that this worker mode belongs to.
const HOST_VERSION : String = "0.1.0"

///|
/// The version and the git commit of a CLI build. The build writes them
/// into a generated constant of the CLI's entry package
/// (`scripts/build-stamp.mbtx`), which gives them to the worker mode.
pub struct BuildStamp {
  version : String
  commit : String
} derive(Eq, Debug)

///|
pub extend BuildStamp with Eq::{equal, not_equal}

///|
pub extend BuildStamp with @debug.Debug::{to_repr}

///|
pub fn BuildStamp::new(version~ : String, commit~ : String) -> BuildStamp {
  { version, commit, }
}

///|
/// The identity of a CLI build for its worker mode: a SHA-256 over the worker
/// contract, the host version, the build's version and git commit, the
/// SHA-256 of the Extism kernel and the engine's features. The host passes
/// its identity, and a worker of another identity refuses to serve.
///
/// Limit: two builds of the same commit share an identity, also when one
/// of them has uncommitted changes, and an incremental build keeps the stamp
/// that its checkout's first build wrote. CI and release builds start from a
/// clean checkout, so their stamps are exact. The launcher runs a staged copy
/// of the executable that it hashed once, so a CLI replaced on disk while it
/// runs does not change the workers it starts.
pub struct BuildIdentity {
  priv digest : @worker.Sha256
} derive(Eq, Debug)

///|
pub extend BuildIdentity with Eq::{equal, not_equal}

///|
pub extend BuildIdentity with @debug.Debug::{to_repr}

///|
/// The identity of the build with this stamp.
pub fn BuildIdentity::current(stamp : BuildStamp) -> BuildIdentity {
  let features = @engine.Engine::default()
    .features()
    .map(feature => feature.name())
    .join(",")
  let text = "\{WORKER_CONTRACT}\nhost \{HOST_VERSION}\nversion \{stamp.version}\ncommit \{stamp.commit}\nkernel \{@kernel.sha256()}\nfeatures \{features}\n"
  { digest: @worker.Sha256::of(@utf8.encode(text)), }
}

///|
/// An identity in its text form, 64 lowercase hexadecimal digits.
pub fn BuildIdentity::parse(
  text : String,
) -> BuildIdentity raise @worker.ValueError {
  { digest: @worker.Sha256::parse(text), }
}

///|
pub impl Show for BuildIdentity with fn output(self, logger) {
  self.digest.output(logger)
}

///|
pub extend BuildIdentity with Show::{to_string, output}

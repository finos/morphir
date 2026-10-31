///|
/// The largest artifact that the host reads, hashes and copies: 512 MiB.
pub const ARTIFACT_LIMIT_BYTES : Int32 = 536870912

///|
/// Checks the size that a host found before it reads an artifact.
pub fn check_artifact_size(size : Int64) -> @worker.ArtifactProblem? {
  if size > ARTIFACT_LIMIT_BYTES.to_int64() {
    Some(TooLarge)
  } else {
    None
  }
}

///|
/// Bytes that a host read from an artifact and whose SHA-256 equals the
/// specification. Only `check` makes one, so a launcher cannot copy bytes
/// that nobody hashed.
pub struct VerifiedArtifact {
  priv bytes : Bytes
  priv digest : @worker.Sha256
  priv file_name : String
}

///|
/// The last segment of an artifact path, or `artifact` when it has no usable
/// name. A private copy keeps the name, so a Windows copy keeps `.exe`.
fn copy_name(source : @worker.ArtifactSource) -> String {
  guard source is File(path) else { return "artifact" }
  let text = path.to_string()
  let name = match text.rev_find("/") {
    Some(i) => text[i + 1:].to_owned()
    None => text
  }
  let name = match name.rev_find("\\") {
    Some(i) => name[i + 1:].to_owned()
    None => name
  }
  match name {
    "" | "." | ".." => "artifact"
    name => name
  }
}

///|
/// Hashes the bytes that were read and compares them with the artifact's
/// digest. A mismatch raises `DigestMismatch`, and nothing is copied.
pub fn VerifiedArtifact::check(
  bytes : Bytes,
  artifact : @worker.ArtifactRef,
) -> VerifiedArtifact raise @worker.LaunchError {
  if check_artifact_size(bytes.length().to_int64()) is Some(problem) {
    raise ArtifactUnreadable(problem)
  }
  let digest = @worker.Sha256::of(bytes)
  guard digest == artifact.sha256 else {
    raise DigestMismatch(expected=artifact.sha256, actual=digest)
  }
  { bytes, digest, file_name: copy_name(artifact.source), }
}

///|
pub fn VerifiedArtifact::bytes(self : VerifiedArtifact) -> Bytes {
  self.bytes
}

///|
pub fn VerifiedArtifact::digest(self : VerifiedArtifact) -> @worker.Sha256 {
  self.digest
}

///|
/// The file name of the private copy.
pub fn VerifiedArtifact::file_name(self : VerifiedArtifact) -> String {
  self.file_name
}

///|
/// The file name of the private copy on a host with path style `style`. On
/// Windows a name without an extension gets `.exe`: Windows starts a file by
/// its name only when the name has an extension, and both launchers start
/// the copy by name. A dot that starts or ends the name is not an extension.
pub fn VerifiedArtifact::copy_name(
  self : VerifiedArtifact,
  style : @worker.PathStyle,
) -> String {
  let name = self.file_name
  let has_extension = match name.rev_find(".") {
    Some(i) => i > 0 && i < name.length() - 1
    None => false
  }
  match style {
    Windows if !has_extension => name + ".exe"
    _ => name
  }
}

///|
/// The subdirectory of a private directory that holds the executable copy.
/// The copy has its own directory, so that no artifact name can collide with
/// `STAGED_WORK_DIRECTORY`.
pub const STAGED_BIN_DIRECTORY : String = "bin"

///|
/// The subdirectory of a private directory that is the worker's empty
/// working directory.
pub const STAGED_WORK_DIRECTORY : String = "work"

///|
/// A private copy of verified bytes. A launcher starts `executable` with
/// `working_directory` as its working directory and removes `directory`, which
/// holds both, after the worker's tree has stopped.
pub struct StagedArtifact {
  priv digest : @worker.Sha256
  priv directory : String
  priv executable : String
  priv working_directory : String
}

///|
/// Records where a host wrote the verified bytes. The host writes them before
/// it calls this, into a directory that only its user can use.
pub fn VerifiedArtifact::staged(
  self : VerifiedArtifact,
  directory~ : String,
  executable~ : String,
  working_directory~ : String,
) -> StagedArtifact {
  { digest: self.digest, directory, executable, working_directory, }
}

///|
fn join_path(
  directory : String,
  name : String,
  style : @worker.PathStyle,
) -> String {
  let separator = match style {
    Posix => "/"
    Windows => "\\"
  }
  if directory.has_suffix(separator) {
    directory + name
  } else {
    directory + separator + name
  }
}

///|
/// Records the private copy in the staging layout of `directory`: the copy is
/// `bin/<copy name>` (see `copy_name`) and the working directory is `work`. The host creates
/// both subdirectories and writes the verified bytes to the copy before it
/// calls this, into a directory that only its user can use.
pub fn VerifiedArtifact::stage_in(
  self : VerifiedArtifact,
  directory~ : String,
  style~ : @worker.PathStyle,
) -> StagedArtifact {
  let bin = join_path(directory, STAGED_BIN_DIRECTORY, style)
  self.staged(
    directory=directory.trim_end(chars=['/', '\\']).to_owned(),
    executable=join_path(bin, self.copy_name(style), style),
    working_directory=join_path(directory, STAGED_WORK_DIRECTORY, style),
  )
}

///|
pub fn StagedArtifact::digest(self : StagedArtifact) -> @worker.Sha256 {
  self.digest
}

///|
pub fn StagedArtifact::directory(self : StagedArtifact) -> String {
  self.directory
}

///|
pub fn StagedArtifact::executable(self : StagedArtifact) -> String {
  self.executable
}

///|
pub fn StagedArtifact::working_directory(self : StagedArtifact) -> String {
  self.working_directory
}

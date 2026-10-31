///|
// SHA-256 of the official versioned archives, retrieved 2026-10-31.
let core_digest : String = "30a8ae1c1e1e8fde478ea742cbc928c8f4ae1f5c00090afe3f10c97be9e5da64"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "fcd60842ff7b3dd28b2ec246f2264192effb5012009ff137e1722d41a45cf184"
    "linux-x86_64" =>
      "0e4cde1ace98e8ef00552a937738b59c6901c4b8a004ebad71ea0e63688f63f1"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}

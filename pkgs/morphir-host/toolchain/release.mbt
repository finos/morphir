///|
// SHA-256 of the official versioned archives, retrieved 2026-11-07.
let core_digest : String = "8ec2a2c01335501d703867bb4eef5f92d3cd7e1ae1ee5f7f14d54d16d2c7c2b5"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "3ccd56479ba704a779178abe8731490edee9e57b3b90f5cef2252afef4fdf130"
    "linux-x86_64" =>
      "80d987523308fa490eba9f1baf98df996a5a7891e118357553b7c2608c0597c5"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}

///|
// SHA-256 of the official versioned archives, retrieved 2026-10-28.
let core_digest : String = "2d837ecbef5933c09726d63682a7695123d622e6aee13525fbc98c4b49433714"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "39e02f7730486cea54d12e8e781d83a665f245f6a621d01e17a3a13f104eb437"
    "linux-x86_64" =>
      "d0a96eaf91c77cfcdd7b7df75390c5a1a95d0b8a328b1a5ed6fee050cfbf8d50"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}

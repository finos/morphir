///|
// SHA-256 of the official versioned archives, retrieved 2026-10-15.
let core_digest : String = "96d30f4dbcc6a9e1736ef26fbdd0e8fb0e97cb01d50e55d2a0072208b8061ae5"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "563109ff02c6dc77fdc74acd0be423964ef678dfea4d9b948c19d245dc8b0e83"
    "linux-x86_64" =>
      "24b93a5409d2a4fb8e3d1b84b473f27b63476cef4418094764df96cb26b03c09"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}

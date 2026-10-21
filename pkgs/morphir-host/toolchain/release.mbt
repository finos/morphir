///|
// SHA-256 of the official versioned archives, retrieved 2026-10-21.
let core_digest : String = "e7db6e3c80a97af953598b374cf14f3e330918b1ca4659b141b9f550c9c0adb0"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "6fe394f394a4e82939ecf3339660af6a15007e1cb74e7dceb04dcaea9442aa1e"
    "linux-x86_64" =>
      "84ae424cd31bc485d2cf4d3736534e52f2f265ceafb562a187b9ab26d9566212"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}

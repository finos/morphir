///|
/// Key shared by paths that can alias on a case-insensitive or normalizing
/// filesystem. Both inline and bounded generation use this collision policy.
pub fn artifact_path_key(path : String) -> String {
  @normalization.nfc(@casefold.casefold(@normalization.nfc(path)))
}

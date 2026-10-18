///|
pub fn notify(
  label : String,
  payload : FixedArray[Byte],
) -> Result[UInt32, String] {
  @host.observe(label, payload)
}

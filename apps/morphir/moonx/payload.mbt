///|
suberror UnpackagedPayload {
  MissingGeneratedPayload
}

///|
// Release packaging replaces this file with the candidate-bound Node assets.
// Source checkout execution can still show launcher help without those assets.
fn packaged_payload() -> @launcher.Payload raise UnpackagedPayload {
  raise MissingGeneratedPayload
}

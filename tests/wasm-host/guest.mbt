///|
let accepted_calls : Ref[UInt32] = Ref(0U)

///|
let closed : Ref[Bool] = Ref(false)

///|
pub fn exchange(
  input : @probe.Packet,
) -> Result[@probe.Packet, @probe.ProbeError] {
  if closed.val {
    Err(Closed)
  } else if input.payload.length() > 65536 {
    Err(Refused("payload exceeds 65536 bytes"))
  } else {
    accepted_calls.val += 1U
    Ok(input)
  }
}

///|
pub fn calls() -> UInt32 {
  accepted_calls.val
}

///|
pub fn close() -> Unit {
  closed.val = true
}

///|
pub fn trap() -> Unit {
  panic()
}

///|
pub fn spin() -> Unit {
  while true {

  }
}

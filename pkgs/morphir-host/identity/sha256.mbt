///|
fn rotate(value : UInt32, bits : Int32) -> UInt32 {
  (value >> bits) | (value << (32 - bits))
}

///|
/// SHA-256 for bounded, already buffered pipeline snapshots.
pub fn sha256(bytes : Bytes) -> String {
  let constants : Array[UInt32] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  let state : Array[UInt32] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let length = (bytes.length() + 9 + 63) / 64 * 64
  let data = FixedArray::make(length, 0U)
  for i in 0..<bytes.length() {
    data[i] = bytes[i].to_uint()
  }
  data[bytes.length()] = 128U
  let bits = bytes.length().to_uint64() * 8UL
  for i in 0..<8 {
    data[length - 1 - i] = ((bits >> (i * 8)) & 255UL).to_uint()
  }
  let words = FixedArray::make(64, 0U)
  for block = 0; block < length; block = block + 64 {
    for i in 0..<16 {
      let offset = block + i * 4
      words[i] = (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3]
    }
    for i in 16..<64 {
      let x = words[i - 15]
      let y = words[i - 2]
      words[i] = words[i - 16] +
        (rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3)) +
        words[i - 7] +
        (rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10))
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for i in 0..<64 {
      let t1 = h +
        (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
        ((e & f) ^ (e.lnot() & g)) +
        constants[i] +
        words[i]
      let t2 = (rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) +
        ((a & b) ^ (a & c) ^ (b & c))
      h = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    state[0] += a
    state[1] += b
    state[2] += c
    state[3] += d
    state[4] += e
    state[5] += f
    state[6] += g
    state[7] += h
  }
  let digits = "0123456789abcdef".to_array()
  let mut output = ""
  for word in state {
    for i = 7; i >= 0; i = i - 1 {
      output += digits[((word >> (i * 4)) & 15U).reinterpret_as_int()].to_string()
    }
  }
  output
}

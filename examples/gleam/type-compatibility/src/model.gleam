//// Types shared with other Morphir languages.

/// A customer represented by a labelled Gleam record constructor.
pub type Customer(a) {
  Customer(name: String, details: a)
}

pub type CustomerId = Int
pub opaque type Secret { Secret(String) }

/// A discriminated union with a different payload for each variant.
pub type Outcome(a) {
  Pending
  Succeeded(value: a)
  Failed(message: String, code: Int)
}

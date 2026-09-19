pub fn prepend(values: List(Int)) -> List(Int) {
  let first = 1
  [first, ..values]
}

pub fn first_or_zero(values: List(Int)) -> Int {
  case values {
    [first, .._] -> first
    [] -> 0
  }
}

pub fn unpack(pair: #(Int, Int)) -> Int {
  let #(left, _) = pair
  left
}

pub fn escaped() -> String {
  "quote: \" slash: \\ line:\n"
}

pub fn whole_float() -> Float {
  1.0
}

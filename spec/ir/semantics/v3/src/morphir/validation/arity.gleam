//// First executable rule in the V3 semantic validation pilot.
//// A caller supplies the parameter count of an already resolved declaration.

import morphir/ir/type_.{type Type}

pub type ArityOutcome {
  Valid
  Mismatch(expected: Int, actual: Int)
}

pub fn check_arity(expected: Int, arguments: List(Type(Nil))) -> ArityOutcome {
  compare_count(expected, count(arguments))
}

fn count(arguments: List(Type(Nil))) -> Int {
  case arguments {
    [] -> 0
    [_, ..rest] -> 1 + count(rest)
  }
}

fn compare_count(expected: Int, actual: Int) -> ArityOutcome {
  case expected == actual {
    True -> Valid
    False -> Mismatch(expected, actual)
  }
}

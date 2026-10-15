///|
/// The Elm binary operators that morphir-elm's `Mapper.mapOperator` binds, with their Morphir SDK functions.
/// `++` is `basics#append` also for lists, and `::` is `list#cons`. `|>` and `<|` are not here: they lower to an
/// application.
let operator_table : Array[(String, String)] = [
  ("||", "morphir/SDK:basics#or"),
  ("&&", "morphir/SDK:basics#and"),
  ("==", "morphir/SDK:basics#equal"),
  ("/=", "morphir/SDK:basics#not-equal"),
  ("<", "morphir/SDK:basics#less-than"),
  (">", "morphir/SDK:basics#greater-than"),
  ("<=", "morphir/SDK:basics#less-than-or-equal"),
  (">=", "morphir/SDK:basics#greater-than-or-equal"),
  ("++", "morphir/SDK:basics#append"),
  ("+", "morphir/SDK:basics#add"),
  ("-", "morphir/SDK:basics#subtract"),
  ("*", "morphir/SDK:basics#multiply"),
  ("/", "morphir/SDK:basics#divide"),
  ("//", "morphir/SDK:basics#integer-divide"),
  ("^", "morphir/SDK:basics#power"),
  ("<<", "morphir/SDK:basics#compose-left"),
  (">>", "morphir/SDK:basics#compose-right"),
  ("::", "morphir/SDK:list#cons"),
]

///|
/// The operator table, parsed once.
let operators : Map[String, @ir.FQName] = {
  let parsed : Map[String, @ir.FQName] = Map([])
  for entry in operator_table {
    parsed[entry.0] = @ir.FQName::parse(entry.1) catch { _ => continue }
  }
  parsed
}

///|
/// The Morphir SDK function of an Elm binary operator, as morphir-elm's `make` maps it. An operator that is not
/// in the table has no binding.
pub fn morphir_operator(symbol : String) -> @ir.FQName? {
  operators.get(symbol)
}

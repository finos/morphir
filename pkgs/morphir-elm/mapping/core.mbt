///|
/// The Elm core modules that the SDK table covers.
pub let elm_core_modules : Array[String] = [
  "Basics", "List", "Maybe", "Result", "String", "Char", "Dict", "Set", "Tuple",
]

///|
/// The Elm-to-Morphir direction of the builtin table. Keys are `Module.name` for types and values. Operators
/// come from `morphir_operator`, morphir-elm's fixed table.
pub struct ElmCore {
  priv types : Map[String, @ir.FQName]
  priv values : Map[String, @ir.FQName]
}

///|
pub fn ElmCore::builtin() -> ElmCore {
  let core = { types: Map([]), values: Map([]), }
  for entry in builtin_entries() {
    let name = @ir.FQName::parse(entry.0) catch { _ => continue }
    match entry.1 {
      Type(elm, _) => core.types[elm] = name
      Function(elm, _) => core.values[elm] = name
      Operator(_) | Removed => ()
    }
  }
  core
}

///|
pub fn ElmCore::type_of(
  self : ElmCore,
  module_name : String,
  name : String,
) -> @ir.FQName? {
  self.types.get(module_name + "." + name)
}

///|
/// Values and constructors. An Elm constructor starts with an upper-case letter.
pub fn ElmCore::value_of(
  self : ElmCore,
  module_name : String,
  name : String,
) -> @ir.FQName? {
  self.values.get(module_name + "." + name)
}

///|
pub fn ElmCore::is_core_module(self : ElmCore, module_name : String) -> Bool {
  ignore(self)
  elm_core_modules.contains(module_name)
}

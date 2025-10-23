///|
pub enum Value[TA, VA] {
  Field(VA, Value[TA, VA], Name)
  Unit(VA)
} derive(Eq, Hash, Show)

///|
pub fn[TA, VA] Value::field(
  attributes : VA,
  value : Value[TA, VA],
  name : Name,
) -> Value[TA, VA] {
  Value::Field(attributes, value, name)
}

///|
pub fn[TA, VA] Value::unit(attributes : VA) -> Value[TA, VA] {
  Value::Unit(attributes)
}

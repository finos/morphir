///|
pub struct Field[A] {
  name : @name.Name
  tpe : Type[A]
} derive(Eq, Hash, Show)

///|
pub fn[A] field(name : @name.Name, tpe : Type[A]) -> Field[A] {
  { name, tpe }
}

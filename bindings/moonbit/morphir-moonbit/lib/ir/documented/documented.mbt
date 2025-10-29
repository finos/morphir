///|
pub struct Documented[T] {
  doc : String
  value : T
}

///|
pub fn[T] Documented::new(doc : String, value : T) -> Documented[T] {
  { doc, value }
}

///|
pub fn[T, U] Documented::map(
  self : Documented[T],
  f : (T) -> U,
) -> Documented[U] {
  Documented::new(self.doc, f(self.value))
}

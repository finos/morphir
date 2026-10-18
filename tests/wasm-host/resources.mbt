///|
let labels : Map[Int32, String] = Map([])

///|
// Keep representations distinct from canonical resource-table handles.
let next_representation : Ref[Int32] = Ref(1000)

///|
let destructor_calls : Ref[UInt32] = Ref(0U)

///|
pub fn Session::session(label : String) -> Session {
  next_representation.val += 1
  let representation = next_representation.val
  labels[representation] = label
  Session::new(representation)
}

///|
pub fn Session::read(self : Session) -> String {
  // Canonical lowering passes a guest-defined borrowed resource's representation
  // to its method. It is not an owned resource-table handle for rep().
  let Session(representation) = self
  labels[representation]
}

///|
pub fn Session::dtor(self : Session) -> Unit {
  let Session(representation) = self
  guard labels.contains(representation) else { panic() }
  labels.remove(representation)
  destructor_calls.val += 1U
}

///|
pub fn read_borrowed(value : Session) -> String {
  value.read()
}

///|
pub fn take(value : Session) -> String {
  // An own argument is a canonical handle. Resolve it before dropping ownership.
  let label = labels[value.rep()]
  value.drop()
  label
}

///|
pub fn live() -> UInt32 {
  labels.length().to_uint()
}

///|
pub fn dropped() -> UInt32 {
  destructor_calls.val
}

///|
/// Internal types. `Con` names are canonical FQName text.
priv enum Ty {
  Meta(Int32)
  /// A declared variable, by key: `<owner>|<canonical name>`, where the owner is the canonical FQName of the
  /// declaration that declares it (see `rigid_key`). The class set comes from the `typeclass` constraint of
  /// the variable, else its name prefix, so the variable carries its classes wherever it goes.
  Rigid(String, Array[String])
  /// A quantified variable inside a `Poly`.
  Gen(Int32)
  Con(String, Array[Ty])
  Fun(Ty, Ty)
  Tup(Array[Ty])
  /// Fields by canonical name. The tail is a `Meta` or a `Rigid`; `None` is a closed record.
  Rec(Map[String, Ty], Ty?)
  UnitTy
} derive(Eq, Debug)

///|
/// The state of a meta variable. An unbound meta has a binding level and a class set of at most one class.
priv enum MetaState {
  Unbound(level~ : Int32, classes~ : Array[String])
  Link(Ty)
}

///|
/// A type scheme. `gens[i]` holds the classes of `Gen(i)`.
priv struct Poly {
  gens : Array[Array[String]]
  body : Ty
}

///|
/// A unification failure: a code, the expected type and the found type.
/// The code is `type_mismatch`, `occurs`, `rigid_variable`, `no_instance` or `missing_field`.
priv suberror Mismatch {
  Mismatch(String, Ty, Ty)
}

///|
/// The substitution and the context of unification.
priv struct Solver {
  metas : Array[MetaState]
  /// Alias expansion. `None` means the type is nominal.
  expand : (String, Array[Ty]) -> Ty?
}

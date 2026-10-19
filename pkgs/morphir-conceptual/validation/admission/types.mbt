///|
/// Versioned fixture profile fixed by the C1 contract interfaces
/// (morphir-ukvn.7.10.1). Values are checked only under this profile.
pub let supported_profile : String = "morphir-contracts/0.1.0-draft.1"

///|
/// A declared type in the bounded checking profile. Function types and
/// explicitly unsupported forms are representable so the checker can report
/// them instead of silently accepting them.
pub(all) enum TypeExpr {
  TBool
  TInt
  TString
  TVariable(String)
  TReference(String, Array[TypeExpr])
  TTuple(Array[TypeExpr])
  TRecord(Array[(String, TypeExpr)])
  TUnion(Array[TypeExpr])
  TList(TypeExpr)
  TSet(TypeExpr)
  TDict(TypeExpr, TypeExpr)
  TFunction(Array[TypeExpr], TypeExpr)
  TUnsupported(String)
}

///|
/// A candidate typed value. Integers keep exact arbitrary-precision lexemes;
/// no value passes through a machine integer or a JS number.
pub(all) enum Value {
  VBool(Bool)
  VInt(@bigint.BigInt)
  VString(String)
  VTuple(Array[Value])
  VRecord(Array[(String, Value)])
  VList(Array[Value])
  VSet(Array[Value])
  VDict(Array[(Value, Value)])
  VConstructed(String, Array[Value])
  VOpaque(String, Value)
}

///|
/// Build an exact integer value from its decimal lexeme.
pub fn int_value(lexeme : String) -> Value {
  VInt(@bigint.BigInt::from_string(lexeme))
}

///|
/// A named predicate obligation carried by an alias. The checker implements
/// only the versioned names in this enum plus the recognized
/// `NamedRefinement` spellings; any other name is reported unsupported.
pub(all) enum Refinement {
  NonEmptyString
  PositiveInt
  NonNegativeInt
  MaxLength(Int32)
  NamedRefinement(String)
}

///|
/// A named type declaration. A transparent alias keeps structural identity; an
/// opaque alias hides its representation outside its defining module; a custom
/// type has finitely many named constructors.
pub(all) enum TypeDecl {
  Transparent(Array[String], TypeExpr, Refinement?)
  Opaque(Array[String], TypeExpr, Refinement?)
  Custom(Array[String], Array[(String, Array[TypeExpr])])
}

///|
/// One precise failure. `path` is an RFC 6901 pointer; the root is empty.
pub(all) struct Diagnostic {
  code : String
  path : String
  message : String
}

///|
/// Which budget ran out. Exhaustion is an execution error detail in the C1
/// outcome set; it never produces a passing check.
pub(all) enum Exhaustion {
  DepthLimit
  NodeLimit
  IntDigitLimit
}

///|
/// The result of checking one candidate value against one declared type.
/// This mirrors the C1 distinction between invalid input, unsupported checks
/// and execution errors; a negative fixture passes by expecting `Invalid`.
pub(all) enum Outcome {
  Valid
  Invalid(Array[Diagnostic])
  Unsupported(Diagnostic)
  Exhausted(Exhaustion)
}

///|
/// The C1 budget record for the admission phase: value depth, visited value
/// nodes and decimal digits per exact integer. Step limits belong to
/// predicate evaluation (C3), not to admission.
pub(all) struct Limits {
  max_depth : Int32
  max_value_nodes : Int32
  max_int_digits : Int32
}

///|
/// The pinned corpus default. Using exactly a limit is allowed; exceeding
/// any limit reports exhaustion and never passes.
pub fn Limits::default() -> Limits {
  { max_depth: 64, max_value_nodes: 10000, max_int_digits: 256, }
}

///|
/// The declared types one check may resolve, scoped to a fixture profile.
pub struct TypeEnvironment {
  profile : String
  declarations : Map[String, TypeDecl]
  declaration_error : Diagnostic?
}

///|
/// Build an environment. Duplicate declaration names are retained as an
/// error that every check reports; they never silently shadow.
pub fn TypeEnvironment::new(
  profile~ : String,
  declarations~ : Array[(String, TypeDecl)],
) -> TypeEnvironment {
  let map : Map[String, TypeDecl] = Map([])
  let mut error : Diagnostic? = None
  for (name, decl) in declarations {
    if map.contains(name) && error is None {
      error = Some({
        code: "contracts.duplicate_declaration",
        path: "",
        message: "duplicate type declaration: " + name,
      })
    }
    map[name] = decl
  }
  { profile, declarations: map, declaration_error: error, }
}

///|
pub fn TypeEnvironment::profile(self : TypeEnvironment) -> String {
  self.profile
}

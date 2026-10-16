///|
pub const LIBRARY_PROFILE : String = "moonbit-model-bool-library-v1"

///|
/// Caller budgets may tighten, but cannot exceed, the profile's hard bounds.
pub(all) struct LibraryLimits {
  max_bytes : Int32
  max_functions : Int32
  max_parameters : Int32
  max_lets : Int32
  max_expressions : Int32
  max_calls : Int32
  max_depth : Int32
  max_call_depth : Int32
} derive(Eq, Debug)

///|
pub fn LibraryLimits::default() -> LibraryLimits {
  {
    max_bytes: 65536,
    max_functions: 64,
    max_parameters: 16,
    max_lets: 256,
    max_expressions: 4096,
    max_calls: 1024,
    max_depth: 64,
    max_call_depth: 32,
  }
}

///|
/// Entries are the canonical, sorted public values; an all-private unit has none.
pub(all) struct LibraryOutput {
  unit_id : String
  ir : @ir.IRFile
  entries : Array[@ir.FQName]
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
  warnings : Array[@diagnostics.Warning]
}

///|
priv enum LibraryExpr {
  Boolean(Bool, @ir.SourceLocation)
  Identifier(String, @ir.SourceLocation)
  Negation(LibraryExpr, @ir.SourceLocation)
  Binary(String, LibraryExpr, LibraryExpr, @ir.SourceLocation)
  Conditional(LibraryExpr, LibraryExpr, LibraryExpr, @ir.SourceLocation)
  Binding(
    String,
    @ir.SourceLocation,
    LibraryExpr,
    LibraryExpr,
    @ir.SourceLocation
  )
  Call(String, Array[LibraryExpr], @ir.SourceLocation)
}

///|
priv struct LibraryFunction {
  name : String
  public : Bool
  parameters : Array[(String, @ir.SourceLocation)]
  body : LibraryExpr
  body_source : @ir.SourceLocation
  source : @ir.SourceLocation
}

///|
/// No parser AST escapes the adapter. Resolved trees hold identities, not spellings.
priv enum ResolvedExpr {
  Boolean(Bool, @ir.SourceLocation)
  Variable(@ir.Name, @ir.SourceLocation)
  Negation(ResolvedExpr, @ir.SourceLocation)
  Binary(String, ResolvedExpr, ResolvedExpr, @ir.SourceLocation)
  Conditional(ResolvedExpr, ResolvedExpr, ResolvedExpr, @ir.SourceLocation)
  Binding(
    @ir.Name,
    String,
    @ir.SourceLocation,
    ResolvedExpr,
    ResolvedExpr,
    @ir.SourceLocation
  )
  Call(Int32, Array[ResolvedExpr], @ir.SourceLocation)
}

///|
priv struct ResolvedFunction {
  declaration : LibrarySignature
  parameters : Array[@ir.Name]
  body : ResolvedExpr
  names : BinderNames
}

///|
/// Resolution drops the unresolved body; later phases retain only its signature.
priv struct LibrarySignature {
  name : String
  public : Bool
  parameters : Array[(String, @ir.SourceLocation)]
  source : @ir.SourceLocation
  body_source : @ir.SourceLocation
}

///|
/// Constructed only after all bodies and the complete call graph pass checking.
priv struct CheckedLibrary {
  functions : Array[ResolvedFunction]
}

///|
fn library_error(
  code : String,
  detail : String,
  source : @ir.SourceLocation?,
) -> Unit raise FrontendError {
  raise Invalid({ code: "moonbit_frontend." + code, detail, source, })
}

///|
fn library_poll(cancelled : () -> Bool) -> Unit raise FrontendError {
  if cancelled() {
    library_error("cancelled", "Frontend cancelled", None)
  }
}

///|
pub extend LibraryLimits with Eq::{equal, not_equal}

///|
pub extend LibraryLimits with @debug.Debug::{to_repr}

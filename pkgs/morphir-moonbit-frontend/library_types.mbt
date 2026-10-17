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
  Text(String, String, @ir.SourceLocation)
  Constraint(LibraryExpr, LibraryTypeUse, @ir.SourceLocation)
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
  doc : String?
  public : Bool
  parameters : Array[(String, @ir.SourceLocation)]
  input_types : Array[LibraryTypeUse]
  output_type : LibraryTypeUse
  body : LibraryExpr
  body_source : @ir.SourceLocation
  source : @ir.SourceLocation
}

///|
/// No parser AST escapes the adapter. Resolved trees hold identities, not spellings.
priv enum ResolvedExpr {
  Boolean(Bool, @ir.SourceLocation)
  Text(String, String, @ir.SourceLocation)
  Constraint(ResolvedExpr, LibraryTypeUse, @ir.SourceLocation)
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
  types : Map[@ir.Name, LibraryTypeUse]
}

///|
/// Resolution drops the unresolved body; later phases retain only its signature.
priv struct LibrarySignature {
  name : String
  doc : String?
  public : Bool
  parameters : Array[(String, @ir.SourceLocation)]
  input_types : Array[LibraryTypeUse]
  output_type : LibraryTypeUse
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

///|
pub const TYPED_FOUNDATION_PROFILE : String = "moonbit-model-typed-library-foundation-v1"

///|
priv enum LibraryMode {
  BooleanOnly
  TypedFoundation
  StringBasics
  SupportedLibrary
  SupportedLibraryV2
  SupportedLibrary20261017
} derive(Eq)

///|
priv enum LibraryScalar {
  Boolean
  SignedInt32
  Text
} derive(Eq)

///|
priv struct LibraryTypeUse {
  scalar : LibraryScalar
  spelling : String
  source : @ir.SourceLocation
}

///|
fn LibraryTypeUse::to_ir(
  self : LibraryTypeUse,
  metadata : Bool,
) -> @ir.Type raise {
  let attrs = @ir.TypeAttributes::default()
  if metadata {
    attrs.extensions[if self.scalar == Text {
      "moonbit-source-string-v1"
    } else {
      "moonbit-source-scalar-v1"
    }] = @ir.Data::Object(
      Map::from_array([
        ("authored", @ir.Data::Text(self.spelling)),
        ("coordinate_profile", @ir.Data::Text("moonbit-parser-position-v1")),
        ("start_line", @ir.Data::Number(self.source.start_line.to_string())),
        ("start_column", @ir.Data::Number(self.source.start_column.to_string())),
        ("end_line", @ir.Data::Number(self.source.end_line.to_string())),
        ("end_column", @ir.Data::Number(self.source.end_column.to_string())),
        (
          "representation",
          @ir.Data::Text(
            match self.scalar {
              Boolean => "bool"
              SignedInt32 => "signed-32"
              Text => "well-formed-utf16"
            },
          ),
        ),
      ]),
    )
  }
  @ir.Type::Reference(
    attrs,
    @ir.FQName::parse(
      match self.scalar {
        Boolean => "morphir/SDK:basics#bool"
        SignedInt32 => "morphir/SDK:int#int-32"
        Text => "morphir/SDK:string#string"
      },
    ),
    [],
  )
}

///|
fn library_type(
  ty : @ast.Type?,
  loc : @location.Location,
  mode : LibraryMode,
) -> LibraryTypeUse raise {
  guard ty is Some(@ast.Name(constr_id~, tys~, ..)) &&
    tys.is_empty() &&
    constr_id.id is @ast.Ident(name~) else {
    reject(
      "unsupported_type", "An explicit supported scalar annotation is required",
      loc,
    )
    abort("unreachable")
  }
  let scalar = match name {
    "Bool" => LibraryScalar::Boolean
    "String" if mode.supports_strings() => LibraryScalar::Text
    "Int32" | "Int" if mode.supports_int32() => LibraryScalar::SignedInt32
    _ => {
      reject(
        "unsupported_type",
        "Type is outside the selected source profile: " + name,
        loc,
      )
      abort("unreachable")
    }
  }
  { scalar, spelling: name, source: span(loc), }
}

///|
pub const STRING_LIBRARY_PROFILE : String = "moonbit-model-string-library-v1"

///|
/// The versioned union of qualified source capabilities, rather than a type lane.
pub const SUPPORTED_LIBRARY_PROFILE : String = "moonbit-model-library-v1"

///|
/// Cumulative v1 capabilities plus qualified String shortlex comparisons.
pub const SUPPORTED_LIBRARY_PROFILE_V2 : String = "moonbit-model-library-v2"

///|
/// Date identifies the current cumulative source qualification snapshot.
pub const CURRENT_LIBRARY_PROFILE : String = "moonbit-model-library-2026-10-17"

///|
/// Immutable qualification identity retained as the current snapshot advances.
pub const LIBRARY_PROFILE_2026_10_17 : String = "moonbit-model-library-2026-10-17"

///|
fn LibraryMode::supports_strings(self : LibraryMode) -> Bool {
  self == StringBasics ||
  self == SupportedLibrary ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017
}

///|
fn LibraryMode::supports_int32(self : LibraryMode) -> Bool {
  self == TypedFoundation ||
  self == SupportedLibrary ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017
}

///|
fn LibraryMode::supports_string_order(self : LibraryMode) -> Bool {
  self == SupportedLibraryV2 || self == SupportedLibrary20261017
}

///|
fn LibraryMode::profile(self : LibraryMode) -> String {
  match self {
    BooleanOnly => LIBRARY_PROFILE
    TypedFoundation => TYPED_FOUNDATION_PROFILE
    StringBasics => STRING_LIBRARY_PROFILE
    SupportedLibrary => SUPPORTED_LIBRARY_PROFILE
    SupportedLibraryV2 => SUPPORTED_LIBRARY_PROFILE_V2
    SupportedLibrary20261017 => LIBRARY_PROFILE_2026_10_17
  }
}

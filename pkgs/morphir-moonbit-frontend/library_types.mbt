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
  Number(String, String, LibraryScalar, @ir.SourceLocation)
  Floating(Double, String, LibraryScalar, @ir.SourceLocation)
  Text(String, String, @ir.SourceLocation)
  Constraint(LibraryExpr, LibraryTypeUse, @ir.SourceLocation)
  Identifier(String, @ir.SourceLocation)
  Negation(LibraryExpr, @ir.SourceLocation)
  NumericNegation(LibraryExpr, @ir.SourceLocation)
  StringLength(LibraryExpr, @ir.SourceLocation)
  StringSlice(LibraryExpr, LibraryExpr, LibraryExpr, @ir.SourceLocation)
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
  QualifiedCall(String, String, Array[LibraryExpr], @ir.SourceLocation)
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
  Number(String, String, LibraryScalar, @ir.SourceLocation)
  Floating(Double, String, LibraryScalar, @ir.SourceLocation)
  Text(String, String, @ir.SourceLocation)
  Constraint(ResolvedExpr, LibraryTypeUse, @ir.SourceLocation)
  Variable(@ir.Name, @ir.SourceLocation)
  Negation(ResolvedExpr, @ir.SourceLocation)
  NumericNegation(ResolvedExpr, @ir.SourceLocation)
  StringLength(ResolvedExpr, @ir.SourceLocation)
  StringSlice(ResolvedExpr, ResolvedExpr, ResolvedExpr, @ir.SourceLocation)
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
  SdkCall(Int32, Array[ResolvedExpr], @ir.SourceLocation)
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
pub const INT32_LIBRARY_PROFILE : String = "moonbit-model-int32-library-v1"

///|
pub const INTEGER_LIBRARY_PROFILE : String = "moonbit-model-integer-library-v1"

///|
pub const FLOAT_LIBRARY_PROFILE : String = "moonbit-model-float-library-v1"

///|
priv enum LibraryMode {
  BooleanOnly
  TypedFoundation
  NumericInt32
  NumericInteger
  NumericFloat
  StringBasics
  SupportedLibrary
  SupportedLibraryV2
  SupportedLibrary20261017
  SupportedLibrary20261019
  PinnedSdk
  NumericMath
} derive(Eq)

///|
/// A resolved source binding is selected by the host adapter. Its fields are
/// private so source text cannot register another native or SDK operation.
priv struct ResolvedSourceBinding {
  source_alias : String
  source_name : String
  source_package : String
  source_version : String
  source_tree : String
  source_signature : String
  canonical : String
  inputs : Array[LibraryScalar]
  output : LibraryScalar
  contract : SourceBindingContract
}

///|
priv enum SourceBindingContract {
  ExactBool
  Binary64Sqrt
  Binary64Reference4Ulp
  ClassicFloatAbs
}

///|
fn SourceBindingContract::identifier(self : SourceBindingContract) -> String {
  match self {
    ExactBool => "exact-bool"
    Binary64Sqrt => "binary64-sqrt-exact-reference-bits"
    Binary64Reference4Ulp => "binary64-reference-4ulp"
    ClassicFloatAbs => "exact-classic-abs-signed-zero"
  }
}

///|
/// The pure frontend receives this frozen mapping from its adapter.
pub struct PinnedSourceBindings {
  priv entries : Array[ResolvedSourceBinding]
}

///|
pub fn PinnedSourceBindings::empty() -> PinnedSourceBindings {
  { entries: [], }
}

///|
/// The adapter supplies a resolved identity. This finite constructor refuses
/// any package, alias or tree that is not the audited SDK call.
pub fn PinnedSourceBindings::sdk_basics_not(
  source_package : String,
  source_version : String,
  source_tree : String,
  source_alias : String,
) -> PinnedSourceBindings raise FrontendError {
  if source_package != "finos/morphir-sdk/basics" ||
    source_version != "0.1.0" ||
    source_tree != "9c83a100383570236b3d781362524008f76dd56d" ||
    source_alias != "basics" {
    library_error(
      "binding_identity",
      "Resolved source binding does not match the audited SDK package, tree and alias",
      None,
    )
  }
  {
    entries: [
      {
        source_alias,
        source_name: "not_",
        source_package,
        source_version,
        source_tree,
        source_signature: "Bool -> Bool",
        canonical: "morphir/SDK:basics#not",
        inputs: [Boolean],
        output: Boolean,
        contract: ExactBool,
      },
    ],
  }
}

///|
/// Finite N4 additions to the audited resolver. No source text can extend it.
pub fn PinnedSourceBindings::sdk_numeric_math(
  source_package : String,
  source_version : String,
  source_tree : String,
  source_alias : String,
) -> PinnedSourceBindings raise FrontendError {
  let bindings = PinnedSourceBindings::sdk_basics_not(
    source_package, source_version, source_tree, source_alias,
  )
  for
    (name, canonical, inputs, policy) in [
      ("sqrt", "sqrt", [Floating64], SourceBindingContract::Binary64Sqrt),
      ("sin", "sin", [Floating64], Binary64Reference4Ulp),
      ("cos", "cos", [Floating64], Binary64Reference4Ulp),
      ("power_float", "power", [Floating64, Floating64], Binary64Reference4Ulp),
      ("abs_float", "abs", [Floating64], ClassicFloatAbs),
    ] {
    bindings.entries.push({
      source_alias,
      source_name: name,
      source_package,
      source_version,
      source_tree,
      source_signature: if inputs.length() == 2 {
        "(Double, Double) -> Double"
      } else {
        "Double -> Double"
      },
      canonical: "morphir/SDK:basics#" + canonical,
      inputs,
      output: Floating64,
      contract: policy,
    })
  }
  bindings
}

///|
fn PinnedSourceBindings::find(
  self : PinnedSourceBindings,
  package_alias : String,
  source_name : String,
) -> Int32? {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].source_alias == package_alias &&
      self.entries[i].source_name == source_name {
      return Some(i)
    }
  }
  None
}

///|
priv enum LibraryScalar {
  Boolean
  SignedInt32
  SignedInt16
  SignedInt64
  UnsignedByte
  UnsignedInt16
  UnsignedInt32
  UnsignedInt64
  UnboundedInteger
  Floating32
  Floating64
  Text
} derive(Eq)

///|
fn LibraryScalar::source_name(self : LibraryScalar) -> String {
  match self {
    Boolean => "Bool"
    SignedInt16 => "Int16"
    SignedInt32 => "Int32"
    SignedInt64 => "Int64"
    UnsignedByte => "Byte"
    UnsignedInt16 => "UInt16"
    UnsignedInt32 => "UInt32"
    UnsignedInt64 => "UInt64"
    UnboundedInteger => "BigInt"
    Floating32 => "Float"
    Floating64 => "Double"
    Text => "String"
  }
}

///|
fn LibraryScalar::is_integer(self : LibraryScalar) -> Bool {
  match self {
    SignedInt16
    | SignedInt32
    | SignedInt64
    | UnsignedByte
    | UnsignedInt16
    | UnsignedInt32
    | UnsignedInt64
    | UnboundedInteger => true
    _ => false
  }
}

///|
fn LibraryScalar::is_floating(self : LibraryScalar) -> Bool {
  self == Floating32 || self == Floating64
}

///|
fn LibraryScalar::is_signed(self : LibraryScalar) -> Bool {
  self == SignedInt16 ||
  self == SignedInt32 ||
  self == SignedInt64 ||
  self == UnboundedInteger
}

///|
fn LibraryScalar::bits(self : LibraryScalar) -> Int32 {
  match self {
    SignedInt16 | UnsignedInt16 => 16
    SignedInt32 | UnsignedInt32 => 32
    SignedInt64 | UnsignedInt64 => 64
    UnsignedByte => 8
    _ => 0
  }
}

///|
fn LibraryScalar::source_module(self : LibraryScalar) -> String {
  match self {
    SignedInt16 => "int16"
    SignedInt32 => "int32"
    SignedInt64 => "int64"
    UnsignedByte => "byte"
    UnsignedInt16 => "uint16"
    UnsignedInt32 => "uint32"
    UnsignedInt64 => "uint64"
    _ => ""
  }
}

///|
priv struct LibraryTypeUse {
  scalar : LibraryScalar
  spelling : String
  source : @ir.SourceLocation
  profile : String
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
              SignedInt16 => "signed-16"
              SignedInt64 => "signed-64"
              UnsignedByte => "unsigned-8"
              UnsignedInt16 => "unsigned-16"
              UnsignedInt32 => "unsigned-32"
              UnsignedInt64 => "unsigned-64"
              UnboundedInteger => "signed-arbitrary"
              Floating32 => "ieee-binary32"
              Floating64 => "ieee-binary64"
              Text => "well-formed-utf16"
            },
          ),
        ),
      ]),
    )
    if (self.scalar.is_integer() || self.scalar.is_floating()) &&
      (
        self.profile == INTEGER_LIBRARY_PROFILE ||
        self.profile == INT32_LIBRARY_PROFILE ||
        self.profile == FLOAT_LIBRARY_PROFILE ||
        self.profile == MATH_LIBRARY_PROFILE ||
        self.profile == LIBRARY_PROFILE_2026_10_19
      ) {
      let facts = Map::from_array([
        ("kind", @ir.Data::Text("type-use")),
        ("language", @ir.Data::Text("moonbit")),
        ("authored", @ir.Data::Text(self.spelling)),
        ("canonical_type", @ir.Data::Text(self.scalar.source_name())),
        (
          "signedness",
          @ir.Data::Text(
            if self.scalar.is_floating() {
              "signed-ieee"
            } else if self.scalar.is_signed() {
              "signed"
            } else {
              "unsigned"
            },
          ),
        ),
        ("compiler", @ir.Data::Text("0.10.15+943464bfa")),
        ("profile", @ir.Data::Text(self.profile)),
      ])
      if self.scalar.is_floating() {
        facts["width"] = @ir.Data::Number(
          if self.scalar == Floating32 {
            "32"
          } else {
            "64"
          },
        )
        facts["precision"] = @ir.Data::Number(
          if self.scalar == Floating32 {
            "24"
          } else {
            "53"
          },
        )
      } else if self.scalar.bits() == 0 {
        facts["precision"] = @ir.Data::Text("arbitrary")
      } else {
        facts["width"] = @ir.Data::Number(self.scalar.bits().to_string())
      }
      attrs.extensions["moonbit-source-number-v1"] = @ir.Data::Object(facts)
    }
  }
  @ir.Type::Reference(
    attrs,
    @ir.FQName::parse(
      match self.scalar {
        Boolean => "morphir/SDK:basics#bool"
        SignedInt32 => "morphir/SDK:int#int-32"
        SignedInt16 => "morphir/SDK:int#int-16"
        SignedInt64 => "morphir/SDK:int#int-64"
        UnsignedByte => "morphir/SDK:int#byte"
        UnsignedInt16 => "morphir/SDK:int#uint-16"
        UnsignedInt32 => "morphir/SDK:int#uint-32"
        UnsignedInt64 => "morphir/SDK:int#uint-64"
        UnboundedInteger => "morphir/SDK:basics#int"
        Floating32 => "morphir/moonbit-source:float32#float32"
        Floating64 => "morphir/SDK:basics#float"
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
    "Int16" if mode.supports_integer() => LibraryScalar::SignedInt16
    "Int64" if mode.supports_integer() => LibraryScalar::SignedInt64
    "Byte" if mode.supports_integer() => LibraryScalar::UnsignedByte
    "UInt16" if mode.supports_integer() => LibraryScalar::UnsignedInt16
    "UInt32" | "UInt" if mode.supports_integer() => LibraryScalar::UnsignedInt32
    "UInt64" if mode.supports_integer() => LibraryScalar::UnsignedInt64
    "BigInt" if mode.supports_integer() => LibraryScalar::UnboundedInteger
    "Float" if mode.supports_float() => LibraryScalar::Floating32
    "Double" if mode.supports_float() => LibraryScalar::Floating64
    _ => {
      reject(
        "unsupported_type",
        "Type is outside the selected source profile: " + name,
        loc,
      )
      abort("unreachable")
    }
  }
  { scalar, spelling: name, source: span(loc), profile: mode.profile(), }
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
pub const CURRENT_LIBRARY_PROFILE : String = "moonbit-model-library-2026-10-19-r2"

///|
/// N4 cumulative snapshot, including all qualified integer and float forms.
pub const MATH_LIBRARY_PROFILE : String = "moonbit-model-library-2026-10-19-r2"

///|
/// Immutable qualification identity retained as the current snapshot advances.
pub const LIBRARY_PROFILE_2026_10_17 : String = "moonbit-model-library-2026-10-17"

///|
pub const LIBRARY_PROFILE_2026_10_19 : String = "moonbit-model-library-2026-10-19"

///|
pub const PINNED_SDK_LIBRARY_PROFILE : String = "moonbit-model-pinned-sdk-library-v1"

///|
fn LibraryMode::supports_strings(self : LibraryMode) -> Bool {
  self == NumericMath ||
  self == StringBasics ||
  self == SupportedLibrary ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017 ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_int32(self : LibraryMode) -> Bool {
  self == NumericMath ||
  self == TypedFoundation ||
  self == NumericInt32 ||
  self == NumericInteger ||
  self == SupportedLibrary ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017 ||
  self == SupportedLibrary20261019 ||
  self == PinnedSdk
}

///|
fn LibraryMode::supports_numeric(self : LibraryMode) -> Bool {
  self == NumericMath ||
  self == NumericInt32 ||
  self == NumericInteger ||
  self == NumericFloat ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_float(self : LibraryMode) -> Bool {
  self == NumericFloat || self == NumericMath
}

///|
fn LibraryMode::supports_integer(self : LibraryMode) -> Bool {
  self == NumericInteger || self == NumericMath
}

///|
fn LibraryMode::supports_string_order(self : LibraryMode) -> Bool {
  self == NumericMath ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017 ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_string_index(self : LibraryMode) -> Bool {
  self == SupportedLibrary20261019 || self == NumericMath
}

///|
fn LibraryMode::profile(self : LibraryMode) -> String {
  match self {
    BooleanOnly => LIBRARY_PROFILE
    TypedFoundation => TYPED_FOUNDATION_PROFILE
    NumericInt32 => INT32_LIBRARY_PROFILE
    NumericInteger => INTEGER_LIBRARY_PROFILE
    NumericFloat => FLOAT_LIBRARY_PROFILE
    StringBasics => STRING_LIBRARY_PROFILE
    SupportedLibrary => SUPPORTED_LIBRARY_PROFILE
    SupportedLibraryV2 => SUPPORTED_LIBRARY_PROFILE_V2
    SupportedLibrary20261017 => LIBRARY_PROFILE_2026_10_17
    SupportedLibrary20261019 => LIBRARY_PROFILE_2026_10_19
    PinnedSdk => PINNED_SDK_LIBRARY_PROFILE
    NumericMath => MATH_LIBRARY_PROFILE
  }
}

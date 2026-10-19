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
  effect : LibraryEffect
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
  effect : LibraryEffect
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
  NumericSdk
} derive(Eq)

///|
/// Only the named SDK model error is admitted; this grants no host effects.
priv enum LibraryEffect {
  Pure
  SdkError
} derive(Eq)

///|
fn LibraryEffect::identifier(self : LibraryEffect) -> String {
  match self {
    Pure => "pure"
    SdkError => "sdk.SdkError"
  }
}

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
  effect : LibraryEffect
  origin : SourceBindingOrigin
}

///|
priv enum SourceBindingOrigin {
  Classic
  NumericExtension
}

///|
fn SourceBindingOrigin::identifier(self : SourceBindingOrigin) -> String {
  match self {
    Classic => "classic"
    NumericExtension => "morphir-sdk-moonbit-numeric-v1"
  }
}

///|
priv enum SourceBindingContract {
  ExactBool
  Binary64Sqrt
  Binary64Reference4Ulp
  ClassicFloatAbs
  ClassicIntegerAbs
  ClassicIntegerRounding(IntegerRoundingPolicy)
  RoundedIntegerToFloat64
  CheckedIntegerToFloat64
  CheckedFloat64ToInteger(IntegerConversionPolicy)
}

///|
priv enum IntegerRoundingPolicy {
  Round
  Floor
  Ceiling
  Truncate
}

///|
priv enum IntegerConversionPolicy {
  Exact
  Truncated
  Floor
  Ceiling
  Rounded
}

///|
fn SourceBindingContract::identifier(self : SourceBindingContract) -> String {
  match self {
    ExactBool => "exact-bool"
    Binary64Sqrt => "binary64-sqrt-exact-reference-bits"
    Binary64Reference4Ulp => "binary64-reference-4ulp"
    ClassicFloatAbs => "exact-classic-abs-signed-zero"
    ClassicIntegerAbs => "exact-integer-abs"
    ClassicIntegerRounding(policy) =>
      match policy {
        Round => "nearest-integer-ties-positive-infinity"
        Floor => "floor-integer"
        Ceiling => "ceiling-integer"
        Truncate => "truncate-integer-toward-zero"
      }
    RoundedIntegerToFloat64 => "integer-to-binary64-rounded"
    CheckedIntegerToFloat64 => "integer-to-binary64-checked-exact"
    CheckedFloat64ToInteger(policy) =>
      match policy {
        Exact => "binary64-to-integer-checked-exact"
        Truncated => "binary64-to-integer-checked-truncated"
        Floor => "binary64-to-integer-checked-floor"
        Ceiling => "binary64-to-integer-checked-ceiling"
        Rounded => "binary64-to-integer-checked-rounded"
      }
  }
}

///|
/// The pure frontend receives this frozen mapping from its adapter.
pub struct PinnedSourceBindings {
  priv entries : Array[ResolvedSourceBinding]
  priv types : Array[SourceSdkType]
}

///|
priv enum SourceSdkType {
  Integer
  Error
} derive(Eq)

///|
pub fn PinnedSourceBindings::empty() -> PinnedSourceBindings {
  { entries: [], types: [], }
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
    types: [],
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
        effect: Pure,
        origin: Classic,
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
      effect: Pure,
      origin: Classic,
    })
  }
  bindings
}

///|
/// R3 preserves the R2 factory and adds only audited SDK Integer call contracts.
pub fn PinnedSourceBindings::sdk_numeric_conversions(
  source_package : String,
  source_version : String,
  source_tree : String,
  source_alias : String,
) -> PinnedSourceBindings raise FrontendError {
  let bindings = PinnedSourceBindings::sdk_numeric_math(
    source_package, source_version, source_tree, source_alias,
  )
  bindings.types.append([SourceSdkType::Integer, Error])
  for
    (name, policy) in [
      ("round", IntegerRoundingPolicy::Round),
      ("floor", Floor),
      ("ceiling", Ceiling),
      ("truncate", Truncate),
    ] {
    bindings.entries.push({
      source_alias,
      source_name: name,
      source_package,
      source_version,
      source_tree,
      source_signature: "Double -> @integer.Integer raise @sdk.SdkError",
      canonical: "morphir/SDK:basics#" + name,
      inputs: [Floating64],
      output: SdkInteger,
      contract: ClassicIntegerRounding(policy),
      effect: SdkError,
      origin: Classic,
    })
  }
  for
    (name, canonical, contract, output) in [
      (
        "to_float",
        "basics#to-float",
        SourceBindingContract::RoundedIntegerToFloat64,
        LibraryScalar::Floating64,
      ),
      ("abs_int", "basics#abs", ClassicIntegerAbs, SdkInteger),
    ] {
    bindings.entries.push({
      source_alias,
      source_name: name,
      source_package,
      source_version,
      source_tree,
      source_signature: "@integer.Integer -> " + output.source_name(),
      canonical: "morphir/SDK:" + canonical,
      inputs: [SdkInteger],
      output,
      contract,
      effect: Pure,
      origin: Classic,
    })
  }
  for
    (name, policy) in [
      ("from_float64_exact", IntegerConversionPolicy::Exact),
      ("from_float64_truncated", Truncated),
      ("from_float64_floor", Floor),
      ("from_float64_ceiling", Ceiling),
      ("from_float64_rounded", Rounded),
    ] {
    bindings.entries.push({
      source_alias: "int",
      source_name: name,
      source_package: "finos/morphir-sdk/int",
      source_version,
      source_tree,
      source_signature: "Double -> @integer.Integer?",
      canonical: "morphir/SDK:int#" + name.split("_").join("-"),
      inputs: [Floating64],
      output: OptionalSdkInteger,
      contract: CheckedFloat64ToInteger(policy),
      effect: Pure,
      origin: NumericExtension,
    })
  }
  for
    (name, output, contract) in [
      (
        "to_float64_exact",
        LibraryScalar::OptionalDouble,
        SourceBindingContract::CheckedIntegerToFloat64,
      ),
      ("to_float64_rounded", Floating64, RoundedIntegerToFloat64),
    ] {
    bindings.entries.push({
      source_alias: "int",
      source_name: name,
      source_package: "finos/morphir-sdk/int",
      source_version,
      source_tree,
      source_signature: "@integer.Integer -> " + output.source_name(),
      canonical: "morphir/SDK:int#" + name.split("_").join("-"),
      inputs: [SdkInteger],
      output,
      contract,
      effect: Pure,
      origin: NumericExtension,
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
  SdkInteger
  OptionalSdkInteger
  OptionalDouble
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
    SdkInteger => "@integer.Integer"
    OptionalSdkInteger => "@integer.Integer?"
    OptionalDouble => "Double?"
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
fn LibraryScalar::has_integer_boundary(self : LibraryScalar) -> Bool {
  self == UnboundedInteger || self == SdkInteger || self == OptionalSdkInteger
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
              SdkInteger => "sdk-integer"
              OptionalSdkInteger => "optional-sdk-integer"
              OptionalDouble => "optional-ieee-binary64"
              Floating32 => "ieee-binary32"
              Floating64 => "ieee-binary64"
              Text => "well-formed-utf16"
            },
          ),
        ),
      ]),
    )
    if self.profile == NUMERIC_SDK_LIBRARY_PROFILE &&
      (self.scalar == SdkInteger || self.scalar == OptionalSdkInteger) {
      attrs.extensions["moonbit-source-sdk-type-v1"] = @ir.Data::Object(
        Map::from_array([
          ("source_alias", @ir.Data::Text("integer")),
          ("source_name", @ir.Data::Text("Integer")),
          ("source_package", @ir.Data::Text("finos/morphir-sdk/integer")),
          ("source_version", @ir.Data::Text("0.1.0")),
          (
            "source_tree",
            @ir.Data::Text("9c83a100383570236b3d781362524008f76dd56d"),
          ),
          ("profile", @ir.Data::Text(self.profile)),
        ]),
      )
    }
    if (
        self.scalar.is_integer() ||
        self.scalar.is_floating() ||
        self.scalar == SdkInteger
      ) &&
      (
        self.profile == INTEGER_LIBRARY_PROFILE ||
        self.profile == INT32_LIBRARY_PROFILE ||
        self.profile == FLOAT_LIBRARY_PROFILE ||
        self.profile == MATH_LIBRARY_PROFILE ||
        self.profile == NUMERIC_SDK_LIBRARY_PROFILE ||
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
            } else if self.scalar.is_signed() || self.scalar == SdkInteger {
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
  if self.scalar == OptionalSdkInteger || self.scalar == OptionalDouble {
    let item = LibraryTypeUse::{
      ..self,
      scalar: if self.scalar == OptionalSdkInteger {
        SdkInteger
      } else {
        Floating64
      },
      spelling: if self.scalar == OptionalSdkInteger {
        "@integer.Integer"
      } else {
        "Double"
      },
    }.to_ir(false)
    return @ir.Type::Reference(
      attrs,
      @ir.FQName::parse("morphir/SDK:maybe#maybe"),
      [item],
    )
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
        UnboundedInteger | SdkInteger => "morphir/SDK:basics#int"
        OptionalSdkInteger | OptionalDouble => abort("optional handled above")
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
  if mode == NumericSdk && ty is Some(@ast.Option(ty=inner, ..)) {
    let inner = library_type(Some(inner), inner.loc(), mode)
    let scalar = match inner.scalar {
      SdkInteger => LibraryScalar::OptionalSdkInteger
      Floating64 => OptionalDouble
      _ => {
        reject(
          "unsupported_type", "Only SDK Integer? and Double? are qualified optional boundaries",
          loc,
        )
        abort("unreachable")
      }
    }
    return {
      scalar,
      spelling: inner.spelling + "?",
      source: span(loc),
      profile: mode.profile(),
    }
  }
  guard ty is Some(@ast.Name(constr_id~, tys~, ..)) && tys.is_empty() else {
    reject(
      "unsupported_type", "An explicit supported scalar annotation is required",
      loc,
    )
    abort("unreachable")
  }
  let name = match constr_id.id {
    @ast.Ident(name~) => name
    @ast.Dot(pkg="integer", id="Integer") if mode == NumericSdk =>
      "@integer.Integer"
    _ => {
      reject("unsupported_type", "An audited source type is required", loc)
      abort("unreachable")
    }
  }
  let scalar = match name {
    "@integer.Integer" if mode == NumericSdk => LibraryScalar::SdkInteger
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
pub const CURRENT_LIBRARY_PROFILE : String = "moonbit-model-library-2026-10-19-r3"

///|
pub const NUMERIC_SDK_LIBRARY_PROFILE : String = "moonbit-model-library-2026-10-19-r3"

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
  self == NumericSdk ||
  self == NumericMath ||
  self == StringBasics ||
  self == SupportedLibrary ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017 ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_int32(self : LibraryMode) -> Bool {
  self == NumericSdk ||
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
  self == NumericSdk ||
  self == NumericMath ||
  self == NumericInt32 ||
  self == NumericInteger ||
  self == NumericFloat ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_float(self : LibraryMode) -> Bool {
  self == NumericFloat || self == NumericMath || self == NumericSdk
}

///|
fn LibraryMode::supports_integer(self : LibraryMode) -> Bool {
  self == NumericInteger || self == NumericMath || self == NumericSdk
}

///|
fn LibraryMode::supports_string_order(self : LibraryMode) -> Bool {
  self == NumericSdk ||
  self == NumericMath ||
  self == SupportedLibraryV2 ||
  self == SupportedLibrary20261017 ||
  self == SupportedLibrary20261019
}

///|
fn LibraryMode::supports_string_index(self : LibraryMode) -> Bool {
  self == SupportedLibrary20261019 || self == NumericMath || self == NumericSdk
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
    NumericSdk => NUMERIC_SDK_LIBRARY_PROFILE
  }
}

///|
pub(all) enum ScalarProfile {
  StrictJsonScalars
  IntegerTokenAsInt
} derive(Eq, Debug)

///|
pub(all) enum ScalarDecodeReason {
  UnsupportedType
  UnsupportedRefinement
  NumericLimit
  WorkLimit
  CyclicAlias
} derive(Eq, Debug)

///|
pub(all) enum ScalarDecode {
  Decoded(@model.Literal)
  Ambiguous(Array[@model.Literal])
  Rejected
  Unsupported(ScalarDecodeReason)
} derive(Eq, Debug)

///|
pub extend ScalarProfile with Eq::{equal, not_equal}

///|
pub extend ScalarProfile with @debug.Debug::{to_repr}

///|
pub extend ScalarDecodeReason with Eq::{equal, not_equal}

///|
pub extend ScalarDecodeReason with @debug.Debug::{to_repr}

///|
pub extend ScalarDecode with Eq::{equal, not_equal}

///|
pub extend ScalarDecode with @debug.Debug::{to_repr}

///|
pub fn ScalarProfile::parse(
  name : String,
) -> ScalarProfile raise @wire.CodecError {
  match name {
    "strict-json-scalars" => StrictJsonScalars
    "integer-token-as-int" => IntegerTokenAsInt
    _ => raise @wire.Invalid("unsupported_scalar_profile", name)
  }
}

///|
/// Decode the native Bool/String/Int/Float scalar subset. Aliases, opaque types and
/// runtime predicates are unsupported. Decimal/exponent integral values can be Int.
/// Numbers are limited to fifteen significant decimal digits, magnitude <= 10^15-1,
/// and finite binary64 Float interpretation. IntegerTokenAsInt maps every integral
/// JSON number to Int, including decimal/exponent spellings, independently of arm order.
/// Limits: 16384 UTF-16 input units, 1024 JSON nodes, 64 levels, 256 type visits.
pub fn decode_scalar_json(
  text : String,
  t : @model.Type,
  profile : ScalarProfile,
) -> ScalarDecode raise @wire.CodecError {
  if text.length() > 16384 {
    return Unsupported(WorkLimit)
  }
  let json = @wire.parse_bounded(
    text,
    max_depth=64,
    max_nodes=1024,
    max_string_units=16384,
  )
  scalar_resolve(
    scalar_attempt(json, t, profile, Map([]), [], { val: 256, }, 0),
  )
}

///|
fn scalar_resolve(attempts : ScalarAttempts) -> ScalarDecode {
  if attempts.values.length() > 1 {
    return Ambiguous(attempts.values)
  }
  if attempts.unknown is Some(reason) {
    return Unsupported(reason)
  }
  match attempts.values {
    [v] => Decoded(v)
    _ => Rejected
  }
}

///|
/// Visible, zero-parameter transparent aliases from an existing IR environment.
/// Opaque/custom/derived types and parameterized aliases remain unsupported.
pub struct ScalarDecoder {
  priv aliases : Map[String, @model.Type]
  priv profile : ScalarProfile
}

///|
pub fn ScalarDecoder::from(
  file : @model.IRFile,
  profile : ScalarProfile,
) -> ScalarDecoder {
  let aliases = Map([])
  let definitions = (
    package_name : @model.PackageName,
    d : @model.PackageDefinition,
    public_only : Bool,
  ) => {
    for module_name, m in d.modules {
      if public_only && m.access is Private {
        continue
      }
      for local_name, d in m.value.types {
        if public_only && d.access is Private {
          continue
        }
        if d.value.value is TypeAliasDefinition([], t) {
          let n : @model.FQName = { package_name, module_name, local_name, }
          aliases[n.to_canonical()] = t
        }
      }
    }
  }
  let specifications = (
    package_name : @model.PackageName,
    s : @model.PackageSpecification,
  ) => {
    for module_name, m in s.modules {
      for local_name, d in m.types {
        if d.value.body is TypeAliasSpecification([], t) {
          let n : @model.FQName = { package_name, module_name, local_name, }
          aliases[n.to_canonical()] = t
        }
      }
    }
  }
  match file.distribution {
    Library(n, deps, d) => {
      definitions(n, d, false)
      for n, s in deps {
        specifications(n, s)
      }
    }
    Specs(n, deps, s) => {
      specifications(n, s)
      for n, s in deps {
        specifications(n, s)
      }
    }
    Application(n, deps, d, _) => {
      for name, dependency in deps {
        definitions(name, dependency, true)
      }
      definitions(n, d, false)
    }
  }
  { aliases, profile, }
}

///|
/// Uses the same bounded scalar profile, retaining obligations at every alias occurrence.
pub fn ScalarDecoder::decode(
  self : ScalarDecoder,
  text : String,
  t : @model.Type,
) -> ScalarDecode raise @wire.CodecError {
  if text.length() > 16384 {
    return Unsupported(WorkLimit)
  }
  let json = @wire.parse_bounded(
    text,
    max_depth=64,
    max_nodes=1024,
    max_string_units=16384,
  )
  scalar_resolve(
    scalar_attempt(json, t, self.profile, self.aliases, [], { val: 256, }, 0),
  )
}

///|
priv struct ScalarAttempts {
  values : Array[@model.Literal]
  unknown : ScalarDecodeReason?
}

///|
fn scalar_attempt(
  json : Json,
  t : @model.Type,
  profile : ScalarProfile,
  aliases : Map[String, @model.Type],
  trail : Array[String],
  budget : Ref[Int32],
  depth : Int32,
) -> ScalarAttempts {
  if depth > 64 || budget.val <= 0 {
    return { values: [], unknown: Some(WorkLimit), }
  }
  budget.val -= 1
  let attributes = match t {
    Variable(a, _)
    | Reference(a, _, _)
    | Tuple(a, _)
    | Union(a, _)
    | Record(a, _)
    | ExtensibleRecord(a, _, _)
    | Function(a, _, _)
    | Unit(a) => a
  }
  let attempts : ScalarAttempts = match t {
    Union(_, alternatives) if alternatives.length() >= 2 => {
      let values = []
      let mut unknown = None
      for alternative in alternatives {
        let next = scalar_attempt(
          json,
          alternative,
          profile,
          aliases,
          trail,
          budget,
          depth + 1,
        )
        for value in next.values {
          if !values.contains(value) {
            values.push(value)
          }
        }
        if next.unknown is Some(_) {
          unknown = next.unknown
        }
        if budget.val <= 0 {
          unknown = Some(WorkLimit)
          break
        }
      }
      { values, unknown, }
    }
    Reference(_, name, []) => {
      let key = name.to_canonical()
      match aliases.get(key) {
        Some(body) =>
          if trail.contains(key) {
            { values: [], unknown: Some(CyclicAlias), }
          } else {
            scalar_attempt(
              json,
              body,
              profile,
              aliases,
              [..trail, key],
              budget,
              depth + 1,
            )
          }
        None => scalar_primitive(json, key, profile)
      }
    }
    _ => { values: [], unknown: Some(UnsupportedType), }
  }
  let extensions = attributes.extensions.copy()
  if extensions.get("example/union:provenance#note") is Some(Text(_)) {
    extensions.remove("example/union:provenance#note")
  }
  if !attributes.constraints.is_empty() || !extensions.is_empty() {
    if !attempts.values.is_empty() || attempts.unknown is Some(_) {
      return { values: [], unknown: Some(UnsupportedRefinement), }
    }
  }
  attempts
}

///|
fn scalar_primitive(
  json : Json,
  name : String,
  profile : ScalarProfile,
) -> ScalarAttempts {
  let rejected : ScalarAttempts = { values: [], unknown: None, }
  let one = v => ScalarAttempts::{ values: [v], unknown: None, }
  match name {
    "morphir/SDK:string#string" =>
      match json {
        String(s) => one(@model.StringLiteral(s))
        _ => rejected
      }
    "morphir/SDK:basics#bool" =>
      match json {
        True => one(@model.BoolLiteral(true))
        False => one(@model.BoolLiteral(false))
        _ => rejected
      }
    "morphir/SDK:basics#int" | "morphir/SDK:basics#float" => {
      guard json is Number(value, ..) else { return rejected }
      let text = @wire.number_text(json) catch {
        _ => return { values: [], unknown: Some(NumericLimit), }
      }
      if name == "morphir/SDK:basics#float" &&
        profile == IntegerTokenAsInt &&
        @wire.is_integral_number(json) {
        return rejected
      }
      if name == "morphir/SDK:basics#int" && !@wire.is_integral_number(json) {
        return rejected
      }
      let mut digits = 0
      let mut started = false
      for c in text {
        if c == 'e' || c == 'E' {
          break
        }
        if c >= '0' && c <= '9' {
          if c != '0' {
            started = true
          }
          if started {
            digits += 1
          }
        }
      }
      if digits > 15 ||
        (started && value == 0.0) ||
        value.is_nan() ||
        value.is_inf() ||
        value > 999999999999999.0 ||
        value < -999999999999999.0 {
        return { values: [], unknown: Some(NumericLimit), }
      }
      if name == "morphir/SDK:basics#int" {
        one(@model.IntegerLiteral(value.to_int64().to_string()))
      } else {
        one(@model.FloatLiteral(value))
      }
    }
    _ => { values: [], unknown: Some(UnsupportedType), }
  }
}

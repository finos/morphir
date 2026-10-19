// Based on finos/morphir's v4 semantic model and schema.
// Copyright 2026 FINOS. SPDX-License-Identifier: Apache-2.0

///|
pub(all) struct SourceLocation {
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
} derive(Eq, Debug)

///|
pub(all) struct TypeAttributes {
  source : SourceLocation?
  constraints : Map[String, Data]
  extensions : Map[String, Data]
} derive(Eq, Debug, Default)

///|
/// The extension key of the inference marker.
pub const INFERENCE_EXTENSION : String = "morphir.inference"

///|
/// The value of `INFERENCE_EXTENSION` on a type variable that inference may solve to any type.
pub const UNKNOWN_MARKER : String = "unknown"

///|
/// Whether the attributes carry the unknown marker. A variable with the marker is not rigid: inference may solve
/// it to any type. An extensible record with the marker has an unknown row variable.
pub fn TypeAttributes::is_unknown(self : TypeAttributes) -> Bool {
  self.extensions.get(INFERENCE_EXTENSION) is Some(Text(UNKNOWN_MARKER))
}

///|
/// The attributes with the unknown marker added. The other extensions stay.
pub fn TypeAttributes::with_unknown(self : TypeAttributes) -> TypeAttributes {
  let extensions = self.extensions.copy()
  extensions[INFERENCE_EXTENSION] = Text(UNKNOWN_MARKER)
  { ..self, extensions, }
}

///|
/// Whether `name` is a morphir-elm let placeholder: `t-` and one or more digits, as in `t-8`. Classic IR cannot
/// carry the unknown marker, so on such a variable the name has the same meaning.
pub fn is_classic_placeholder_name(name : Name) -> Bool {
  match name.to_canonical() {
    [.. "t-", .. rest] if rest.length() > 0 =>
      rest.iter().all(c => c >= '0' && c <= '9')
    _ => false
  }
}

///|
pub(all) struct ValueAttributes {
  source : SourceLocation?
  inferred_type : Type?
  extensions : Map[String, Data]
} derive(Eq, Debug, Default)

///|
pub(all) enum Type {
  Variable(TypeAttributes, Name)
  Reference(TypeAttributes, FQName, Array[Type])
  Tuple(TypeAttributes, Array[Type])
  /// Inclusive alternatives, retaining authored order and duplicates. Codecs require at least two entries.
  Union(TypeAttributes, Array[Type])
  Record(TypeAttributes, Map[Name, Type])
  ExtensibleRecord(TypeAttributes, Name, Map[Name, Type])
  Function(TypeAttributes, Type, Type)
  Unit(TypeAttributes)
} derive(Eq, Debug)

///|
pub type Constructors = Map[Name, Array[(Name, Type)]]

///|
pub(all) enum Annotation {
  Compact(FQName, String?)
  Structured(FQName, Array[AnnotationArgument])
} derive(Eq, Debug)

///|
pub(all) enum AnnotationArgument {
  Positional(Value)
  Named(Name, Value)
} derive(Eq, Debug)

///|
pub(all) struct TypeSpecification {
  annotations : Array[Annotation]
  body : TypeSpecificationBody
} derive(Eq, Debug)

///|
pub(all) enum TypeSpecificationBody {
  TypeAliasSpecification(Array[Name], Type)
  OpaqueTypeSpecification(Array[Name])
  CustomTypeSpecification(Array[Name], Constructors)
  DerivedTypeSpecification(Array[Name], DerivedTypeDetails)
} derive(Eq, Debug)

///|
pub(all) struct DerivedTypeDetails {
  base_type : Type
  from_base_type : FQName
  to_base_type : FQName
} derive(Eq, Debug)

///|
pub(all) enum TypeDefinition {
  TypeAliasDefinition(Array[Name], Type)
  CustomTypeDefinition(Array[Name], AccessControlled[Constructors])
  IncompleteTypeDefinition(Array[Name], Incompleteness, Type?)
} derive(Eq, Debug)

///|
pub(all) enum HoleReason {
  UnresolvedReference(FQName)
  DeletedDuringRefactor(String)
  TypeMismatch(String, String)
} derive(Eq, Debug)

///|
pub(all) enum Incompleteness {
  Hole(HoleReason, Type?)
  Draft
} derive(Eq, Debug)

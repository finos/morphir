//// Type representation for the Morphir IR.
//// This module defines the types for representing type expressions in the IR,
//// including variables, references, tuples, records, functions, and more.

import gleam/dict.{type Dict}
import morphir/ir/access_controlled.{type AccessControlled}
import morphir/ir/fqname.{type FQName}
import morphir/ir/name.{type Name}

/// A field in a record type.
pub type Field(a) {
  Field(name: Name, tpe: Type(a))
}

/// A type expression in the Morphir IR.
/// The type parameter `a` represents attributes (like source location info).
pub type Type(a) {
  /// A type variable (e.g., `a` in `List a`)
  Variable(attributes: a, name: Name)

  /// A reference to a named type with type arguments
  /// (e.g., `List Int` or `Dict String Value`)
  Reference(attributes: a, type_name: FQName, type_arguments: List(Type(a)))

  /// A tuple type (e.g., `#(Int, String)`)
  Tuple(attributes: a, element_types: List(Type(a)))

  /// A record type with named fields (e.g., `{ name: String, age: Int }`)
  Record(attributes: a, fields: List(Field(a)))

  /// An extensible record type (e.g., `{ a | name: String }`)
  ExtensibleRecord(attributes: a, variable_name: Name, fields: List(Field(a)))

  /// A function type (e.g., `Int -> String`)
  Function(attributes: a, argument_type: Type(a), return_type: Type(a))

  /// The unit type
  Unit(attributes: a)
}

/// Constructor arguments: a list of (name, type) pairs.
pub type ConstructorArgs(a) =
  List(#(Name, Type(a)))

/// Constructors for a custom type: a dictionary from constructor name to its arguments.
pub type Constructors(a) =
  Dict(Name, ConstructorArgs(a))

/// Details for a derived type specification.
pub type DerivedTypeSpecificationDetails(a) {
  DerivedTypeSpecificationDetails(
    base_type: Type(a),
    from_base_type: FQName,
    to_base_type: FQName,
  )
}

/// Type specification - the public interface of a type.
pub type Specification(a) {
  /// A type alias specification (e.g., `type alias UserId = String`)
  TypeAliasSpecification(type_params: List(Name), tpe: Type(a))

  /// An opaque type specification (only the type parameters are visible)
  OpaqueTypeSpecification(type_params: List(Name))

  /// A custom type specification (all constructors are visible)
  CustomTypeSpecification(
    type_params: List(Name),
    constructors: Constructors(a),
  )

  /// A derived type specification (a type derived from a base type)
  DerivedTypeSpecification(
    type_params: List(Name),
    details: DerivedTypeSpecificationDetails(a),
  )
}

/// Type definition - the full implementation of a type.
pub type Definition(a) {
  /// A type alias definition
  TypeAliasDefinition(type_params: List(Name), tpe: Type(a))

  /// A custom type definition with access-controlled constructors
  CustomTypeDefinition(
    type_params: List(Name),
    constructors: AccessControlled(Constructors(a)),
  )
}

/// One named constructor and its arguments.
pub type Constructor(a) =
  #(Name, ConstructorArgs(a))

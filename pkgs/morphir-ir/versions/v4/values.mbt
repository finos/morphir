// Based on finos/morphir's v4 semantic model and schema.
// Copyright 2026 FINOS. SPDX-License-Identifier: Apache-2.0

///|
/// Integers and decimals retain their original lexemes, including arbitrary precision.
#derive(Eq, Debug)
pub(all) enum Literal {
  BoolLiteral(Bool)
  CharLiteral(Char)
  StringLiteral(String)
  IntegerLiteral(String)
  FloatLiteral(Double)
  DecimalLiteral(String)
  DocumentLiteral(Data)
}

///|
/// Document literals cannot occur in a literal pattern.
#derive(Eq, Debug)
pub(all) enum PatternLiteral {
  BoolLiteral(Bool)
  CharLiteral(Char)
  StringLiteral(String)
  IntegerLiteral(String)
  FloatLiteral(Double)
  DecimalLiteral(String)
}

///|
#derive(Eq, Debug)
pub(all) enum Pattern {
  WildcardPattern(ValueAttributes)
  AsPattern(ValueAttributes, Pattern, Name)
  TuplePattern(ValueAttributes, Array[Pattern])
  ConstructorPattern(ValueAttributes, FQName, Array[Pattern])
  EmptyListPattern(ValueAttributes)
  HeadTailPattern(ValueAttributes, Pattern, Pattern)
  LiteralPattern(ValueAttributes, PatternLiteral)
  UnitPattern(ValueAttributes)
}

///|
#derive(Eq, Debug)
pub(all) enum Value {
  Literal(ValueAttributes, Literal)
  Constructor(ValueAttributes, FQName)
  Tuple(ValueAttributes, Array[Value])
  List(ValueAttributes, Array[Value])
  Record(ValueAttributes, Map[Name, Value])
  Variable(ValueAttributes, Name)
  Reference(ValueAttributes, FQName)
  Field(ValueAttributes, Value, Name)
  FieldFunction(ValueAttributes, Name)
  Apply(ValueAttributes, Value, Value)
  Lambda(ValueAttributes, Pattern, Value)
  LetDefinition(ValueAttributes, Name, ValueDefinition, Value)
  LetRecursion(ValueAttributes, Map[Name, ValueDefinition], Value)
  Destructure(ValueAttributes, Pattern, Value, Value)
  IfThenElse(ValueAttributes, Value, Value, Value)
  PatternMatch(ValueAttributes, Value, Array[(Pattern, Value)])
  UpdateRecord(ValueAttributes, Value, Map[Name, Value])
  Unit(ValueAttributes)
  Hole(ValueAttributes, HoleReason, Type?)
}

///|
#derive(Eq, Debug)
pub(all) struct ValueSpecification {
  annotations : Array[Annotation]
  inputs : Array[(Name, Type)]
  output : Type
}

///|
/// Ordered inputs preserve parameter order independently of any wire map spelling.
#derive(Eq, Debug)
pub(all) enum ValueDefinition {
  ExpressionBody(Array[(Name, Type)], Type, Value)
  NativeBody(Array[(Name, Type)], Type, NativeInfo)
  ExternalBody(Array[(Name, Type)], Type, Array[ExternalBinding], Value?)
  IncompleteBody(Array[(Name, Type)], Type?, Incompleteness, Value?)
}

///|
#derive(Eq, Debug)
pub(all) struct ExternalBinding {
  target_platform : String
  external_name : String
}

///|
#derive(Eq, Debug)
pub(all) struct NativeInfo {
  hint : NativeHint
  description : String?
}

///|
#derive(Eq, Debug)
pub(all) enum NativeHint {
  Arithmetic
  Comparison
  StringOp
  CollectionOp
  PlatformSpecific(String)
}

///|
/// Incomplete definitions without an output type do not yet have a specification.
pub fn ValueDefinition::to_specification(
  self : ValueDefinition,
) -> ValueSpecification? {
  match self {
    ExpressionBody(inputs, output, _)
    | NativeBody(inputs, output, _)
    | ExternalBody(inputs, output, _, _)
    | IncompleteBody(inputs, Some(output), _, _) =>
      Some({ annotations: [], inputs, output, })
    IncompleteBody(_, None, _, _) => None
  }
}

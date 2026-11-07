// Adapted from Morphir.IR.Value and Morphir.IR.Literal in finos/morphir-elm.
// Copyright 2020 Morgan Stanley. Copyright 2026 FINOS.
// SPDX-License-Identifier: Apache-2.0

///|
/// Integer and decimal lexemes retain their precision and decimal scale.
#derive(Eq, Debug)
pub(all) enum Literal {
  BoolLiteral(Bool)
  CharLiteral(Char)
  StringLiteral(String)
  WholeNumberLiteral(String)
  FloatLiteral(Double)
  DecimalLiteral(String)
}

///|
#derive(Eq, Debug)
pub(all) enum Pattern[A] {
  WildcardPattern(A)
  AsPattern(A, Pattern[A], Name)
  TuplePattern(A, Array[Pattern[A]])
  ConstructorPattern(A, FQName, Array[Pattern[A]])
  EmptyListPattern(A)
  HeadTailPattern(A, Pattern[A], Pattern[A])
  LiteralPattern(A, Literal)
  UnitPattern(A)
}

///|
#derive(Eq, Debug)
pub(all) enum Value[TA, VA] {
  Literal(VA, Literal)
  Constructor(VA, FQName)
  Tuple(VA, Array[Value[TA, VA]])
  List(VA, Array[Value[TA, VA]])
  Record(VA, Map[Name, Value[TA, VA]])
  Variable(VA, Name)
  Reference(VA, FQName)
  Field(VA, Value[TA, VA], Name)
  FieldFunction(VA, Name)
  Apply(VA, Value[TA, VA], Value[TA, VA])
  Lambda(VA, Pattern[VA], Value[TA, VA])
  LetDefinition(VA, Name, ValueDefinition[TA, VA], Value[TA, VA])
  LetRecursion(VA, Map[Name, ValueDefinition[TA, VA]], Value[TA, VA])
  Destructure(VA, Pattern[VA], Value[TA, VA], Value[TA, VA])
  IfThenElse(VA, Value[TA, VA], Value[TA, VA], Value[TA, VA])
  PatternMatch(VA, Value[TA, VA], Array[(Pattern[VA], Value[TA, VA])])
  UpdateRecord(VA, Value[TA, VA], Map[Name, Value[TA, VA]])
  Unit(VA)
}

///|
pub type RawValue = Value[Unit, Unit]

///|
pub type TypedValue = Value[Unit, Type[Unit]]

///|
#derive(Eq, Debug)
pub(all) struct ValueSpecification[TA] {
  inputs : Array[(Name, Type[TA])]
  output : Type[TA]
}

///|
#derive(Eq, Debug)
pub(all) struct ValueDefinition[TA, VA] {
  input_types : Array[(Name, VA, Type[TA])]
  output_type : Type[TA]
  body : Value[TA, VA]
}

///|
pub fn[TA, VA] ValueDefinition::to_specification(
  self : ValueDefinition[TA, VA],
) -> ValueSpecification[TA] {
  {
    inputs: self.input_types.map(input => (input.0, input.2)),
    output: self.output_type,
  }
}

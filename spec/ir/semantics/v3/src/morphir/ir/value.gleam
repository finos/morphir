//// Value representation for the Morphir IR.
//// This module defines the types for representing value expressions (business logic)
//// in the IR, including literals, function applications, pattern matching, and more.

import gleam/dict.{type Dict}
import morphir/ir/fqname.{type FQName}
import morphir/ir/literal.{type Literal}
import morphir/ir/name.{type Name}
import morphir/ir/type_.{type Type}

/// A pattern for pattern matching.
/// The type parameter `a` represents attributes (like source location info).
pub type Pattern(a) {
  /// Matches anything without binding (the `_` pattern)
  WildcardPattern(attributes: a)

  /// Matches anything and binds it to a name (e.g., `x` or `_ as x`)
  AsPattern(attributes: a, pattern: Pattern(a), name: Name)

  /// Matches a tuple pattern (e.g., `#(a, b)`)
  TuplePattern(attributes: a, element_patterns: List(Pattern(a)))

  /// Matches a constructor pattern (e.g., `Ok(value)` or `Some(x)`)
  ConstructorPattern(
    attributes: a,
    constructor_name: FQName,
    argument_patterns: List(Pattern(a)),
  )

  /// Matches an empty list
  EmptyListPattern(attributes: a)

  /// Matches a non-empty list (e.g., `[head, ..tail]`)
  HeadTailPattern(
    attributes: a,
    head_pattern: Pattern(a),
    tail_pattern: Pattern(a),
  )

  /// Matches a literal value
  LiteralPattern(attributes: a, value: Literal)

  /// Matches the unit value
  UnitPattern(attributes: a)
}

/// A value definition (function or constant implementation).
/// - `ta` is the type attributes
/// - `va` is the value attributes
pub type Definition(ta, va) {
  Definition(
    input_types: List(#(Name, va, Type(ta))),
    output_type: Type(ta),
    body: Value(ta, va),
  )
}

/// A value specification (type signature without implementation).
pub type Specification(a) {
  Specification(inputs: List(#(Name, Type(a))), output: Type(a))
}

/// A value expression in the Morphir IR.
/// - `ta` is the type attributes
/// - `va` is the value attributes
pub type Value(ta, va) {
  /// A literal value (number, string, bool, etc.)
  Literal(attributes: va, value: Literal)

  /// A constructor reference (e.g., `Ok`, `Some`, `Nil`)
  Constructor(attributes: va, constructor_name: FQName)

  /// A tuple value (e.g., `#(1, "hello")`)
  Tuple(attributes: va, elements: List(Value(ta, va)))

  /// A list value (e.g., `[1, 2, 3]`)
  List(attributes: va, items: List(Value(ta, va)))

  /// A record value (e.g., `{ name: "John", age: 30 }`)
  Record(attributes: va, fields: Dict(Name, Value(ta, va)))

  /// A variable reference
  Variable(attributes: va, name: Name)

  /// A reference to a named value
  Reference(attributes: va, value_name: FQName)

  /// Field access on a record (e.g., `person.name`)
  Field(attributes: va, record: Value(ta, va), field_name: Name)

  /// A field function (e.g., `.name` as a function)
  FieldFunction(attributes: va, field_name: Name)

  /// Function application (e.g., `f(x)`)
  Apply(attributes: va, function: Value(ta, va), argument: Value(ta, va))

  /// Lambda expression (e.g., `fn(x) { x + 1 }`)
  Lambda(attributes: va, argument_pattern: Pattern(va), body: Value(ta, va))

  /// Let binding (e.g., `let x = 1 in x + 1`)
  LetDefinition(
    attributes: va,
    name: Name,
    definition: Definition(ta, va),
    in_value: Value(ta, va),
  )

  /// Recursive let bindings (e.g., mutually recursive functions)
  LetRecursion(
    attributes: va,
    definitions: Dict(Name, Definition(ta, va)),
    in_value: Value(ta, va),
  )

  /// Destructuring bind (e.g., `let #(a, b) = pair in a + b`)
  Destructure(
    attributes: va,
    pattern: Pattern(va),
    value_to_destructure: Value(ta, va),
    in_value: Value(ta, va),
  )

  /// Conditional expression (if-then-else)
  IfThenElse(
    attributes: va,
    condition: Value(ta, va),
    then_branch: Value(ta, va),
    else_branch: Value(ta, va),
  )

  /// Pattern matching expression (case/match)
  PatternMatch(
    attributes: va,
    value: Value(ta, va),
    cases: List(#(Pattern(va), Value(ta, va))),
  )

  /// Record update (e.g., `{ person | name: "Jane" }`)
  UpdateRecord(
    attributes: va,
    record: Value(ta, va),
    fields_to_update: Dict(Name, Value(ta, va)),
  )

  /// The unit value
  Unit(attributes: va)
}

/// An expression with no type or value attributes.
pub type RawValue =
  Value(Nil, Nil)

/// An expression annotated with its inferred types.
pub type TypedValue =
  Value(Nil, Type(Nil))

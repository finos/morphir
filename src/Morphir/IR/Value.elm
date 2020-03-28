module Morphir.IR.Value exposing
    ( Value, literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
    , tuple, variable, ifThenElse, patternMatch, update, unit
    , Literal, boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral
    , Pattern, wildcardPattern, asPattern, tuplePattern, recordPattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern
    , Specification
    , Definition, typedDefinition, untypedDefinition
    )

{-| This module contains the building blocks of values in the Morphir IR.


# Value

Value is the top level building block for data and logic. See the constructor functions below for details on each node type.

@docs Value, literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
@docs tuple, variable, ifThenElse, patternMatch, update, unit


# Literal

Literals represent fixed values in the IR. We support the same set of basic types as Elm which almost matches JSON's supported values:

  - Bool
  - Char
  - String
  - Int
  - Float

@docs Literal, boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral


# Pattern

Patterns are used in multiple ways in the IR: they can take apart a structured value into smaller pieces (destructure) and they
can also filter values. The combination of these two features creates a very powerful method tool that can be used in two ways:
destructuring and pattern-matching. Pattern-matching is a combination of destructuring, filtering and branching.

@docs Pattern, wildcardPattern, asPattern, tuplePattern, recordPattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern


# Specification

The specification of what the value or function
is without the actual data or logic behind it.

@docs Specification


# Definition

A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.

@docs Definition, typedDefinition, untypedDefinition

-}

import Morphir.IR.Advanced.Value as Advanced
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type exposing (Type)


{-| Type that represents a value.
-}
type alias Value =
    Advanced.Value ()


{-| Type that represents a literal value.
-}
type alias Literal =
    Advanced.Literal


{-| Type that represents a pattern.
-}
type alias Pattern =
    Advanced.Pattern ()


{-| Type that represents a value or function specification. The specification of what the value or function
is without the actual data or logic behind it.
-}
type alias Specification =
    Advanced.Specification ()


{-| Type that represents a value or function definition. A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.
-}
type alias Definition =
    Advanced.Definition ()


{-| A [literal][lit] represents a fixed value in the IR. We only allow values of basic types: bool, char, string, int, float.

    True -- Literal (BoolLiteral True)

    'a' -- Literal (CharLiteral 'a')

    "foo" -- Literal (StringLiteral "foo")

    13 -- Literal (IntLiteral 13)

    15.4 -- Literal (FloatLiteral 15.4)

[lit]: https://en.wikipedia.org/wiki/Literal_(computer_programming)

-}
literal : Literal -> Value
literal value =
    Advanced.literal value ()


{-| A reference to a constructor of a custom type.

    Nothing -- Constructor ( ..., [ [ "maybe" ] ], [ "nothing" ] )

    Foo.Bar -- Constructor ( ..., [ [ "foo" ] ], [ "bar" ] )

-}
constructor : FQName -> Value
constructor fullyQualifiedName =
    Advanced.constructor fullyQualifiedName ()


{-| A [tuple] represents an ordered list of values where each value can be of a different type.

**Note**: Tuples with zero values are considered to be the special value [`Unit`](#unit)

    ( 1, True ) -- Tuple [ Literal (IntLiteral 1), Literal (BoolLiteral True) ]

    ( "foo", True, 3 ) -- Tuple [ Literal (StringLiteral "foo"), Literal (BoolLiteral True), Literal (IntLiteral 3) ]

    () -- Unit

[tuple]: https://en.wikipedia.org/wiki/Tuple

-}
tuple : List Value -> Value
tuple elements =
    Advanced.tuple elements ()


{-| A [list] represents an ordered list of values where every value has to be of the same type.

    [ 1, 3, 5 ] -- List [ Literal (IntLiteral 1), Literal (IntLiteral 3), Literal (IntLiteral 5) ]

    [] -- List []

[list]: https://en.wikipedia.org/wiki/List_(abstract_data_type)

-}
list : List Value -> Value
list items =
    Advanced.list items ()


{-| A [record] represents a list of fields where each field has a name and a value.

    { foo = "bar" } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ) ]

    { foo = "bar", baz = 1 } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ), ( [ "baz" ], Literal (IntLiteral 1) ) ]

    {} -- Record []

[record]: https://en.wikipedia.org/wiki/Record_(computer_science)

-}
record : List ( Name, Value ) -> Value
record fields =
    Advanced.record fields ()


{-| A [variable] represents a reference to a named value in the scope.

    a -- Variable [ "a" ]

    fooBar15 -- Variable [ "foo", "bar", "15" ]

[variable]: https://en.wikipedia.org/wiki/Variable_(computer_science)

-}
variable : Name -> Value
variable name =
    Advanced.variable name ()


{-| A reference that refers to a function or a value with its fully-qualified name.

    List.map -- Reference ( [ ..., [ [ "list" ] ], [ "map" ] )

-}
reference : FQName -> Value
reference fullyQualifiedName =
    Advanced.reference fullyQualifiedName ()


{-| Extracts the value of a record's field.

    a.foo -- Field (Variable [ "a" ]) [ "foo" ]

-}
field : Value -> Name -> Value
field subjectValue fieldName =
    Advanced.field subjectValue fieldName ()


{-| Represents a function that extract a field from a record value passed to it.

    .foo -- FieldFunction [ "foo" ]

-}
fieldFunction : Name -> Value
fieldFunction fieldName =
    Advanced.fieldFunction fieldName ()


{-| Represents a function invocation. We use currying to represent function invocations with multiple arguments.

**Note**: Operators are mapped to well-known function names.

    not True -- Apply (Reference ( ..., [ [ "basics" ] ], [ "not" ])) (Literal (BoolLiteral True))

    True || False -- Apply (Apply (Reference ( ..., [ [ "basics" ] ], [ "and" ]))) (Literal (BoolLiteral True)) (Literal (BoolLiteral True))

-}
apply : Value -> Value -> Value
apply function argument =
    Advanced.apply function argument ()


{-| Represents a lambda abstraction.

**Note**:

  - We use currying to represent lambda abstractions with multiple arguments.
  - Arguments are not just names, they are patterns.

```
\a -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Variable [ "a" ])

\a b -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Lambda (AsPattern WildcardPattern [ "b" ]) (Variable [ "a" ]))
```

-}
lambda : Pattern -> Value -> Value
lambda argumentPattern body =
    Advanced.lambda argumentPattern body ()


{-| Represents a let expression that assigns a value (and optionally type) to a name.

**Note**: We use currying to represent let expressions with multiple name bindings.

    let
        a =
            b
    in
    a
    -- LetDef [ "a" ]
    --     (UntypedDefinition [] (Variable [ "b" ]))
    --     (Variable [ "a" ])

    let
        a : Bool
        a =
            b

        c x =
            a
    in
    c
    -- LetDef [ "a" ]
    --     (TypedDefinition (Basic BoolType) [] (Variable [ "b" ]))
    --     (LetDef [ "c" ]
    --         (UntypedDefinition [ [ "x" ] ] (Variable [ "a" ]))
    --         (Variable [ "c" ])
    --     )

-}
letDef : Name -> Definition -> Value -> Value
letDef valueName valueDefinition inValue =
    Advanced.letDef valueName valueDefinition inValue ()


{-| Represents a let expression with one or many recursive definitions.

    let
        a =
            b

        b =
            a
    in
    a
    -- LetRec
    --     [ ( [ "a" ], UntypedDefinition [] (Variable [ "b" ]) )
    --     , ( [ "b" ], UntypedDefinition [] (Variable [ "a" ]) )
    --     ]
    --     (Variable [ "a" ])

-}
letRec : List ( Name, Definition ) -> Value -> Value
letRec valueDefinitions inValue =
    Advanced.letRec valueDefinitions inValue ()


{-| Represents a let expression that extracts values using a pattern.

    let
        ( a, b ) =
            c
    in
    a
    -- LetDestruct
    --     (TuplePattern [ AsPattern WildcardPattern ["a"], AsPattern WildcardPattern ["b"] ])
    --     (Variable ["a"])

-}
letDestruct : Pattern -> Value -> Value -> Value
letDestruct pattern valueToDestruct inValue =
    Advanced.letDestruct pattern valueToDestruct inValue ()


{-| Represents and if/then/else expression.

    if a then
        b
    else
        c
    -- IfThenElse (Variable ["a"])
    --     (Variable ["b"])
    --     (Variable ["c"])

-}
ifThenElse : Value -> Value -> Value -> Value
ifThenElse condition thenBranch elseBranch =
    Advanced.ifThenElse condition thenBranch elseBranch ()


{-| Represents a pattern-match.

    case a of
        1 ->
            "yea"

        _ ->
            "nay"
    -- PatternMatch (Variable ["a"])
    --     [ ( LiteralPattern (IntLiteral 1), Literal (StringLiteral "yea") )
    --     , ( WildcardPattern, Literal (StringLiteral "nay") )
    --     ]

-}
patternMatch : Value -> List ( Pattern, Value ) -> Value
patternMatch branchOutOn cases =
    Advanced.patternMatch branchOutOn cases ()


{-| Update one or many fields of a record value.

    { a | foo = 1 } -- Update (Variable ["a"]) [ ( ["foo"], Literal (IntLiteral 1) ) ]

-}
update : Value -> List ( Name, Value ) -> Value
update valueToUpdate fieldsToUpdate =
    Advanced.update valueToUpdate fieldsToUpdate ()


{-| Represents the unit value.

    () -- Unit

-}
unit : Value
unit =
    Advanced.unit ()


{-| Represents a boolean value. Only possible values are: `True`, `False`
-}
boolLiteral : Bool -> Literal
boolLiteral value =
    Advanced.boolLiteral value


{-| Represents a character value. Some possible values: `'a'`, `'Z'`, `'3'`
-}
charLiteral : Char -> Literal
charLiteral value =
    Advanced.charLiteral value


{-| Represents a string value. Some possible values: `""`, `"foo"`, `"Bar baz: 123"`
-}
stringLiteral : String -> Literal
stringLiteral value =
    Advanced.stringLiteral value


{-| Represents an integer value. Some possible values: `0`, `-1`, `9832479`
-}
intLiteral : Int -> Literal
intLiteral value =
    Advanced.intLiteral value


{-| Represents a floating-point number. Some possible values: `1.25`, `-13.4`
-}
floatLiteral : Float -> Literal
floatLiteral value =
    Advanced.floatLiteral value


{-| Matches any value and ignores it (assigns no variable name).

    _ -- WildcardPattern

-}
wildcardPattern : Pattern
wildcardPattern =
    Advanced.wildcardPattern ()


{-| Assigns a variable name to a pattern.

    _ as foo -- AsPattern WildcardPattern ["foo"]

    foo -- AsPattern WildcardPattern ["foo"]

    [] as foo -- AsPattern EmptyListPattern ["foo"]

-}
asPattern : Pattern -> Name -> Pattern
asPattern pattern name =
    Advanced.asPattern pattern name ()


{-| Destructures a tuple using a pattern for every element.

    ( _, foo ) -- TuplePattern [ WildcardPattern, AsPattern WildcardPattern ["foo"] ]

-}
tuplePattern : List Pattern -> Pattern
tuplePattern elementPatterns =
    Advanced.tuplePattern elementPatterns ()


{-| Pulls out the values of some fields from a record value.

    { foo, bar } -- RecordPattern [ ["foo"], ["bar"] ]

-}
recordPattern : List Name -> Pattern
recordPattern fieldNames =
    Advanced.recordPattern fieldNames ()


{-| Matches on a custom type's constructor.

**Note**: When the custom type has a single constructor this can be used for destructuring.
When there are multiple constructors it also does filtering so it cannot be used in a
[`LetDestruct`](#letDestruct) but it can be used in a [pattern-match](#patternMatch).

    Just _ -- ConstructorPattern ( ..., [["maybe"]], ["just"]) [ WildcardPattern ]

-}
constructorPattern : FQName -> List Pattern -> Pattern
constructorPattern constructorName argumentPatterns =
    Advanced.constructorPattern constructorName argumentPatterns ()


{-| Matches an empty list. Can be used standalon but frequently used as a terminal pattern
in a [`HeadTailPattern`](#headTailPattern).

    [] -- EmptyListPattern

    [ _ ]
    -- HeadTailPattern
    --     WildcardPattern
    --     EmptyListPattern

-}
emptyListPattern : Pattern
emptyListPattern =
    Advanced.emptyListPattern ()


{-| Matches the head and the tail of a list. It can be used to match lists of at least N items
by nesting this pattern N times and terminating with [`EmptyListPattern`](#emptyListPattern).

    [ a ]
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     EmptyListPattern

    a :: b
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     (AsPattern WildcardPattern ["b"])

    [ a, b ]
    -- HeadTailPattern
    --     (AsPattern WildcardPattern ["a"])
    --     (HeadTailPattern
    --         (AsPattern WildcardPattern ["b"])
    --         EmptyListPattern
    --     )

-}
headTailPattern : Pattern -> Pattern -> Pattern
headTailPattern headPattern tailPattern =
    Advanced.headTailPattern headPattern tailPattern ()


{-| Matches a specific literal value. This pattern can only be used in a [pattern-match](#patternMatch)
since it always filters.

    True -- LiteralPattern (BoolLiteral True)

    'a' -- LiteralPattern (CharLiteral 'a')

    "foo" -- LiteralPattern (StringLiteral "foo")

    13 -- LiteralPattern (IntLiteral 13)

    15.4 -- LiteralPattern (FloatLiteral 15.4)

-}
literalPattern : Literal -> Pattern
literalPattern value =
    Advanced.literalPattern value ()


{-| Typed value or function definition.

**Note**: Elm uses patterns instead of argument names which is flexible but makes it more
difficult to understand the model. Since most business models will actually use names which
is represented as `AsPattern WildcardPattern name` in the IR we will extract those into the
definition. This is a best-efforts process and stops when it runs into a more complex pattern.
When that happens the rest of the argument patterns will be pushed down to the body as lambda
arguments. The examples below try to visualize the process.

    myFun : Int -> Int -> { foo : Int } -> Int
    myFun a b { foo } =
        body

    -- the above is logically translated to the below
    myFun :
        Int
        -> Int
        -> { foo : Int }
        -> Int -- the value type does not change in the process
    myFun a b =
        \{ foo } ->
            body

-}
typedDefinition : Type -> List Name -> Value -> Definition
typedDefinition valueType argumentNames body =
    Advanced.typedDefinition valueType argumentNames body


{-| Untyped value or function definition.

**Note**: Elm uses patterns instead of argument names which is flexible but makes it more
difficult to understand the model. Since most business models will actually use names which
is represented as `AsPattern WildcardPattern name` in the IR we will extract those into the
definition. This is a best-efforts process and stops when it runs into a more complex pattern.
When that happens the rest of the argument patterns will be pushed down to the body as lambda
arguments. The examples below try to visualize the process.

    myFun a b { foo } =
        body

    -- the above is logically translated to the below
    myFun a b =
        \{ foo } ->
            body

-}
untypedDefinition : List Name -> Value -> Definition
untypedDefinition argumentNames body =
    Advanced.untypedDefinition argumentNames body

module Morphir.IR.Value exposing
    ( Value(..), literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
    , tuple, variable, ifThenElse, patternMatch, update, unit
    , Literal(..), boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral
    , Pattern(..), wildcardPattern, asPattern, tuplePattern, recordPattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern
    , Specification
    , Definition(..), typedDefinition, untypedDefinition
    , encodeValue, encodeSpecification, encodeDefinition
    , getDefinitionBody, mapDefinition, mapSpecification, mapValueExtra
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


# Serialization

@docs encodeValue, encodeSpecification, encodeDefinition

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName, decodeFQName, encodeFQName)
import Morphir.IR.Name exposing (Name, decodeName, encodeName)
import Morphir.IR.Type as Type exposing (Type, decodeType, encodeType)
import Morphir.ResultList as ResultList
import String


{-| Type that represents a value.
-}
type Value extra
    = Literal Literal extra
    | Constructor FQName extra
    | Tuple (List (Value extra)) extra
    | List (List (Value extra)) extra
    | Record (List ( Name, Value extra )) extra
    | Variable Name extra
    | Reference FQName extra
    | Field (Value extra) Name extra
    | FieldFunction Name extra
    | Apply (Value extra) (Value extra) extra
    | Lambda (Pattern extra) (Value extra) extra
    | LetDefinition Name (Definition extra) (Value extra) extra
    | LetRecursion (List ( Name, Definition extra )) (Value extra) extra
    | Destructure (Pattern extra) (Value extra) (Value extra) extra
    | IfThenElse (Value extra) (Value extra) (Value extra) extra
    | PatternMatch (Value extra) (List ( Pattern extra, Value extra )) extra
    | UpdateRecord (Value extra) (List ( Name, Value extra )) extra
    | Unit extra


{-| Type that represents a literal value.
-}
type Literal
    = BoolLiteral Bool
    | CharLiteral Char
    | StringLiteral String
    | IntLiteral Int
    | FloatLiteral Float


{-| Type that represents a pattern.
-}
type Pattern extra
    = WildcardPattern extra
    | AsPattern (Pattern extra) Name extra
    | TuplePattern (List (Pattern extra)) extra
    | RecordPattern (List Name) extra
    | ConstructorPattern FQName (List (Pattern extra)) extra
    | EmptyListPattern extra
    | HeadTailPattern (Pattern extra) (Pattern extra) extra
    | LiteralPattern Literal extra


{-| Type that represents a value or function specification. The specification of what the value or function
is without the actual data or logic behind it.
-}
type alias Specification extra =
    { inputs : List ( Name, Type extra )
    , output : Type extra
    }


{-| Type that represents a value or function definition. A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.
-}
type Definition extra
    = TypedDefinition (Type extra) (List Name) (Value extra)
    | UntypedDefinition (List Name) (Value extra)


getDefinitionBody : Definition extra -> Value extra
getDefinitionBody def =
    case def of
        TypedDefinition _ _ body ->
            body

        UntypedDefinition _ body ->
            body



-- definitionToSpecification : Definition extra -> Maybe (Specification extra)
-- definitionToSpecification def =
--     case def of
--         TypedDefinition valueType argNames _ ->
--             let
--                 extractArgTypes tpe names =
--                     case ( names, tpe ) of
--                         ( [], returnType ) ->
--                             ( [], returnType )
--                         ( nextArgName :: restOfArgNames,  ->
--             in


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Specification a -> Result (List e) (Specification b)
mapSpecification mapType mapValue spec =
    let
        inputsResult =
            spec.inputs
                |> List.map
                    (\( name, tpe ) ->
                        mapType tpe
                            |> Result.map (Tuple.pair name)
                    )
                |> ResultList.toResult

        outputResult =
            mapType spec.output
                |> Result.mapError List.singleton
    in
    Result.map2 Specification
        inputsResult
        outputResult


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Value b) -> Definition a -> Result (List e) (Definition b)
mapDefinition mapType mapValue def =
    case def of
        TypedDefinition tpe args body ->
            mapType tpe
                |> Result.map
                    (\t ->
                        TypedDefinition t args (mapValue body)
                    )
                |> Result.mapError List.singleton

        UntypedDefinition args body ->
            UntypedDefinition args (mapValue body)
                |> Ok


mapValueExtra : (a -> b) -> Value a -> Value b
mapValueExtra f v =
    case v of
        Literal value extra ->
            Literal value (f extra)

        Constructor fullyQualifiedName extra ->
            Constructor fullyQualifiedName (f extra)

        Tuple elements extra ->
            Tuple (elements |> List.map (mapValueExtra f)) (f extra)

        List items extra ->
            List (items |> List.map (mapValueExtra f)) (f extra)

        Record fields extra ->
            Record
                (fields
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( fieldName, mapValueExtra f fieldValue )
                        )
                )
                (f extra)

        Variable name extra ->
            Variable name (f extra)

        Reference fullyQualifiedName extra ->
            Reference fullyQualifiedName (f extra)

        Field subjectValue fieldName extra ->
            Field (mapValueExtra f subjectValue) fieldName (f extra)

        FieldFunction fieldName extra ->
            FieldFunction fieldName (f extra)

        Apply function argument extra ->
            Apply (mapValueExtra f function) (mapValueExtra f argument) (f extra)

        Lambda argumentPattern body extra ->
            Lambda (mapPatternExtra f argumentPattern) (mapValueExtra f body) (f extra)

        LetDefinition valueName valueDefinition inValue extra ->
            LetDefinition valueName (mapDefinitionExtra f valueDefinition) (mapValueExtra f inValue) (f extra)

        LetRecursion valueDefinitions inValue extra ->
            LetRecursion
                (valueDefinitions
                    |> List.map
                        (\( name, def ) ->
                            ( name, mapDefinitionExtra f def )
                        )
                )
                (mapValueExtra f inValue)
                (f extra)

        Destructure pattern valueToDestruct inValue extra ->
            Destructure (mapPatternExtra f pattern) (mapValueExtra f valueToDestruct) (mapValueExtra f inValue) (f extra)

        IfThenElse condition thenBranch elseBranch extra ->
            IfThenElse (mapValueExtra f condition) (mapValueExtra f thenBranch) (mapValueExtra f elseBranch) (f extra)

        PatternMatch branchOutOn cases extra ->
            PatternMatch (mapValueExtra f branchOutOn)
                (cases
                    |> List.map
                        (\( pattern, body ) ->
                            ( mapPatternExtra f pattern, mapValueExtra f body )
                        )
                )
                (f extra)

        UpdateRecord valueToUpdate fieldsToUpdate extra ->
            UpdateRecord (mapValueExtra f valueToUpdate)
                (fieldsToUpdate
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( fieldName, mapValueExtra f fieldValue )
                        )
                )
                (f extra)

        Unit extra ->
            Unit (f extra)


mapPatternExtra : (a -> b) -> Pattern a -> Pattern b
mapPatternExtra f p =
    case p of
        WildcardPattern extra ->
            WildcardPattern (f extra)

        AsPattern p2 name extra ->
            AsPattern (mapPatternExtra f p2) name (f extra)

        TuplePattern elementPatterns extra ->
            TuplePattern (elementPatterns |> List.map (mapPatternExtra f)) (f extra)

        RecordPattern fieldNames extra ->
            RecordPattern fieldNames (f extra)

        ConstructorPattern constructorName argumentPatterns extra ->
            ConstructorPattern constructorName (argumentPatterns |> List.map (mapPatternExtra f)) (f extra)

        EmptyListPattern extra ->
            EmptyListPattern (f extra)

        HeadTailPattern headPattern tailPattern extra ->
            HeadTailPattern (mapPatternExtra f headPattern) (mapPatternExtra f tailPattern) (f extra)

        LiteralPattern value extra ->
            LiteralPattern value (f extra)


mapDefinitionExtra : (a -> b) -> Definition a -> Definition b
mapDefinitionExtra f d =
    case d of
        TypedDefinition tpe args body ->
            TypedDefinition (Type.mapTypeExtra f tpe) args (mapValueExtra f body)

        UntypedDefinition args body ->
            UntypedDefinition args (mapValueExtra f body)


{-| A [literal][lit] represents a fixed value in the IR. We only allow values of basic types: bool, char, string, int, float.

    True -- Literal (BoolLiteral True)

    'a' -- Literal (CharLiteral 'a')

    "foo" -- Literal (StringLiteral "foo")

    13 -- Literal (IntLiteral 13)

    15.4 -- Literal (FloatLiteral 15.4)

[lit]: https://en.wikipedia.org/wiki/Literal_(computer_programming)

-}
literal : Literal -> extra -> Value extra
literal value extra =
    Literal value extra


{-| A reference to a constructor of a custom type.

    Nothing -- Constructor ( ..., [ [ "maybe" ] ], [ "nothing" ] )

    Foo.Bar -- Constructor ( ..., [ [ "foo" ] ], [ "bar" ] )

-}
constructor : FQName -> extra -> Value extra
constructor fullyQualifiedName extra =
    Constructor fullyQualifiedName extra


{-| A [tuple] represents an ordered list of values where each value can be of a different type.

**Note**: Tuples with zero values are considered to be the special value [`Unit`](#unit)

    ( 1, True ) -- Tuple [ Literal (IntLiteral 1), Literal (BoolLiteral True) ]

    ( "foo", True, 3 ) -- Tuple [ Literal (StringLiteral "foo"), Literal (BoolLiteral True), Literal (IntLiteral 3) ]

    () -- Unit

[tuple]: https://en.wikipedia.org/wiki/Tuple

-}
tuple : List (Value extra) -> extra -> Value extra
tuple elements extra =
    Tuple elements extra


{-| A [list] represents an ordered list of values where every value has to be of the same type.

    [ 1, 3, 5 ] -- List [ Literal (IntLiteral 1), Literal (IntLiteral 3), Literal (IntLiteral 5) ]

    [] -- List []

[list]: https://en.wikipedia.org/wiki/List_(abstract_data_type)

-}
list : List (Value extra) -> extra -> Value extra
list items extra =
    List items extra


{-| A [record] represents a list of fields where each field has a name and a value.

    { foo = "bar" } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ) ]

    { foo = "bar", baz = 1 } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ), ( [ "baz" ], Literal (IntLiteral 1) ) ]

    {} -- Record []

[record]: https://en.wikipedia.org/wiki/Record_(computer_science)

-}
record : List ( Name, Value extra ) -> extra -> Value extra
record fields extra =
    Record fields extra


{-| A [variable] represents a reference to a named value in the scope.

    a -- Variable [ "a" ]

    fooBar15 -- Variable [ "foo", "bar", "15" ]

[variable]: https://en.wikipedia.org/wiki/Variable_(computer_science)

-}
variable : Name -> extra -> Value extra
variable name extra =
    Variable name extra


{-| A reference that refers to a function or a value with its fully-qualified name.

    List.map -- Reference ( [ ..., [ [ "list" ] ], [ "map" ] )

-}
reference : FQName -> extra -> Value extra
reference fullyQualifiedName extra =
    Reference fullyQualifiedName extra


{-| Extracts the value of a record's field.

    a.foo -- Field (Variable [ "a" ]) [ "foo" ]

-}
field : Value extra -> Name -> extra -> Value extra
field subjectValue fieldName extra =
    Field subjectValue fieldName extra


{-| Represents a function that extract a field from a record value passed to it.

    .foo -- FieldFunction [ "foo" ]

-}
fieldFunction : Name -> extra -> Value extra
fieldFunction fieldName extra =
    FieldFunction fieldName extra


{-| Represents a function invocation. We use currying to represent function invocations with multiple arguments.

**Note**: Operators are mapped to well-known function names.

    not True -- Apply (Reference ( ..., [ [ "basics" ] ], [ "not" ])) (Literal (BoolLiteral True))

    True || False -- Apply (Apply (Reference ( ..., [ [ "basics" ] ], [ "and" ]))) (Literal (BoolLiteral True)) (Literal (BoolLiteral True))

-}
apply : Value extra -> Value extra -> extra -> Value extra
apply function argument extra =
    Apply function argument extra


{-| Represents a lambda abstraction.

**Note**:

  - We use currying to represent lambda abstractions with multiple arguments.
  - Arguments are not just names, they are patterns.

```
\a -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Variable [ "a" ])

\a b -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Lambda (AsPattern WildcardPattern [ "b" ]) (Variable [ "a" ]))
```

-}
lambda : Pattern extra -> Value extra -> extra -> Value extra
lambda argumentPattern body extra =
    Lambda argumentPattern body extra


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
letDef : Name -> Definition extra -> Value extra -> extra -> Value extra
letDef valueName valueDefinition inValue extra =
    LetDefinition valueName valueDefinition inValue extra


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
letRec : List ( Name, Definition extra ) -> Value extra -> extra -> Value extra
letRec valueDefinitions inValue extra =
    LetRecursion valueDefinitions inValue extra


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
letDestruct : Pattern extra -> Value extra -> Value extra -> extra -> Value extra
letDestruct pattern valueToDestruct inValue extra =
    Destructure pattern valueToDestruct inValue extra


{-| Represents and if/then/else expression.

    if a then
        b
    else
        c
    -- IfThenElse (Variable ["a"])
    --     (Variable ["b"])
    --     (Variable ["c"])

-}
ifThenElse : Value extra -> Value extra -> Value extra -> extra -> Value extra
ifThenElse condition thenBranch elseBranch extra =
    IfThenElse condition thenBranch elseBranch extra


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
patternMatch : Value extra -> List ( Pattern extra, Value extra ) -> extra -> Value extra
patternMatch branchOutOn cases extra =
    PatternMatch branchOutOn cases extra


{-| Update one or many fields of a record value.

    { a | foo = 1 } -- Update (Variable ["a"]) [ ( ["foo"], Literal (IntLiteral 1) ) ]

-}
update : Value extra -> List ( Name, Value extra ) -> extra -> Value extra
update valueToUpdate fieldsToUpdate extra =
    UpdateRecord valueToUpdate fieldsToUpdate extra


{-| Represents the unit value.

    () -- Unit

-}
unit : extra -> Value extra
unit extra =
    Unit extra


{-| Represents a boolean value. Only possible values are: `True`, `False`
-}
boolLiteral : Bool -> Literal
boolLiteral value =
    BoolLiteral value


{-| Represents a character value. Some possible values: `'a'`, `'Z'`, `'3'`
-}
charLiteral : Char -> Literal
charLiteral value =
    CharLiteral value


{-| Represents a string value. Some possible values: `""`, `"foo"`, `"Bar baz: 123"`
-}
stringLiteral : String -> Literal
stringLiteral value =
    StringLiteral value


{-| Represents an integer value. Some possible values: `0`, `-1`, `9832479`
-}
intLiteral : Int -> Literal
intLiteral value =
    IntLiteral value


{-| Represents a floating-point number. Some possible values: `1.25`, `-13.4`
-}
floatLiteral : Float -> Literal
floatLiteral value =
    FloatLiteral value


{-| Matches any value and ignores it (assigns no variable name).

    _ -- WildcardPattern

-}
wildcardPattern : extra -> Pattern extra
wildcardPattern extra =
    WildcardPattern extra


{-| Assigns a variable name to a pattern.

    _ as foo -- AsPattern WildcardPattern ["foo"]

    foo -- AsPattern WildcardPattern ["foo"]

    [] as foo -- AsPattern EmptyListPattern ["foo"]

-}
asPattern : Pattern extra -> Name -> extra -> Pattern extra
asPattern pattern name extra =
    AsPattern pattern name extra


{-| Destructures a tuple using a pattern for every element.

    ( _, foo ) -- TuplePattern [ WildcardPattern, AsPattern WildcardPattern ["foo"] ]

-}
tuplePattern : List (Pattern extra) -> extra -> Pattern extra
tuplePattern elementPatterns extra =
    TuplePattern elementPatterns extra


{-| Pulls out the values of some fields from a record value.

    { foo, bar } -- RecordPattern [ ["foo"], ["bar"] ]

-}
recordPattern : List Name -> extra -> Pattern extra
recordPattern fieldNames extra =
    RecordPattern fieldNames extra


{-| Matches on a custom type's constructor.

**Note**: When the custom type has a single constructor this can be used for destructuring.
When there are multiple constructors it also does filtering so it cannot be used in a
[`LetDestruct`](#letDestruct) but it can be used in a [pattern-match](#patternMatch).

    Just _ -- ConstructorPattern ( ..., [["maybe"]], ["just"]) [ WildcardPattern ]

-}
constructorPattern : FQName -> List (Pattern extra) -> extra -> Pattern extra
constructorPattern constructorName argumentPatterns extra =
    ConstructorPattern constructorName argumentPatterns extra


{-| Matches an empty list. Can be used standalon but frequently used as a terminal pattern
in a [`HeadTailPattern`](#headTailPattern).

    [] -- EmptyListPattern

    [ _ ]
    -- HeadTailPattern
    --     WildcardPattern
    --     EmptyListPattern

-}
emptyListPattern : extra -> Pattern extra
emptyListPattern extra =
    EmptyListPattern extra


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
headTailPattern : Pattern extra -> Pattern extra -> extra -> Pattern extra
headTailPattern headPattern tailPattern extra =
    HeadTailPattern headPattern tailPattern extra


{-| Matches a specific literal value. This pattern can only be used in a [pattern-match](#patternMatch)
since it always filters.

    True -- LiteralPattern (BoolLiteral True)

    'a' -- LiteralPattern (CharLiteral 'a')

    "foo" -- LiteralPattern (StringLiteral "foo")

    13 -- LiteralPattern (IntLiteral 13)

    15.4 -- LiteralPattern (FloatLiteral 15.4)

-}
literalPattern : Literal -> extra -> Pattern extra
literalPattern value extra =
    LiteralPattern value extra


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
typedDefinition : Type extra -> List Name -> Value extra -> Definition extra
typedDefinition valueType argumentNames body =
    TypedDefinition valueType argumentNames body


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
untypedDefinition : List Name -> Value extra -> Definition extra
untypedDefinition argumentNames body =
    UntypedDefinition argumentNames body


encodeValue : (extra -> Encode.Value) -> Value extra -> Encode.Value
encodeValue encodeExtra v =
    let
        typeTag tag =
            ( "@type", Encode.string tag )
    in
    case v of
        Literal value extra ->
            Encode.object
                [ typeTag "literal"
                , ( "value", encodeLiteral value )
                , ( "extra", encodeExtra extra )
                ]

        Constructor fullyQualifiedName extra ->
            Encode.object
                [ typeTag "constructor"
                , ( "fullyQualifiedName", encodeFQName fullyQualifiedName )
                , ( "extra", encodeExtra extra )
                ]

        Tuple elements extra ->
            Encode.object
                [ typeTag "tuple"
                , ( "elements", elements |> Encode.list (encodeValue encodeExtra) )
                , ( "extra", encodeExtra extra )
                ]

        List items extra ->
            Encode.object
                [ typeTag "list"
                , ( "items", items |> Encode.list (encodeValue encodeExtra) )
                , ( "extra", encodeExtra extra )
                ]

        Record fields extra ->
            Encode.object
                [ typeTag "record"
                , ( "fields"
                  , fields
                        |> Encode.list
                            (\( fieldName, fieldValue ) ->
                                Encode.list identity
                                    [ encodeName fieldName
                                    , encodeValue encodeExtra fieldValue
                                    ]
                            )
                  )
                , ( "extra", encodeExtra extra )
                ]

        Variable name extra ->
            Encode.object
                [ typeTag "variable"
                , ( "name", encodeName name )
                , ( "extra", encodeExtra extra )
                ]

        Reference fullyQualifiedName extra ->
            Encode.object
                [ typeTag "reference"
                , ( "fullyQualifiedName", encodeFQName fullyQualifiedName )
                , ( "extra", encodeExtra extra )
                ]

        Field subjectValue fieldName extra ->
            Encode.object
                [ typeTag "field"
                , ( "subjectValue", encodeValue encodeExtra subjectValue )
                , ( "fieldName", encodeName fieldName )
                , ( "extra", encodeExtra extra )
                ]

        FieldFunction fieldName extra ->
            Encode.object
                [ typeTag "fieldFunction"
                , ( "fieldName", encodeName fieldName )
                , ( "extra", encodeExtra extra )
                ]

        Apply function argument extra ->
            Encode.object
                [ typeTag "apply"
                , ( "function", encodeValue encodeExtra function )
                , ( "argument", encodeValue encodeExtra argument )
                , ( "extra", encodeExtra extra )
                ]

        Lambda argumentPattern body extra ->
            Encode.object
                [ typeTag "lambda"
                , ( "argumentPattern", encodePattern encodeExtra argumentPattern )
                , ( "body", encodeValue encodeExtra body )
                , ( "extra", encodeExtra extra )
                ]

        LetDefinition valueName valueDefinition inValue extra ->
            Encode.object
                [ typeTag "letDef"
                , ( "valueName", encodeName valueName )
                , ( "valueDefintion", encodeDefinition encodeExtra valueDefinition )
                , ( "inValue", encodeValue encodeExtra inValue )
                , ( "extra", encodeExtra extra )
                ]

        LetRecursion valueDefinitions inValue extra ->
            Encode.object
                [ typeTag "letRec"
                , ( "valueDefintions"
                  , valueDefinitions
                        |> Encode.list
                            (\( name, def ) ->
                                Encode.list identity
                                    [ encodeName name
                                    , encodeDefinition encodeExtra def
                                    ]
                            )
                  )
                , ( "inValue", encodeValue encodeExtra inValue )
                , ( "extra", encodeExtra extra )
                ]

        Destructure pattern valueToDestruct inValue extra ->
            Encode.object
                [ typeTag "letDestruct"
                , ( "pattern", encodePattern encodeExtra pattern )
                , ( "valueToDestruct", encodeValue encodeExtra valueToDestruct )
                , ( "inValue", encodeValue encodeExtra inValue )
                , ( "extra", encodeExtra extra )
                ]

        IfThenElse condition thenBranch elseBranch extra ->
            Encode.object
                [ typeTag "ifThenElse"
                , ( "condition", encodeValue encodeExtra condition )
                , ( "thenBranch", encodeValue encodeExtra thenBranch )
                , ( "elseBranch", encodeValue encodeExtra elseBranch )
                , ( "extra", encodeExtra extra )
                ]

        PatternMatch branchOutOn cases extra ->
            Encode.object
                [ typeTag "patternMatch"
                , ( "branchOutOn", encodeValue encodeExtra branchOutOn )
                , ( "cases"
                  , cases
                        |> Encode.list
                            (\( pattern, body ) ->
                                Encode.list identity
                                    [ encodePattern encodeExtra pattern
                                    , encodeValue encodeExtra body
                                    ]
                            )
                  )
                , ( "extra", encodeExtra extra )
                ]

        UpdateRecord valueToUpdate fieldsToUpdate extra ->
            Encode.object
                [ typeTag "update"
                , ( "valueToUpdate", encodeValue encodeExtra valueToUpdate )
                , ( "fieldsToUpdate"
                  , fieldsToUpdate
                        |> Encode.list
                            (\( fieldName, fieldValue ) ->
                                Encode.list identity
                                    [ encodeName fieldName
                                    , encodeValue encodeExtra fieldValue
                                    ]
                            )
                  )
                , ( "extra", encodeExtra extra )
                ]

        Unit extra ->
            Encode.object
                [ typeTag "unit"
                , ( "extra", encodeExtra extra )
                ]


decodeValue : Decode.Decoder extra -> Decode.Decoder (Value extra)
decodeValue decodeExtra =
    let
        lazyDecodeValue =
            Decode.lazy <|
                \_ ->
                    decodeValue decodeExtra
    in
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "literal" ->
                        Decode.map2 Literal
                            (Decode.field "value" decodeLiteral)
                            (Decode.field "extra" decodeExtra)

                    "constructor" ->
                        Decode.map2 Constructor
                            (Decode.field "fullyQualifiedName" decodeFQName)
                            (Decode.field "extra" decodeExtra)

                    "tuple" ->
                        Decode.map2 Tuple
                            (Decode.field "elements" <| Decode.list lazyDecodeValue)
                            (Decode.field "extra" decodeExtra)

                    "list" ->
                        Decode.map2 List
                            (Decode.field "items" <| Decode.list lazyDecodeValue)
                            (Decode.field "extra" decodeExtra)

                    "record" ->
                        Decode.map2 Record
                            (Decode.field "fields"
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeValue decodeExtra)
                                    )
                                )
                            )
                            (Decode.field "extra" decodeExtra)

                    "variable" ->
                        Decode.map2 Variable
                            (Decode.field "name" decodeName)
                            (Decode.field "extra" decodeExtra)

                    "reference" ->
                        Decode.map2 Reference
                            (Decode.field "fullyQualifiedName" decodeFQName)
                            (Decode.field "extra" decodeExtra)

                    "field" ->
                        Decode.map3 Field
                            (Decode.field "subjectValue" <| decodeValue decodeExtra)
                            (Decode.field "fieldName" decodeName)
                            (Decode.field "extra" decodeExtra)

                    "fieldFunction" ->
                        Decode.map2 FieldFunction
                            (Decode.field "fieldName" decodeName)
                            (Decode.field "extra" decodeExtra)

                    "apply" ->
                        Decode.map3 Apply
                            (Decode.field "function" <| decodeValue decodeExtra)
                            (Decode.field "argument" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "lambda" ->
                        Decode.map3 Lambda
                            (Decode.field "argumentPattern" <| decodePattern decodeExtra)
                            (Decode.field "body" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "letDef" ->
                        Decode.map4 LetDefinition
                            (Decode.field "valueName" decodeName)
                            (Decode.field "valueDefintion" <| decodeDefinition decodeExtra)
                            (Decode.field "inValue" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "letRec" ->
                        Decode.map3 LetRecursion
                            (Decode.field "valueDefintions"
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeDefinition decodeExtra)
                                    )
                                )
                            )
                            (Decode.field "inValue" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "letDestruct" ->
                        Decode.map4 Destructure
                            (Decode.field "pattern" <| decodePattern decodeExtra)
                            (Decode.field "valueToDestruct" <| decodeValue decodeExtra)
                            (Decode.field "inValue" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "ifThenElse" ->
                        Decode.map4 IfThenElse
                            (Decode.field "condition" <| decodeValue decodeExtra)
                            (Decode.field "thenBranch" <| decodeValue decodeExtra)
                            (Decode.field "elseBranch" <| decodeValue decodeExtra)
                            (Decode.field "extra" decodeExtra)

                    "patternMatch" ->
                        Decode.map3 PatternMatch
                            (Decode.field "branchOutOn" <| decodeValue decodeExtra)
                            (Decode.field "cases" <|
                                Decode.list
                                    (Decode.map2 Tuple.pair
                                        (decodePattern decodeExtra)
                                        (decodeValue decodeExtra)
                                    )
                            )
                            (Decode.field "extra" decodeExtra)

                    "update" ->
                        Decode.map3 UpdateRecord
                            (Decode.field "valueToUpdate" <| decodeValue decodeExtra)
                            (Decode.field "fieldsToUpdate" <|
                                Decode.list <|
                                    Decode.map2 Tuple.pair
                                        decodeName
                                        (decodeValue decodeExtra)
                            )
                            (Decode.field "extra" decodeExtra)

                    "unit" ->
                        Decode.map Unit
                            (Decode.field "extra" decodeExtra)

                    other ->
                        Decode.fail <| "Unknown value type: " ++ other
            )


encodePattern : (extra -> Encode.Value) -> Pattern extra -> Encode.Value
encodePattern encodeExtra pattern =
    let
        typeTag tag =
            ( "@type", Encode.string tag )
    in
    case pattern of
        WildcardPattern extra ->
            Encode.object
                [ typeTag "wildcardPattern"
                , ( "extra", encodeExtra extra )
                ]

        AsPattern p name extra ->
            Encode.object
                [ typeTag "asPattern"
                , ( "pattern", encodePattern encodeExtra p )
                , ( "name", encodeName name )
                , ( "extra", encodeExtra extra )
                ]

        TuplePattern elementPatterns extra ->
            Encode.object
                [ typeTag "tuplePattern"
                , ( "elementPatterns", elementPatterns |> Encode.list (encodePattern encodeExtra) )
                , ( "extra", encodeExtra extra )
                ]

        RecordPattern fieldNames extra ->
            Encode.object
                [ typeTag "recordPattern"
                , ( "fieldNames", fieldNames |> Encode.list encodeName )
                , ( "extra", encodeExtra extra )
                ]

        ConstructorPattern constructorName argumentPatterns extra ->
            Encode.object
                [ typeTag "constructorPattern"
                , ( "constructorName", encodeFQName constructorName )
                , ( "argumentPatterns", argumentPatterns |> Encode.list (encodePattern encodeExtra) )
                , ( "extra", encodeExtra extra )
                ]

        EmptyListPattern extra ->
            Encode.object
                [ typeTag "emptyListPattern"
                , ( "extra", encodeExtra extra )
                ]

        HeadTailPattern headPattern tailPattern extra ->
            Encode.object
                [ typeTag "headTailPattern"
                , ( "headPattern", encodePattern encodeExtra headPattern )
                , ( "tailPattern", encodePattern encodeExtra tailPattern )
                , ( "extra", encodeExtra extra )
                ]

        LiteralPattern value extra ->
            Encode.object
                [ typeTag "literalPattern"
                , ( "value", encodeLiteral value )
                , ( "extra", encodeExtra extra )
                ]


decodePattern : Decode.Decoder extra -> Decode.Decoder (Pattern extra)
decodePattern decodeExtra =
    let
        lazyDecodePattern =
            Decode.lazy <|
                \_ ->
                    decodePattern decodeExtra
    in
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "wildcardPattern" ->
                        Decode.map WildcardPattern
                            (Decode.field "extra" decodeExtra)

                    "asPattern" ->
                        Decode.map3 AsPattern
                            (Decode.field "pattern" lazyDecodePattern)
                            (Decode.field "name" decodeName)
                            (Decode.field "extra" decodeExtra)

                    "tuplePattern" ->
                        Decode.map2 TuplePattern
                            (Decode.field "elementPatterns" <| Decode.list lazyDecodePattern)
                            (Decode.field "extra" decodeExtra)

                    "recordPattern" ->
                        Decode.map2 RecordPattern
                            (Decode.field "fieldNames" <| Decode.list decodeName)
                            (Decode.field "extra" decodeExtra)

                    "constructorPattern" ->
                        Decode.map3 ConstructorPattern
                            (Decode.field "constructorName" decodeFQName)
                            (Decode.field "argumentPatterns" <| Decode.list lazyDecodePattern)
                            (Decode.field "extra" decodeExtra)

                    "emptyListPattern" ->
                        Decode.map EmptyListPattern
                            (Decode.field "extra" decodeExtra)

                    "headTailPattern" ->
                        Decode.map3 HeadTailPattern
                            (Decode.field "headPattern" lazyDecodePattern)
                            (Decode.field "tailPattern" lazyDecodePattern)
                            (Decode.field "extra" decodeExtra)

                    other ->
                        Decode.fail <| "Unknown pattern type: " ++ other
            )


encodeLiteral : Literal -> Encode.Value
encodeLiteral l =
    let
        typeTag tag =
            ( "@type", Encode.string tag )
    in
    case l of
        BoolLiteral v ->
            Encode.object
                [ typeTag "boolLiteral"
                , ( "value", Encode.bool v )
                ]

        CharLiteral v ->
            Encode.object
                [ typeTag "charLiteral"
                , ( "value", Encode.string (String.fromChar v) )
                ]

        StringLiteral v ->
            Encode.object
                [ typeTag "stringLiteral"
                , ( "value", Encode.string v )
                ]

        IntLiteral v ->
            Encode.object
                [ typeTag "intLiteral"
                , ( "value", Encode.int v )
                ]

        FloatLiteral v ->
            Encode.object
                [ typeTag "floatLiteral"
                , ( "value", Encode.float v )
                ]


decodeLiteral : Decode.Decoder Literal
decodeLiteral =
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "boolLiteral" ->
                        Decode.map BoolLiteral
                            (Decode.field "value" Decode.bool)

                    "charLiteral" ->
                        Decode.map CharLiteral
                            (Decode.field "value" Decode.string
                                |> Decode.andThen
                                    (\str ->
                                        case String.uncons str of
                                            Just ( ch, _ ) ->
                                                Decode.succeed ch

                                            Nothing ->
                                                Decode.fail "Single char expected"
                                    )
                            )

                    "stringLiteral" ->
                        Decode.map StringLiteral
                            (Decode.field "value" Decode.string)

                    "intLiteral" ->
                        Decode.map IntLiteral
                            (Decode.field "value" Decode.int)

                    "floatLiteral" ->
                        Decode.map FloatLiteral
                            (Decode.field "value" Decode.float)

                    other ->
                        Decode.fail <| "Unknown literal type: " ++ other
            )


encodeSpecification : (extra -> Encode.Value) -> Specification extra -> Encode.Value
encodeSpecification encodeExtra spec =
    Encode.object
        [ ( "inputs"
          , spec.inputs
                |> Encode.list
                    (\( argName, argType ) ->
                        Encode.object
                            [ ( "argName", encodeName argName )
                            , ( "argType", encodeType encodeExtra argType )
                            ]
                    )
          )
        , ( "output", encodeType encodeExtra spec.output )
        ]


encodeDefinition : (extra -> Encode.Value) -> Definition extra -> Encode.Value
encodeDefinition encodeExtra definition =
    case definition of
        TypedDefinition valueType argumentNames body ->
            Encode.object
                [ ( "@type", Encode.string "typedDefinition" )
                , ( "valueType", encodeType encodeExtra valueType )
                , ( "argumentNames", argumentNames |> Encode.list encodeName )
                , ( "body", encodeValue encodeExtra body )
                ]

        UntypedDefinition argumentNames body ->
            Encode.object
                [ ( "@type", Encode.string "untypedDefinition" )
                , ( "argumentNames", argumentNames |> Encode.list encodeName )
                , ( "body", encodeValue encodeExtra body )
                ]


decodeDefinition : Decode.Decoder extra -> Decode.Decoder (Definition extra)
decodeDefinition decodeExtra =
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "typedDefinition" ->
                        Decode.map3 TypedDefinition
                            (Decode.field "valueType" <| decodeType decodeExtra)
                            (Decode.field "argumentNames" <| Decode.list decodeName)
                            (Decode.field "body" <| Decode.lazy (\_ -> decodeValue decodeExtra))

                    "untypedDefinition" ->
                        Decode.map2 UntypedDefinition
                            (Decode.field "argumentNames" <| Decode.list decodeName)
                            (Decode.field "body" <| Decode.lazy (\_ -> decodeValue decodeExtra))

                    other ->
                        Decode.fail <| "Unknown definition type: " ++ other
            )

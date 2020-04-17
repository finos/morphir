module Morphir.IR.Value exposing
    ( Value(..), literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
    , tuple, variable, ifThenElse, patternMatch, update, unit
    , Literal(..), boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral
    , Pattern(..), wildcardPattern, asPattern, tuplePattern, recordPattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern
    , Specification
    , Definition(..), typedDefinition, untypedDefinition
    , encodeValue, encodeSpecification, encodeDefinition
    , getDefinitionBody, mapDefinition, mapSpecification, mapValueAttributes
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

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName, decodeFQName, encodeFQName)
import Morphir.IR.Name exposing (Name, decodeName, encodeName)
import Morphir.IR.Type as Type exposing (Type, decodeType, encodeType)
import Morphir.ListOfResults as ListOfResults
import String


{-| Type that represents a value.
-}
type Value a
    = Literal a Literal
    | Constructor a FQName
    | Tuple a (List (Value a))
    | List a (List (Value a))
    | Record a (List ( Name, Value a ))
    | Variable a Name
    | Reference a FQName
    | Field a (Value a) Name
    | FieldFunction a Name
    | Apply a (Value a) (Value a)
    | Lambda a (Pattern a) (Value a)
    | LetDefinition a Name (Definition a) (Value a)
    | LetRecursion a (Dict Name (Definition a)) (Value a)
    | Destructure a (Pattern a) (Value a) (Value a)
    | IfThenElse a (Value a) (Value a) (Value a)
    | PatternMatch a (Value a) (List ( Pattern a, Value a ))
    | UpdateRecord a (Value a) (List ( Name, Value a ))
    | Unit a


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
type Pattern a
    = WildcardPattern a
    | AsPattern a (Pattern a) Name
    | TuplePattern a (List (Pattern a))
    | RecordPattern a (List Name)
    | ConstructorPattern a FQName (List (Pattern a))
    | EmptyListPattern a
    | HeadTailPattern a (Pattern a) (Pattern a)
    | LiteralPattern a Literal
    | UnitPattern a


{-| Type that represents a value or function specification. The specification of what the value or function
is without the actual data or logic behind it.
-}
type alias Specification a =
    { inputs : List ( Name, Type a )
    , output : Type a
    }


{-| Type that represents a value or function definition. A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.
-}
type Definition a
    = TypedDefinition (Type a) (List Name) (Value a)
    | UntypedDefinition (List Name) (Value a)


getDefinitionBody : Definition a -> Value a
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


mapSpecification : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Specification a -> Result (List e) (Specification b)
mapSpecification mapType mapValue spec =
    let
        inputsResult =
            spec.inputs
                |> List.map
                    (\( name, tpe ) ->
                        mapType tpe
                            |> Result.map (Tuple.pair name)
                    )
                |> ListOfResults.liftAllErrors

        outputResult =
            mapType spec.output
                |> Result.mapError List.singleton
    in
    Result.map2 Specification
        inputsResult
        outputResult


mapDefinition : (Type a -> Result e (Type b)) -> (Value a -> Result e (Value b)) -> Definition a -> Result (List e) (Definition b)
mapDefinition mapType mapValue def =
    case def of
        TypedDefinition tpe args body ->
            Result.map2 (\t v -> TypedDefinition t args v)
                (mapType tpe)
                (mapValue body)
                |> Result.mapError List.singleton

        UntypedDefinition args body ->
            mapValue body
                |> Result.map (UntypedDefinition args)
                |> Result.mapError List.singleton


mapValueAttributes : (a -> b) -> Value a -> Value b
mapValueAttributes f v =
    case v of
        Literal a value ->
            Literal (f a) value

        Constructor a fullyQualifiedName ->
            Constructor (f a) fullyQualifiedName

        Tuple a elements ->
            Tuple (f a) (elements |> List.map (mapValueAttributes f))

        List a items ->
            List (f a) (items |> List.map (mapValueAttributes f))

        Record a fields ->
            Record (f a)
                (fields
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( fieldName, mapValueAttributes f fieldValue )
                        )
                )

        Variable a name ->
            Variable (f a) name

        Reference a fullyQualifiedName ->
            Reference (f a) fullyQualifiedName

        Field a subjectValue fieldName ->
            Field (f a) (mapValueAttributes f subjectValue) fieldName

        FieldFunction a fieldName ->
            FieldFunction (f a) fieldName

        Apply a function argument ->
            Apply (f a) (mapValueAttributes f function) (mapValueAttributes f argument)

        Lambda a argumentPattern body ->
            Lambda (f a) (mapPatternAttributes f argumentPattern) (mapValueAttributes f body)

        LetDefinition a valueName valueDefinition inValue ->
            LetDefinition (f a) valueName (mapDefinitionAttributes f valueDefinition) (mapValueAttributes f inValue)

        LetRecursion a valueDefinitions inValue ->
            LetRecursion (f a)
                (valueDefinitions
                    |> Dict.map
                        (\_ def ->
                            mapDefinitionAttributes f def
                        )
                )
                (mapValueAttributes f inValue)

        Destructure a pattern valueToDestruct inValue ->
            Destructure (f a) (mapPatternAttributes f pattern) (mapValueAttributes f valueToDestruct) (mapValueAttributes f inValue)

        IfThenElse a condition thenBranch elseBranch ->
            IfThenElse (f a) (mapValueAttributes f condition) (mapValueAttributes f thenBranch) (mapValueAttributes f elseBranch)

        PatternMatch a branchOutOn cases ->
            PatternMatch (f a)
                (mapValueAttributes f branchOutOn)
                (cases
                    |> List.map
                        (\( pattern, body ) ->
                            ( mapPatternAttributes f pattern, mapValueAttributes f body )
                        )
                )

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            UpdateRecord (f a)
                (mapValueAttributes f valueToUpdate)
                (fieldsToUpdate
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            ( fieldName, mapValueAttributes f fieldValue )
                        )
                )

        Unit a ->
            Unit (f a)


mapPatternAttributes : (a -> b) -> Pattern a -> Pattern b
mapPatternAttributes f p =
    case p of
        WildcardPattern a ->
            WildcardPattern (f a)

        AsPattern a p2 name ->
            AsPattern (f a) (mapPatternAttributes f p2) name

        TuplePattern a elementPatterns ->
            TuplePattern (f a) (elementPatterns |> List.map (mapPatternAttributes f))

        RecordPattern a fieldNames ->
            RecordPattern (f a) fieldNames

        ConstructorPattern a constructorName argumentPatterns ->
            ConstructorPattern (f a) constructorName (argumentPatterns |> List.map (mapPatternAttributes f))

        EmptyListPattern a ->
            EmptyListPattern (f a)

        HeadTailPattern a headPattern tailPattern ->
            HeadTailPattern (f a) (mapPatternAttributes f headPattern) (mapPatternAttributes f tailPattern)

        LiteralPattern a value ->
            LiteralPattern (f a) value

        UnitPattern a ->
            UnitPattern (f a)


mapDefinitionAttributes : (a -> b) -> Definition a -> Definition b
mapDefinitionAttributes f d =
    case d of
        TypedDefinition tpe args body ->
            TypedDefinition (Type.mapTypeAttributes f tpe) args (mapValueAttributes f body)

        UntypedDefinition args body ->
            UntypedDefinition args (mapValueAttributes f body)



--rewriteValue : Rewrite e (Value a)
--rewriteValue rewriteBranch rewriteLeaf valueToRewrite =
--    case valueToRewrite of
--        Tuple a elements ->
--            elements
--                |> List.map rewriteBranch
--                |> ResultList.liftLastError
--                |> Result.map (Tuple a)
--
--        List a items ->
--            items
--                |> List.map rewriteBranch
--                |> ResultList.liftLastError
--                |> Result.map (List a)
--
--        Record a fields ->
--            fields
--                |> List.map
--                    (\( fieldName, fieldValue ) ->
--                        rewriteBranch fieldValue
--                            |> Result.map (Tuple.pair fieldName)
--                    )
--                |> ResultList.liftLastError
--                |> Result.map (Record a)
--
--        Field a subjectValue fieldName ->
--            rewriteBranch subjectValue
--                |> Result.map
--                    (\subject ->
--                        Field a subject fieldName
--                    )
--
--        Apply a function argument ->
--            Result.map2 (Apply a)
--                (rewriteBranch function)
--                (rewriteBranch argument)
--
--        Lambda a argumentPattern body ->
--            Lambda (f a) (mapPatternAttributes f argumentPattern) (mapValueAttributes f body)
--
--        LetDefinition a valueName valueDefinition inValue ->
--            LetDefinition (f a) valueName (mapDefinitionAttributes f valueDefinition) (mapValueAttributes f inValue)
--
--        LetRecursion a valueDefinitions inValue ->
--            LetRecursion (f a)
--                (valueDefinitions
--                    |> List.map
--                        (\( name, def ) ->
--                            ( name, mapDefinitionAttributes f def )
--                        )
--                )
--                (mapValueAttributes f inValue)
--
--        Destructure a pattern valueToDestruct inValue ->
--            Destructure (f a) (mapPatternAttributes f pattern) (mapValueAttributes f valueToDestruct) (mapValueAttributes f inValue)
--
--        IfThenElse a condition thenBranch elseBranch ->
--            IfThenElse (f a) (mapValueAttributes f condition) (mapValueAttributes f thenBranch) (mapValueAttributes f elseBranch)
--
--        PatternMatch a branchOutOn cases ->
--            PatternMatch (f a)
--                (mapValueAttributes f branchOutOn)
--                (cases
--                    |> List.map
--                        (\( pattern, body ) ->
--                            ( mapPatternAttributes f pattern, mapValueAttributes f body )
--                        )
--                )
--
--        UpdateRecord a valueToUpdate fieldsToUpdate ->
--            UpdateRecord (f a)
--                (mapValueAttributes f valueToUpdate)
--                (fieldsToUpdate
--                    |> List.map
--                        (\( fieldName, fieldValue ) ->
--                            ( fieldName, mapValueAttributes f fieldValue )
--                        )
--                )
--
--        _ ->
--            rewriteLeaf valueToRewrite


{-| A [literal][lit] represents a fixed value in the IR. We only allow values of basic types: bool, char, string, int, float.

    True -- Literal (BoolLiteral True)

    'a' -- Literal (CharLiteral 'a')

    "foo" -- Literal (StringLiteral "foo")

    13 -- Literal (IntLiteral 13)

    15.4 -- Literal (FloatLiteral 15.4)

[lit]: https://en.wikipedia.org/wiki/Literal_(computer_programming)

-}
literal : a -> Literal -> Value a
literal attributes value =
    Literal attributes value


{-| A reference to a constructor of a custom type.

    Nothing -- Constructor ( ..., [ [ "maybe" ] ], [ "nothing" ] )

    Foo.Bar -- Constructor ( ..., [ [ "foo" ] ], [ "bar" ] )

-}
constructor : a -> FQName -> Value a
constructor attributes fullyQualifiedName =
    Constructor attributes fullyQualifiedName


{-| A [tuple] represents an ordered list of values where each value can be of a different type.

**Note**: Tuples with zero values are considered to be the special value [`Unit`](#unit)

    ( 1, True ) -- Tuple [ Literal (IntLiteral 1), Literal (BoolLiteral True) ]

    ( "foo", True, 3 ) -- Tuple [ Literal (StringLiteral "foo"), Literal (BoolLiteral True), Literal (IntLiteral 3) ]

    () -- Unit

[tuple]: https://en.wikipedia.org/wiki/Tuple

-}
tuple : a -> List (Value a) -> Value a
tuple attributes elements =
    Tuple attributes elements


{-| A [list] represents an ordered list of values where every value has to be of the same type.

    [ 1, 3, 5 ] -- List [ Literal (IntLiteral 1), Literal (IntLiteral 3), Literal (IntLiteral 5) ]

    [] -- List []

[list]: https://en.wikipedia.org/wiki/List_(abstract_data_type)

-}
list : a -> List (Value a) -> Value a
list attributes items =
    List attributes items


{-| A [record] represents a list of fields where each field has a name and a value.

    { foo = "bar" } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ) ]

    { foo = "bar", baz = 1 } -- Record [ ( [ "foo" ], Literal (StringLiteral "bar") ), ( [ "baz" ], Literal (IntLiteral 1) ) ]

    {} -- Record []

[record]: https://en.wikipedia.org/wiki/Record_(computer_science)

-}
record : a -> List ( Name, Value a ) -> Value a
record attributes fields =
    Record attributes fields


{-| A [variable] represents a reference to a named value in the scope.

    a -- Variable [ "a" ]

    fooBar15 -- Variable [ "foo", "bar", "15" ]

[variable]: https://en.wikipedia.org/wiki/Variable_(computer_science)

-}
variable : a -> Name -> Value a
variable attributes name =
    Variable attributes name


{-| A reference that refers to a function or a value with its fully-qualified name.

    List.map -- Reference ( [ ..., [ [ "list" ] ], [ "map" ] )

-}
reference : a -> FQName -> Value a
reference attributes fullyQualifiedName =
    Reference attributes fullyQualifiedName


{-| Extracts the value of a record's field.

    a.foo -- Field (Variable [ "a" ]) [ "foo" ]

-}
field : a -> Value a -> Name -> Value a
field attributes subjectValue fieldName =
    Field attributes subjectValue fieldName


{-| Represents a function that extract a field from a record value passed to it.

    .foo -- FieldFunction [ "foo" ]

-}
fieldFunction : a -> Name -> Value a
fieldFunction attributes fieldName =
    FieldFunction attributes fieldName


{-| Represents a function invocation. We use currying to represent function invocations with multiple arguments.

**Note**: Operators are mapped to well-known function names.

    not True -- Apply (Reference ( ..., [ [ "basics" ] ], [ "not" ])) (Literal (BoolLiteral True))

    True || False -- Apply (Apply (Reference ( ..., [ [ "basics" ] ], [ "and" ]))) (Literal (BoolLiteral True)) (Literal (BoolLiteral True))

-}
apply : a -> Value a -> Value a -> Value a
apply attributes function argument =
    Apply attributes function argument


{-| Represents a lambda abstraction.

**Note**:

  - We use currying to represent lambda abstractions with multiple arguments.
  - Arguments are not just names, they are patterns.

```
\a -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Variable [ "a" ])

\a b -> a -- Lambda (AsPattern WildcardPattern [ "a" ]) (Lambda (AsPattern WildcardPattern [ "b" ]) (Variable [ "a" ]))
```

-}
lambda : a -> Pattern a -> Value a -> Value a
lambda attributes argumentPattern body =
    Lambda attributes argumentPattern body


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
letDef : a -> Name -> Definition a -> Value a -> Value a
letDef attributes valueName valueDefinition inValue =
    LetDefinition attributes valueName valueDefinition inValue


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
letRec : a -> Dict Name (Definition a) -> Value a -> Value a
letRec attributes valueDefinitions inValue =
    LetRecursion attributes valueDefinitions inValue


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
letDestruct : a -> Pattern a -> Value a -> Value a -> Value a
letDestruct attributes pattern valueToDestruct inValue =
    Destructure attributes pattern valueToDestruct inValue


{-| Represents and if/then/else expression.

    if a then
        b
    else
        c
    -- IfThenElse (Variable ["a"])
    --     (Variable ["b"])
    --     (Variable ["c"])

-}
ifThenElse : a -> Value a -> Value a -> Value a -> Value a
ifThenElse attributes condition thenBranch elseBranch =
    IfThenElse attributes condition thenBranch elseBranch


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
patternMatch : a -> Value a -> List ( Pattern a, Value a ) -> Value a
patternMatch attributes branchOutOn cases =
    PatternMatch attributes branchOutOn cases


{-| Update one or many fields of a record value.

    { a | foo = 1 } -- Update (Variable ["a"]) [ ( ["foo"], Literal (IntLiteral 1) ) ]

-}
update : a -> Value a -> List ( Name, Value a ) -> Value a
update attributes valueToUpdate fieldsToUpdate =
    UpdateRecord attributes valueToUpdate fieldsToUpdate


{-| Represents the unit value.

    () -- Unit

-}
unit : a -> Value a
unit attributes =
    Unit attributes


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
wildcardPattern : a -> Pattern a
wildcardPattern attributes =
    WildcardPattern attributes


{-| Assigns a variable name to a pattern.

    _ as foo -- AsPattern WildcardPattern ["foo"]

    foo -- AsPattern WildcardPattern ["foo"]

    [] as foo -- AsPattern EmptyListPattern ["foo"]

-}
asPattern : a -> Pattern a -> Name -> Pattern a
asPattern attributes pattern name =
    AsPattern attributes pattern name


{-| Destructures a tuple using a pattern for every element.

    ( _, foo ) -- TuplePattern [ WildcardPattern, AsPattern WildcardPattern ["foo"] ]

-}
tuplePattern : a -> List (Pattern a) -> Pattern a
tuplePattern attributes elementPatterns =
    TuplePattern attributes elementPatterns


{-| Pulls out the values of some fields from a record value.

    { foo, bar } -- RecordPattern [ ["foo"], ["bar"] ]

-}
recordPattern : a -> List Name -> Pattern a
recordPattern attributes fieldNames =
    RecordPattern attributes fieldNames


{-| Matches on a custom type's constructor.

**Note**: When the custom type has a single constructor this can be used for destructuring.
When there are multiple constructors it also does filtering so it cannot be used in a
[`LetDestruct`](#letDestruct) but it can be used in a [pattern-match](#patternMatch).

    Just _ -- ConstructorPattern ( ..., [["maybe"]], ["just"]) [ WildcardPattern ]

-}
constructorPattern : a -> FQName -> List (Pattern a) -> Pattern a
constructorPattern attributes constructorName argumentPatterns =
    ConstructorPattern attributes constructorName argumentPatterns


{-| Matches an empty list. Can be used standalon but frequently used as a terminal pattern
in a [`HeadTailPattern`](#headTailPattern).

    [] -- EmptyListPattern

    [ _ ]
    -- HeadTailPattern
    --     WildcardPattern
    --     EmptyListPattern

-}
emptyListPattern : a -> Pattern a
emptyListPattern attributes =
    EmptyListPattern attributes


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
headTailPattern : a -> Pattern a -> Pattern a -> Pattern a
headTailPattern attributes headPattern tailPattern =
    HeadTailPattern attributes headPattern tailPattern


{-| Matches a specific literal value. This pattern can only be used in a [pattern-match](#patternMatch)
since it always filters.

    True -- LiteralPattern (BoolLiteral True)

    'a' -- LiteralPattern (CharLiteral 'a')

    "foo" -- LiteralPattern (StringLiteral "foo")

    13 -- LiteralPattern (IntLiteral 13)

    15.4 -- LiteralPattern (FloatLiteral 15.4)

-}
literalPattern : a -> Literal -> Pattern a
literalPattern attributes value =
    LiteralPattern attributes value


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
typedDefinition : Type a -> List Name -> Value a -> Definition a
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
untypedDefinition : List Name -> Value a -> Definition a
untypedDefinition argumentNames body =
    UntypedDefinition argumentNames body


encodeValue : (a -> Encode.Value) -> Value a -> Encode.Value
encodeValue encodeAttributes v =
    case v of
        Literal a value ->
            Encode.list identity
                [ Encode.string "Literal"
                , encodeAttributes a
                , encodeLiteral value
                ]

        Constructor a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Constructor"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Tuple a elements ->
            Encode.list identity
                [ Encode.string "Tuple"
                , encodeAttributes a
                , elements |> Encode.list (encodeValue encodeAttributes)
                ]

        List a items ->
            Encode.list identity
                [ Encode.string "List"
                , encodeAttributes a
                , items |> Encode.list (encodeValue encodeAttributes)
                ]

        Record a fields ->
            Encode.list identity
                [ Encode.string "Record"
                , encodeAttributes a
                , fields
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeAttributes fieldValue
                                ]
                        )
                ]

        Variable a name ->
            Encode.list identity
                [ Encode.string "Variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a fullyQualifiedName ->
            Encode.list identity
                [ Encode.string "Reference"
                , encodeAttributes a
                , encodeFQName fullyQualifiedName
                ]

        Field a subjectValue fieldName ->
            Encode.list identity
                [ Encode.string "Field"
                , encodeAttributes a
                , encodeValue encodeAttributes subjectValue
                , encodeName fieldName
                ]

        FieldFunction a fieldName ->
            Encode.list identity
                [ Encode.string "FieldFunction"
                , encodeAttributes a
                , encodeName fieldName
                ]

        Apply a function argument ->
            Encode.list identity
                [ Encode.string "Apply"
                , encodeAttributes a
                , encodeValue encodeAttributes function
                , encodeValue encodeAttributes argument
                ]

        Lambda a argumentPattern body ->
            Encode.list identity
                [ Encode.string "Lambda"
                , encodeAttributes a
                , encodePattern encodeAttributes argumentPattern
                , encodeValue encodeAttributes body
                ]

        LetDefinition a valueName valueDefinition inValue ->
            Encode.list identity
                [ Encode.string "LetDefinition"
                , encodeAttributes a
                , encodeName valueName
                , encodeDefinition encodeAttributes valueDefinition
                , encodeValue encodeAttributes inValue
                ]

        LetRecursion a valueDefinitions inValue ->
            Encode.list identity
                [ Encode.string "LetRecursion"
                , encodeAttributes a
                , valueDefinitions
                    |> Dict.toList
                    |> Encode.list
                        (\( name, def ) ->
                            Encode.list identity
                                [ encodeName name
                                , encodeDefinition encodeAttributes def
                                ]
                        )
                , encodeValue encodeAttributes inValue
                ]

        Destructure a pattern valueToDestruct inValue ->
            Encode.list identity
                [ Encode.string "Destructure"
                , encodeAttributes a
                , encodePattern encodeAttributes pattern
                , encodeValue encodeAttributes valueToDestruct
                , encodeValue encodeAttributes inValue
                ]

        IfThenElse a condition thenBranch elseBranch ->
            Encode.list identity
                [ Encode.string "IfThenElse"
                , encodeAttributes a
                , encodeValue encodeAttributes condition
                , encodeValue encodeAttributes thenBranch
                , encodeValue encodeAttributes elseBranch
                ]

        PatternMatch a branchOutOn cases ->
            Encode.list identity
                [ Encode.string "PatternMatch"
                , encodeAttributes a
                , encodeValue encodeAttributes branchOutOn
                , cases
                    |> Encode.list
                        (\( pattern, body ) ->
                            Encode.list identity
                                [ encodePattern encodeAttributes pattern
                                , encodeValue encodeAttributes body
                                ]
                        )
                ]

        UpdateRecord a valueToUpdate fieldsToUpdate ->
            Encode.list identity
                [ Encode.string "Update"
                , encodeAttributes a
                , encodeValue encodeAttributes valueToUpdate
                , fieldsToUpdate
                    |> Encode.list
                        (\( fieldName, fieldValue ) ->
                            Encode.list identity
                                [ encodeName fieldName
                                , encodeValue encodeAttributes fieldValue
                                ]
                        )
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "Unit"
                , encodeAttributes a
                ]


decodeValue : Decode.Decoder a -> Decode.Decoder (Value a)
decodeValue decodeAttributes =
    let
        lazyDecodeValue =
            Decode.lazy <|
                \_ ->
                    decodeValue decodeAttributes
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "Literal" ->
                        Decode.map2 Literal
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeLiteral)

                    "Constructor" ->
                        Decode.map2 Constructor
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "Tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "List" ->
                        Decode.map2 List
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodeValue)

                    "Record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeValue decodeAttributes)
                                    )
                                )
                            )

                    "Variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Reference" ->
                        Decode.map2 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)

                    "Field" ->
                        Decode.map3 Field
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 decodeName)

                    "FieldFunction" ->
                        Decode.map2 FieldFunction
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Apply" ->
                        Decode.map3 Apply
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "Lambda" ->
                        Decode.map3 Lambda
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "LetDefinition" ->
                        Decode.map4 LetDefinition
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 <| decodeDefinition decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "LetRecursion" ->
                        Decode.map3 LetRecursion
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2
                                (Decode.list
                                    (Decode.map2 Tuple.pair
                                        (Decode.index 0 decodeName)
                                        (Decode.index 1 <| decodeDefinition decodeAttributes)
                                    )
                                    |> Decode.map Dict.fromList
                                )
                            )
                            (Decode.index 3 <| decodeValue decodeAttributes)

                    "Destructure" ->
                        Decode.map4 Destructure
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodePattern decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "IfThenElse" ->
                        Decode.map4 IfThenElse
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <| decodeValue decodeAttributes)
                            (Decode.index 4 <| decodeValue decodeAttributes)

                    "PatternMatch" ->
                        Decode.map3 PatternMatch
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list
                                    (Decode.map2 Tuple.pair
                                        (decodePattern decodeAttributes)
                                        (decodeValue decodeAttributes)
                                    )
                            )

                    "UpdateRecord" ->
                        Decode.map3 UpdateRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| decodeValue decodeAttributes)
                            (Decode.index 3 <|
                                Decode.list <|
                                    Decode.map2 Tuple.pair
                                        decodeName
                                        (decodeValue decodeAttributes)
                            )

                    "Unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeAttributes)

                    other ->
                        Decode.fail <| "Unknown value type: " ++ other
            )


encodePattern : (a -> Encode.Value) -> Pattern a -> Encode.Value
encodePattern encodeAttributes pattern =
    case pattern of
        WildcardPattern a ->
            Encode.list identity
                [ Encode.string "WildcardPattern"
                , encodeAttributes a
                ]

        AsPattern a p name ->
            Encode.list identity
                [ Encode.string "AsPattern"
                , encodeAttributes a
                , encodePattern encodeAttributes p
                , encodeName name
                ]

        TuplePattern a elementPatterns ->
            Encode.list identity
                [ Encode.string "TuplePattern"
                , encodeAttributes a
                , elementPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        RecordPattern a fieldNames ->
            Encode.list identity
                [ Encode.string "RecordPattern"
                , encodeAttributes a
                , fieldNames |> Encode.list encodeName
                ]

        ConstructorPattern a constructorName argumentPatterns ->
            Encode.list identity
                [ Encode.string "ConstructorPattern"
                , encodeAttributes a
                , encodeFQName constructorName
                , argumentPatterns |> Encode.list (encodePattern encodeAttributes)
                ]

        EmptyListPattern a ->
            Encode.list identity
                [ Encode.string "EmptyListPattern"
                , encodeAttributes a
                ]

        HeadTailPattern a headPattern tailPattern ->
            Encode.list identity
                [ Encode.string "HeadTailPattern"
                , encodeAttributes a
                , encodePattern encodeAttributes headPattern
                , encodePattern encodeAttributes tailPattern
                ]

        LiteralPattern a value ->
            Encode.list identity
                [ Encode.string "LiteralPattern"
                , encodeAttributes a
                , encodeLiteral value
                ]

        UnitPattern a ->
            Encode.list identity
                [ Encode.string "UnitPattern"
                , encodeAttributes a
                ]


decodePattern : Decode.Decoder a -> Decode.Decoder (Pattern a)
decodePattern decodeAttributes =
    let
        lazyDecodePattern =
            Decode.lazy <|
                \_ ->
                    decodePattern decodeAttributes
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "WildcardPattern" ->
                        Decode.map WildcardPattern
                            (Decode.index 1 decodeAttributes)

                    "AsPattern" ->
                        Decode.map3 AsPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 decodeName)

                    "TuplePattern" ->
                        Decode.map2 TuplePattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list lazyDecodePattern)

                    "RecordPattern" ->
                        Decode.map2 RecordPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 <| Decode.list decodeName)

                    "ConstructorPattern" ->
                        Decode.map3 ConstructorPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 <| Decode.list lazyDecodePattern)

                    "EmptyListPattern" ->
                        Decode.map EmptyListPattern
                            (Decode.index 1 decodeAttributes)

                    "HeadTailPattern" ->
                        Decode.map3 HeadTailPattern
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodePattern)
                            (Decode.index 3 lazyDecodePattern)

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


encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "inputs"
          , spec.inputs
                |> Encode.list
                    (\( argName, argType ) ->
                        Encode.object
                            [ ( "argName", encodeName argName )
                            , ( "argType", encodeType encodeAttributes argType )
                            ]
                    )
          )
        , ( "output", encodeType encodeAttributes spec.output )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes definition =
    case definition of
        TypedDefinition valueType argumentNames body ->
            Encode.object
                [ ( "@type", Encode.string "typedDefinition" )
                , ( "valueType", encodeType encodeAttributes valueType )
                , ( "argumentNames", argumentNames |> Encode.list encodeName )
                , ( "body", encodeValue encodeAttributes body )
                ]

        UntypedDefinition argumentNames body ->
            Encode.object
                [ ( "@type", Encode.string "untypedDefinition" )
                , ( "argumentNames", argumentNames |> Encode.list encodeName )
                , ( "body", encodeValue encodeAttributes body )
                ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "typedDefinition" ->
                        Decode.map3 TypedDefinition
                            (Decode.field "valueType" <| decodeType decodeAttributes)
                            (Decode.field "argumentNames" <| Decode.list decodeName)
                            (Decode.field "body" <| Decode.lazy (\_ -> decodeValue decodeAttributes))

                    "untypedDefinition" ->
                        Decode.map2 UntypedDefinition
                            (Decode.field "argumentNames" <| Decode.list decodeName)
                            (Decode.field "body" <| Decode.lazy (\_ -> decodeValue decodeAttributes))

                    other ->
                        Decode.fail <| "Unknown definition type: " ++ other
            )

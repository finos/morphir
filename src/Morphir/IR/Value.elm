module Morphir.IR.Value exposing
    ( Value(..), literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
    , tuple, variable, ifThenElse, patternMatch, update, unit
    , mapValueAttributes
    , Literal(..), boolLiteral, charLiteral, stringLiteral, intLiteral, floatLiteral
    , Pattern(..), wildcardPattern, asPattern, tuplePattern, recordPattern, constructorPattern, emptyListPattern, headTailPattern, literalPattern
    , Specification, mapSpecificationAttributes
    , Definition, typedDefinition, untypedDefinition, mapDefinition, mapDefinitionAttributes
    )

{-| This module contains the building blocks of values in the Morphir IR.


# Value

Value is the top level building block for data and logic. See the constructor functions below for details on each node type.

@docs Value, literal, constructor, apply, field, fieldFunction, lambda, letDef, letDestruct, letRec, list, record, reference
@docs tuple, variable, ifThenElse, patternMatch, update, unit
@docs mapValueAttributes


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

@docs Specification, mapSpecificationAttributes


# Definition

A definition is the actual data or logic as opposed to a specification
which is just the specification of those. Value definitions can be typed or untyped. Exposed values have to be typed.

@docs Definition, typedDefinition, untypedDefinition, mapDefinition, mapDefinitionAttributes

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
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
type alias Definition a =
    { valueType : Maybe (Type a)
    , arguments : List ( Name, a )
    , body : Value a
    }



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


{-| -}
mapDefinition : (Type a -> Result e (Type a)) -> (Value a -> Result e (Value a)) -> Definition a -> Result (List e) (Definition a)
mapDefinition mapType mapValue def =
    Result.map2 (\t v -> Definition t def.arguments v)
        (case def.valueType of
            Just valueType ->
                mapType valueType
                    |> Result.map Just

            Nothing ->
                Ok Nothing
        )
        (mapValue def.body)
        |> Result.mapError List.singleton


{-| -}
mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    Specification
        (spec.inputs
            |> List.map
                (\( name, tpe ) ->
                    ( name, Type.mapTypeAttributes f tpe )
                )
        )
        (Type.mapTypeAttributes f spec.output)


{-| -}
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


{-| -}
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


{-| -}
mapDefinitionAttributes : (a -> b) -> Definition a -> Definition b
mapDefinitionAttributes f d =
    Definition
        (d.valueType |> Maybe.map (Type.mapTypeAttributes f))
        (d.arguments |> List.map (\( name, a ) -> ( name, f a )))
        (mapValueAttributes f d.body)



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
typedDefinition : Type a -> List ( Name, a ) -> Value a -> Definition a
typedDefinition valueType argumentNames body =
    Definition (Just valueType) argumentNames body


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
untypedDefinition : List ( Name, a ) -> Value a -> Definition a
untypedDefinition argumentNames body =
    Definition Nothing argumentNames body

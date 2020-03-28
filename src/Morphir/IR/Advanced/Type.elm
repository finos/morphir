module Morphir.IR.Advanced.Type exposing
    ( Type(..)
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit
    , Field, matchField, mapFieldName, mapFieldType
    , Specification(..), typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification, matchCustomTypeSpecification
    , Definition(..), typeAliasDefinition, customTypeDefinition
    , Constructors
    , fuzzType
    , encodeType, decodeType, encodeSpecification, encodeDefinition
    , Constructor, definitionToSpecification, mapDefinition, mapSpecification, mapTypeExtra, rewriteType
    )

{-| This module contains the building blocks of types in the Morphir IR.


# Type Expression

@docs Type


## Creation

@docs variable, reference, tuple, record, extensibleRecord, function, unit


## Matching

@docs matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit


# Record Field

@docs Field, matchField, mapFieldName, mapFieldType


# Specification

@docs Specification, typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification, matchCustomTypeSpecification


# Definition

@docs Definition, typeAliasDefinition, customTypeDefinition


# Constructors

@docs Constructors


# Property Testing

@docs fuzzType


# Serialization

@docs encodeType, decodeType, encodeSpecification, encodeDefinition

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.FQName exposing (FQName, decodeFQName, encodeFQName, fuzzFQName)
import Morphir.IR.Name exposing (Name, decodeName, encodeName, fuzzName)
import Morphir.Pattern exposing (Pattern)
import Morphir.ResultList as ResultList
import Morphir.Rewrite exposing (Rewrite)


{-| An opaque representation of a type. Check out the docs for each building blocks
for more details:

  - type variable: [creation](#variable), [matching](#matchVariable)
  - type reference: [creation](#reference), [matching](#matchReference)
  - tuple type: [creation](#tuple), [matching](#matchTuple)
  - record type: [creation](#record), [matching](#matchRecord)
  - extensible record type: [creation](#extensibleRecord), [matching](#matchExtensibleRecord)
  - function type: [creation](#function), [matching](#matchFunction)
  - unit type: [creation](#unit), [matching](#matchUnit)

-}
type Type extra
    = Variable Name extra
    | Reference FQName (List (Type extra)) extra
    | Tuple (List (Type extra)) extra
    | Record (List (Field extra)) extra
    | ExtensibleRecord Name (List (Field extra)) extra
    | Function (Type extra) (Type extra) extra
    | Unit extra


{-| An opaque representation of a field. It's made up of a name and a type.
-}
type alias Field extra =
    { name : Name
    , tpe : Type extra
    }


{-| -}
type Specification extra
    = TypeAliasSpecification (List Name) (Type extra)
    | OpaqueTypeSpecification (List Name)
    | CustomTypeSpecification (List Name) (Constructors extra)


{-| This syntax represents a type definition. For example:

  - `type alias Foo a = {bar : Maybe a, qux : Int}`
  - `type MyList a = End | Cons a (MyList a)`

In the definition, the `List Name` refers to type parameters on the LHS
and `Type extra` refers to the RHS

-}
type Definition extra
    = TypeAliasDefinition (List Name) (Type extra)
    | CustomTypeDefinition (List Name) (AccessControlled (Constructors extra))


{-| -}
type alias Constructors extra =
    List (Constructor extra)


{-| -}
type alias Constructor extra =
    ( Name, List ( Name, Type extra ) )


definitionToSpecification : Definition extra -> Specification extra
definitionToSpecification def =
    case def of
        TypeAliasDefinition params exp ->
            TypeAliasSpecification params exp

        CustomTypeDefinition params accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just ctors ->
                    CustomTypeSpecification params ctors

                Nothing ->
                    OpaqueTypeSpecification params


mapSpecification : (Type a -> Result e (Type b)) -> Specification a -> Result (List e) (Specification b)
mapSpecification f spec =
    case spec of
        TypeAliasSpecification params tpe ->
            f tpe
                |> Result.map (TypeAliasSpecification params)
                |> Result.mapError List.singleton

        OpaqueTypeSpecification params ->
            OpaqueTypeSpecification params
                |> Ok

        CustomTypeSpecification params constructors ->
            let
                ctorsResult : Result (List e) (Constructors b)
                ctorsResult =
                    constructors
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            f argType
                                                |> Result.map (Tuple.pair argName)
                                        )
                                    |> ResultList.toResult
                                    |> Result.map (Tuple.pair ctorName)
                            )
                        |> ResultList.toResult
                        |> Result.mapError List.concat
            in
            ctorsResult
                |> Result.map (CustomTypeSpecification params)


mapDefinition : (Type a -> Result e (Type b)) -> Definition a -> Result (List e) (Definition b)
mapDefinition f def =
    case def of
        TypeAliasDefinition params tpe ->
            f tpe
                |> Result.map (TypeAliasDefinition params)
                |> Result.mapError List.singleton

        CustomTypeDefinition params constructors ->
            let
                ctorsResult : Result (List e) (AccessControlled (Constructors b))
                ctorsResult =
                    constructors.value
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            f argType
                                                |> Result.map (Tuple.pair argName)
                                        )
                                    |> ResultList.toResult
                                    |> Result.map (Tuple.pair ctorName)
                            )
                        |> ResultList.toResult
                        |> Result.map (AccessControlled constructors.access)
                        |> Result.mapError List.concat
            in
            ctorsResult
                |> Result.map (CustomTypeDefinition params)


mapTypeExtra : (a -> b) -> Type a -> Type b
mapTypeExtra f tpe =
    case tpe of
        Variable name extra ->
            Variable name (f extra)

        Reference fQName argTypes extra ->
            Reference fQName (argTypes |> List.map (mapTypeExtra f)) (f extra)

        Tuple elemTypes extra ->
            Tuple (elemTypes |> List.map (mapTypeExtra f)) (f extra)

        Record fields extra ->
            Record (fields |> List.map (mapFieldType (mapTypeExtra f))) (f extra)

        ExtensibleRecord name fields extra ->
            ExtensibleRecord name (fields |> List.map (mapFieldType (mapTypeExtra f))) (f extra)

        Function argType returnType extra ->
            Function (argType |> mapTypeExtra f) (returnType |> mapTypeExtra f) (f extra)

        Unit extra ->
            Unit (f extra)


typeExtra : Type a -> a
typeExtra tpe =
    case tpe of
        Variable name extra ->
            extra

        Reference fQName argTypes extra ->
            extra

        Tuple elemTypes extra ->
            extra

        Record fields extra ->
            extra

        ExtensibleRecord name fields extra ->
            extra

        Function argType returnType extra ->
            extra

        Unit extra ->
            extra


{-| Creates a type variable.

    toIR a == variable [ "a" ] ()

    toIR fooBar == variable [ "foo", "bar" ] ()

-}
variable : Name -> extra -> Type extra
variable name extra =
    Variable name extra


{-| -}
matchVariable : Pattern Name a -> Pattern extra b -> Pattern (Type extra) ( a, b )
matchVariable matchName matchExtra typeToMatch =
    case typeToMatch of
        Variable name extra ->
            Maybe.map2 Tuple.pair
                (matchName name)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates a fully-qualified reference to a type.

    toIR (List Int)
        == reference SDK.List.listType [ intType ]

    toIR Foo.Bar
        == reference
            ( [ [ "my" ], [ "lib" ] ], [ [ "foo" ] ], [ "bar" ] )
            []

-}
reference : FQName -> List (Type extra) -> extra -> Type extra
reference typeName typeParameters extra =
    Reference typeName typeParameters extra


{-| -}
matchReference : Pattern FQName a -> Pattern (List (Type extra)) b -> Pattern extra c -> Pattern (Type extra) ( a, b, c )
matchReference matchTypeName matchTypeParameters matchExtra typeToMatch =
    case typeToMatch of
        Reference typeName typeParameters extra ->
            Maybe.map3 (\a b c -> ( a, b, c ))
                (matchTypeName typeName)
                (matchTypeParameters typeParameters)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates a tuple type.

    toIR ( Int, Bool )
        == tuple [ basic intType, basic boolType ]

-}
tuple : List (Type extra) -> extra -> Type extra
tuple elementTypes extra =
    Tuple elementTypes extra


{-| Matches a tuple type and extracts element types.

    tpe =
        tuple [ SDK.Basics.intType, SDK.Basics.boolType ]

    pattern =
        matchTuple (list [ matchBasic any, matchBasic any ])

    pattern tpe ==
        [ SDK.Basics.intType, SDK.Basics.boolType ]

-}
matchTuple : Pattern (List (Type extra)) a -> Pattern extra b -> Pattern (Type extra) ( a, b )
matchTuple matchElementTypes matchExtra typeToMatch =
    case typeToMatch of
        Tuple elementTypes extra ->
            Maybe.map2 Tuple.pair
                (matchElementTypes elementTypes)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates a record type.

    toIR {} == record []

    toIR { foo = Int }
        == record
            [ field [ "foo" ] SDK.Basics.intType
            ]

    toIR { foo = Int, bar = Bool }
        == record
            [ field [ "foo" ] SDK.Basics.intType
            , field [ "bar" ] SDK.Basics.boolType
            ]

-}
record : List (Field extra) -> extra -> Type extra
record fieldTypes extra =
    Record fieldTypes extra


{-| Match a record type.

    matchRecordFooBar =
        matchRecord
                (matchList
                    [ matchField
                        (matchValue ["foo"])
                        matchAny
                    , matchField
                        (matchValue ["bar"])
                        matchAny
                    ]
                )

    matchRecordFooBar <|
        record
            [ field ["foo"] SDK.Basics.intType
            , field ["bar"] SDK.Basics.boolType
            ]
    --> Just ( SDK.Basics.intType, SDK.Basics.boolType )

-}
matchRecord : Pattern (List (Field extra)) a -> Pattern extra b -> Pattern (Type extra) ( a, b )
matchRecord matchFieldTypes matchExtra typeToMatch =
    case typeToMatch of
        Record fieldTypes extra ->
            Maybe.map2 Tuple.pair
                (matchFieldTypes fieldTypes)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates an extensible record type.

    toIR { e | foo = Int }
        == extensibleRecord (variable [ "e" ])
            [ field [ "foo" ] intType
            ]

    toIR { f | foo = Int, bar = Bool }
        == extensibleRecord (variable [ "f" ])
            [ field [ "foo" ] intType
            , field [ "bar" ] boolType
            ]

-}
extensibleRecord : Name -> List (Field extra) -> extra -> Type extra
extensibleRecord variableName fieldTypes extra =
    ExtensibleRecord variableName fieldTypes extra


{-| -}
matchExtensibleRecord : Pattern Name a -> Pattern (List (Field extra)) b -> Pattern extra c -> Pattern (Type extra) ( a, b, c )
matchExtensibleRecord matchVariableName matchFieldTypes matchExtra typeToMatch =
    case typeToMatch of
        ExtensibleRecord variableName fieldTypes extra ->
            Maybe.map3 (\a b c -> ( a, b, c ))
                (matchVariableName variableName)
                (matchFieldTypes fieldTypes)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates a function type. Use currying to create functions with more than one argument.

    toIR (Int -> Bool) ==
        function
            SDK.Basics.intType
            SDK.Basics.boolType

    toIR (Int -> Bool -> Char) ==
        function
            intType
            (function
                SDK.Basics.boolType
                SDK.Basics.charType
            )

-}
function : Type extra -> Type extra -> extra -> Type extra
function argumentType returnType extra =
    Function argumentType returnType extra


{-| Matches a function type.

    tpe =
        function SDK.Basics.intType SDK.Basics.boolType

    pattern =
        matchFunction matchAny matchAny

    pattern tpe ==
        ( SDK.Basics.intType, SDK.Basics.boolType )

-}
matchFunction : Pattern (Type extra) a -> Pattern (Type extra) b -> Pattern extra c -> Pattern (Type extra) ( a, b, c )
matchFunction matchArgType matchReturnType matchExtra typeToMatch =
    case typeToMatch of
        Function argType returnType extra ->
            Maybe.map3 (\a b c -> ( a, b, c ))
                (matchArgType argType)
                (matchReturnType returnType)
                (matchExtra extra)

        _ ->
            Nothing


{-| Creates a unit type.

    toIR () == unit

-}
unit : extra -> Type extra
unit extra =
    Unit extra


{-| -}
matchUnit : Pattern extra a -> Pattern (Type extra) a
matchUnit matchExtra typeToMatch =
    case typeToMatch of
        Unit extra ->
            matchExtra extra

        _ ->
            Nothing


{-| -}
typeAliasDefinition : List Name -> Type extra -> Definition extra
typeAliasDefinition typeParams typeExp =
    TypeAliasDefinition typeParams typeExp


{-| -}
customTypeDefinition : List Name -> AccessControlled (Constructors extra) -> Definition extra
customTypeDefinition typeParams ctors =
    CustomTypeDefinition typeParams ctors


{-| -}
typeAliasSpecification : List Name -> Type extra -> Specification extra
typeAliasSpecification typeParams typeExp =
    TypeAliasSpecification typeParams typeExp


{-| -}
opaqueTypeSpecification : List Name -> Specification extra
opaqueTypeSpecification typeParams =
    OpaqueTypeSpecification typeParams


{-| -}
customTypeSpecification : List Name -> Constructors extra -> Specification extra
customTypeSpecification typeParams ctors =
    CustomTypeSpecification typeParams ctors


{-| -}
matchCustomTypeSpecification : Pattern (List Name) a -> Pattern (Constructors extra) b -> Pattern (Specification extra) ( a, b )
matchCustomTypeSpecification matchTypeParams matchCtors specToMatch =
    case specToMatch of
        CustomTypeSpecification typeParams ctors ->
            Maybe.map2 Tuple.pair
                (matchTypeParams typeParams)
                (matchCtors ctors)

        _ ->
            Nothing


rewriteType : Rewrite e (Type extra)
rewriteType rewriteBranch rewriteLeaf typeToRewrite =
    case typeToRewrite of
        Reference fQName argTypes extra ->
            argTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map
                    (\args ->
                        Reference fQName args extra
                    )

        Tuple elemTypes extra ->
            elemTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map
                    (\elems ->
                        Tuple elems extra
                    )

        Record fieldTypes extra ->
            fieldTypes
                |> List.foldr
                    (\field resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch field.tpe
                                |> Result.map (Field field.name)
                            )
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map
                    (\fields ->
                        Record fields extra
                    )

        ExtensibleRecord varName fieldTypes extra ->
            fieldTypes
                |> List.foldr
                    (\field resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch field.tpe
                                |> Result.map (Field field.name)
                            )
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map
                    (\fields ->
                        ExtensibleRecord varName fields extra
                    )

        Function argType returnType extra ->
            Result.map2 (\arg return -> Function arg return extra)
                (rewriteBranch argType)
                (rewriteBranch returnType)

        _ ->
            rewriteLeaf typeToRewrite


{-| Matches a field.

    let
        field =
            field [ "foo" ] SDK.Basics.intType

        pattern =
            matchField matchAny matchAny
    in
    pattern field
        == Just ( [ "foo" ], SDK.Basics.intType )

-}
matchField : Pattern Name a -> Pattern (Type extra) b -> Pattern (Field extra) ( a, b )
matchField matchFieldName matchFieldType field =
    Maybe.map2 Tuple.pair
        (matchFieldName field.name)
        (matchFieldType field.tpe)


{-| Map the name of the field to get a new field.
-}
mapFieldName : (Name -> Name) -> Field extra -> Field extra
mapFieldName f field =
    Field (f field.name) field.tpe


{-| Map the type of the field to get a new field.
-}
mapFieldType : (Type a -> Type b) -> Field a -> Field b
mapFieldType f field =
    Field field.name (f field.tpe)


{-| Generate random types.
-}
fuzzType : Int -> Fuzzer extra -> Fuzzer (Type extra)
fuzzType maxDepth fuzzExtra =
    let
        fuzzField depth =
            Fuzz.map2 Field
                fuzzName
                (fuzzType depth fuzzExtra)

        fuzzVariable =
            Fuzz.map2 Variable
                fuzzName
                fuzzExtra

        fuzzReference depth =
            Fuzz.map3 Reference
                fuzzFQName
                (Fuzz.list (fuzzType depth fuzzExtra) |> Fuzz.map (List.take depth))
                fuzzExtra

        fuzzTuple depth =
            Fuzz.map2 Tuple
                (Fuzz.list (fuzzType depth fuzzExtra) |> Fuzz.map (List.take depth))
                fuzzExtra

        fuzzRecord depth =
            Fuzz.map2 Record
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))
                fuzzExtra

        fuzzExtensibleRecord depth =
            Fuzz.map3 ExtensibleRecord
                fuzzName
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))
                fuzzExtra

        fuzzFunction depth =
            Fuzz.map3 Function
                (fuzzType depth fuzzExtra)
                (fuzzType depth fuzzExtra)
                fuzzExtra

        fuzzUnit =
            Fuzz.map Unit
                fuzzExtra

        fuzzLeaf =
            Fuzz.oneOf
                [ fuzzVariable
                , fuzzUnit
                ]

        fuzzBranch depth =
            Fuzz.oneOf
                [ fuzzFunction depth
                , fuzzReference depth
                , fuzzTuple depth
                , fuzzRecord depth
                , fuzzExtensibleRecord depth
                ]
    in
    if maxDepth <= 0 then
        fuzzLeaf

    else
        Fuzz.oneOf
            [ fuzzLeaf
            , fuzzBranch (maxDepth - 1)
            ]


{-| Encode a type into JSON.
-}
encodeType : (extra -> Encode.Value) -> Type extra -> Encode.Value
encodeType encodeExtra tpe =
    let
        typeTag tag =
            ( "@type", Encode.string tag )
    in
    case tpe of
        Variable name extra ->
            Encode.object
                [ typeTag "variable"
                , ( "name", encodeName name )
                , ( "extra", encodeExtra extra )
                ]

        Reference typeName typeParameters extra ->
            Encode.object
                [ typeTag "reference"
                , ( "typeName", encodeFQName typeName )
                , ( "typeParameters", Encode.list (encodeType encodeExtra) typeParameters )
                , ( "extra", encodeExtra extra )
                ]

        Tuple elementTypes extra ->
            Encode.object
                [ typeTag "tuple"
                , ( "elementTypes", Encode.list (encodeType encodeExtra) elementTypes )
                , ( "extra", encodeExtra extra )
                ]

        Record fieldTypes extra ->
            Encode.object
                [ typeTag "record"
                , ( "fieldTypes", Encode.list (encodeField encodeExtra) fieldTypes )
                , ( "extra", encodeExtra extra )
                ]

        ExtensibleRecord variableName fieldTypes extra ->
            Encode.object
                [ typeTag "extensibleRecord"
                , ( "variableName", encodeName variableName )
                , ( "fieldTypes", Encode.list (encodeField encodeExtra) fieldTypes )
                , ( "extra", encodeExtra extra )
                ]

        Function argumentType returnType extra ->
            Encode.object
                [ typeTag "function"
                , ( "argumentType", encodeType encodeExtra argumentType )
                , ( "returnType", encodeType encodeExtra returnType )
                , ( "extra", encodeExtra extra )
                ]

        Unit extra ->
            Encode.object
                [ typeTag "unit"
                , ( "extra", encodeExtra extra )
                ]


{-| Decode a type from JSON.
-}
decodeType : Decode.Decoder extra -> Decode.Decoder (Type extra)
decodeType decodeExtra =
    let
        lazyDecodeType =
            Decode.lazy
                (\_ ->
                    decodeType decodeExtra
                )

        lazyDecodeField =
            Decode.lazy
                (\_ ->
                    decodeField decodeExtra
                )
    in
    Decode.field "@type" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "variable" ->
                        Decode.map2 Variable
                            (Decode.field "name" decodeName)
                            (Decode.field "extra" decodeExtra)

                    "reference" ->
                        Decode.map3 Reference
                            (Decode.field "typeName" decodeFQName)
                            (Decode.field "typeParameters" (Decode.list (Decode.lazy (\_ -> decodeType decodeExtra))))
                            (Decode.field "extra" decodeExtra)

                    "tuple" ->
                        Decode.map2 Tuple
                            (Decode.field "elementTypes" (Decode.list lazyDecodeType))
                            (Decode.field "extra" decodeExtra)

                    "record" ->
                        Decode.map2 Record
                            (Decode.field "fieldTypes" (Decode.list lazyDecodeField))
                            (Decode.field "extra" decodeExtra)

                    "extensibleRecord" ->
                        Decode.map3 ExtensibleRecord
                            (Decode.field "variableName" decodeName)
                            (Decode.field "fieldTypes" (Decode.list lazyDecodeField))
                            (Decode.field "extra" decodeExtra)

                    "function" ->
                        Decode.map3 Function
                            (Decode.field "argumentType" lazyDecodeType)
                            (Decode.field "returnType" lazyDecodeType)
                            (Decode.field "extra" decodeExtra)

                    "unit" ->
                        Decode.map Unit
                            (Decode.field "extra" decodeExtra)

                    _ ->
                        Decode.fail ("Unknown kind: " ++ kind)
            )


encodeField : (extra -> Encode.Value) -> Field extra -> Encode.Value
encodeField encodeExtra field =
    Encode.list identity
        [ encodeName field.name
        , encodeType encodeExtra field.tpe
        ]


decodeField : Decode.Decoder extra -> Decode.Decoder (Field extra)
decodeField decodeExtra =
    Decode.map2 Field
        (Decode.index 0 decodeName)
        (Decode.index 1 (decodeType decodeExtra))


{-| -}
encodeSpecification : (extra -> Encode.Value) -> Specification extra -> Encode.Value
encodeSpecification encodeExtra spec =
    case spec of
        TypeAliasSpecification params exp ->
            Encode.object
                [ ( "$type", Encode.string "typeAlias" )
                , ( "params", Encode.list encodeName params )
                , ( "exp", encodeType encodeExtra exp )
                ]

        OpaqueTypeSpecification params ->
            Encode.object
                [ ( "$type", Encode.string "opaqueType" )
                , ( "params", Encode.list encodeName params )
                ]

        CustomTypeSpecification params ctors ->
            Encode.object
                [ ( "$type", Encode.string "customType" )
                , ( "params", Encode.list encodeName params )
                , ( "ctors", encodeConstructors encodeExtra ctors )
                ]


{-| -}
encodeDefinition : (extra -> Encode.Value) -> Definition extra -> Encode.Value
encodeDefinition encodeExtra def =
    case def of
        TypeAliasDefinition params exp ->
            Encode.object
                [ ( "$type", Encode.string "typeAlias" )
                , ( "params", Encode.list encodeName params )
                , ( "exp", encodeType encodeExtra exp )
                ]

        CustomTypeDefinition params ctors ->
            Encode.object
                [ ( "$type", Encode.string "customType" )
                , ( "params", Encode.list encodeName params )
                , ( "ctors", encodeAccessControlled (encodeConstructors encodeExtra) ctors )
                ]


encodeConstructors : (extra -> Encode.Value) -> Constructors extra -> Encode.Value
encodeConstructors encodeExtra ctors =
    ctors
        |> Encode.list
            (\( ctorName, ctorArgs ) ->
                Encode.object
                    [ ( "name", encodeName ctorName )
                    , ( "args"
                      , ctorArgs
                            |> Encode.list
                                (\( argName, argType ) ->
                                    Encode.list identity
                                        [ encodeName argName
                                        , encodeType encodeExtra argType
                                        ]
                                )
                      )
                    ]
            )

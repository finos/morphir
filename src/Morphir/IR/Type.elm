module Morphir.IR.Type exposing
    ( Type(..)
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , Field, matchField, mapFieldName, mapFieldType
    , Specification(..), typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification
    , Definition(..), typeAliasDefinition, customTypeDefinition
    , Constructors
    , fuzzType
    , encodeType, decodeType, encodeSpecification, encodeDefinition
    , Constructor, definitionToSpecification, eraseAttributes, mapDefinition, mapSpecification, mapTypeExtra, rewriteType
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
type Type a
    = Variable a Name
    | Reference a FQName (List (Type a))
    | Tuple a (List (Type a))
    | Record a (List (Field a))
    | ExtensibleRecord a Name (List (Field a))
    | Function a (Type a) (Type a)
    | Unit a


{-| An opaque representation of a field. It's made up of a name and a type.
-}
type alias Field a =
    { name : Name
    , tpe : Type a
    }


{-| -}
type Specification a
    = TypeAliasSpecification (List Name) (Type a)
    | OpaqueTypeSpecification (List Name)
    | CustomTypeSpecification (List Name) (Constructors a)


{-| This syntax represents a type definition. For example:

  - `type alias Foo a = {bar : Maybe a, qux : Int}`
  - `type MyList a = End | Cons a (MyList a)`

In the definition, the `List Name` refers to type parameters on the LHS
and `Type extra` refers to the RHS

-}
type Definition a
    = TypeAliasDefinition (List Name) (Type a)
    | CustomTypeDefinition (List Name) (AccessControlled (Constructors a))


{-| -}
type alias Constructors a =
    List (Constructor a)


{-| -}
type alias Constructor a =
    ( Name, List ( Name, Type a ) )


definitionToSpecification : Definition a -> Specification a
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
        Variable a name ->
            Variable (f a) name

        Reference a fQName argTypes ->
            Reference (f a) fQName (argTypes |> List.map (mapTypeExtra f))

        Tuple a elemTypes ->
            Tuple (f a) (elemTypes |> List.map (mapTypeExtra f))

        Record a fields ->
            Record (f a) (fields |> List.map (mapFieldType (mapTypeExtra f)))

        ExtensibleRecord a name fields ->
            ExtensibleRecord (f a) name (fields |> List.map (mapFieldType (mapTypeExtra f)))

        Function a argType returnType ->
            Function (f a) (argType |> mapTypeExtra f) (returnType |> mapTypeExtra f)

        Unit a ->
            Unit (f a)


typeAttributes : Type a -> a
typeAttributes tpe =
    case tpe of
        Variable a name ->
            a

        Reference a fQName argTypes ->
            a

        Tuple a elemTypes ->
            a

        Record a fields ->
            a

        ExtensibleRecord a name fields ->
            a

        Function a argType returnType ->
            a

        Unit a ->
            a


eraseAttributes : Definition a -> Definition ()
eraseAttributes typeDef =
    case typeDef of
        TypeAliasDefinition typeVars tpe ->
            TypeAliasDefinition typeVars (mapTypeExtra (\_ -> ()) tpe)

        CustomTypeDefinition typeVars acsCtrlConstructors ->
            let
                eraseExtraCtor : Constructor extra -> Constructor ()
                eraseExtraCtor ( name, types ) =
                    let
                        extraErasedTypes : List ( Name, Type () )
                        extraErasedTypes =
                            types
                                |> List.map (\( n, t ) -> ( n, mapTypeExtra (\_ -> ()) t ))
                    in
                    ( name, extraErasedTypes )

                emptyExtraCtors : AccessControlled (Constructors extra) -> AccessControlled (Constructors ())
                emptyExtraCtors acsCtrlCtors =
                    AccessControlled.map
                        (\ctors -> ctors |> List.map eraseExtraCtor)
                        acsCtrlCtors
            in
            CustomTypeDefinition typeVars (emptyExtraCtors acsCtrlConstructors)


{-| Creates a type variable.

    toIR a == variable [ "a" ] ()

    toIR fooBar == variable [ "foo", "bar" ] ()

-}
variable : a -> Name -> Type a
variable attributes name =
    Variable attributes name


{-| Creates a fully-qualified reference to a type.

    toIR (List Int)
        == reference SDK.List.listType [ intType ]

    toIR Foo.Bar
        == reference
            ( [ [ "my" ], [ "lib" ] ], [ [ "foo" ] ], [ "bar" ] )
            []

-}
reference : a -> FQName -> List (Type a) -> Type a
reference attributes typeName typeParameters =
    Reference attributes typeName typeParameters


{-| Creates a tuple type.

    toIR ( Int, Bool )
        == tuple [ basic intType, basic boolType ]

-}
tuple : a -> List (Type a) -> Type a
tuple attributes elementTypes =
    Tuple attributes elementTypes


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
record : a -> List (Field a) -> Type a
record attributes fieldTypes =
    Record attributes fieldTypes


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
extensibleRecord : a -> Name -> List (Field a) -> Type a
extensibleRecord attributes variableName fieldTypes =
    ExtensibleRecord attributes variableName fieldTypes


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
function : a -> Type a -> Type a -> Type a
function attributes argumentType returnType =
    Function attributes argumentType returnType


{-| Creates a unit type.

    toIR () == unit

-}
unit : a -> Type a
unit attributes =
    Unit attributes


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


rewriteType : Rewrite e (Type a)
rewriteType rewriteBranch rewriteLeaf typeToRewrite =
    case typeToRewrite of
        Reference a fQName argTypes ->
            argTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (Reference a fQName)

        Tuple a elemTypes ->
            elemTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (Tuple a)

        Record a fieldTypes ->
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
                |> Result.map (Record a)

        ExtensibleRecord a varName fieldTypes ->
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
                |> Result.map (ExtensibleRecord a varName)

        Function a argType returnType ->
            Result.map2 (Function a)
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
fuzzType : Int -> Fuzzer a -> Fuzzer (Type a)
fuzzType maxDepth fuzzAttributes =
    let
        fuzzField depth =
            Fuzz.map2 Field
                fuzzName
                (fuzzType depth fuzzAttributes)

        fuzzVariable =
            Fuzz.map2 Variable
                fuzzAttributes
                fuzzName

        fuzzReference depth =
            Fuzz.map3 Reference
                fuzzAttributes
                fuzzFQName
                (Fuzz.list (fuzzType depth fuzzAttributes) |> Fuzz.map (List.take depth))

        fuzzTuple depth =
            Fuzz.map2 Tuple
                fuzzAttributes
                (Fuzz.list (fuzzType depth fuzzAttributes) |> Fuzz.map (List.take depth))

        fuzzRecord depth =
            Fuzz.map2 Record
                fuzzAttributes
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))

        fuzzExtensibleRecord depth =
            Fuzz.map3 ExtensibleRecord
                fuzzAttributes
                fuzzName
                (Fuzz.list (fuzzField (depth - 1)) |> Fuzz.map (List.take depth))

        fuzzFunction depth =
            Fuzz.map3 Function
                fuzzAttributes
                (fuzzType depth fuzzAttributes)
                (fuzzType depth fuzzAttributes)

        fuzzUnit =
            Fuzz.map Unit
                fuzzAttributes

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
encodeType : (a -> Encode.Value) -> Type a -> Encode.Value
encodeType encodeAttributes tpe =
    case tpe of
        Variable a name ->
            Encode.list identity
                [ Encode.string "Variable"
                , encodeAttributes a
                , encodeName name
                ]

        Reference a typeName typeParameters ->
            Encode.list identity
                [ Encode.string "Reference"
                , encodeAttributes a
                , encodeFQName typeName
                , Encode.list (encodeType encodeAttributes) typeParameters
                ]

        Tuple a elementTypes ->
            Encode.list identity
                [ Encode.string "Tuple"
                , encodeAttributes a
                , Encode.list (encodeType encodeAttributes) elementTypes
                ]

        Record a fieldTypes ->
            Encode.list identity
                [ Encode.string "Record"
                , encodeAttributes a
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        ExtensibleRecord a variableName fieldTypes ->
            Encode.list identity
                [ Encode.string "ExtensibleRecord"
                , encodeAttributes a
                , encodeName variableName
                , Encode.list (encodeField encodeAttributes) fieldTypes
                ]

        Function a argumentType returnType ->
            Encode.list identity
                [ Encode.string "Function"
                , encodeAttributes a
                , encodeType encodeAttributes argumentType
                , encodeType encodeAttributes returnType
                ]

        Unit a ->
            Encode.list identity
                [ Encode.string "Unit"
                , encodeAttributes a
                ]


{-| Decode a type from JSON.
-}
decodeType : Decode.Decoder a -> Decode.Decoder (Type a)
decodeType decodeAttributes =
    let
        lazyDecodeType =
            Decode.lazy
                (\_ ->
                    decodeType decodeAttributes
                )

        lazyDecodeField =
            Decode.lazy
                (\_ ->
                    decodeField decodeAttributes
                )
    in
    Decode.index 0 Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "Variable" ->
                        Decode.map2 Variable
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)

                    "Reference" ->
                        Decode.map3 Reference
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeFQName)
                            (Decode.index 3 (Decode.list (Decode.lazy (\_ -> decodeType decodeAttributes))))

                    "Tuple" ->
                        Decode.map2 Tuple
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeType))

                    "Record" ->
                        Decode.map2 Record
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 (Decode.list lazyDecodeField))

                    "ExtensibleRecord" ->
                        Decode.map3 ExtensibleRecord
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 decodeName)
                            (Decode.index 3 (Decode.list lazyDecodeField))

                    "Function" ->
                        Decode.map3 Function
                            (Decode.index 1 decodeAttributes)
                            (Decode.index 2 lazyDecodeType)
                            (Decode.index 3 lazyDecodeType)

                    "Unit" ->
                        Decode.map Unit
                            (Decode.index 1 decodeAttributes)

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
            Encode.list identity
                [ Encode.string "TypeAliasSpecification"
                , Encode.list encodeName params
                , encodeType encodeExtra exp
                ]

        OpaqueTypeSpecification params ->
            Encode.list identity
                [ Encode.string "OpaqueTypeSpecification"
                , Encode.list encodeName params
                ]

        CustomTypeSpecification params ctors ->
            Encode.list identity
                [ Encode.string "CustomTypeSpecification"
                , Encode.list encodeName params
                , encodeConstructors encodeExtra ctors
                ]


{-| -}
encodeDefinition : (extra -> Encode.Value) -> Definition extra -> Encode.Value
encodeDefinition encodeExtra def =
    case def of
        TypeAliasDefinition params exp ->
            Encode.list identity
                [ Encode.string "TypeAliasDefinition"
                , Encode.list encodeName params
                , encodeType encodeExtra exp
                ]

        CustomTypeDefinition params ctors ->
            Encode.list identity
                [ Encode.string "CustomTypeDefinition"
                , Encode.list encodeName params
                , encodeAccessControlled (encodeConstructors encodeExtra) ctors
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

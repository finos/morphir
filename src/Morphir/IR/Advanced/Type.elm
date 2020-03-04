module Morphir.IR.Advanced.Type exposing
    ( Type
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit
    , Field, field, matchField, mapFieldName, mapFieldType
    , Declaration, typeAliasDeclaration, opaqueTypeDeclaration, customTypeDeclaration, matchCustomTypeDeclaration
    , Definition, typeAliasDefinition, customTypeDefinition
    , Constructors
    , fuzzType
    , encodeType, decodeType, encodeDeclaration, encodeDefinition
    , definitionToDeclaration
    )

{-| This module contains the building blocks of types in the Morphir IR.


# Type Expression

@docs Type


## Creation

@docs variable, reference, tuple, record, extensibleRecord, function, unit


## Matching

@docs matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit


# Record Field

@docs Field, field, matchField, mapFieldName, mapFieldType


# Declaration

@docs Declaration, typeAliasDeclaration, opaqueTypeDeclaration, customTypeDeclaration, matchCustomTypeDeclaration


# Definition

@docs Definition, typeAliasDefinition, customTypeDefinition


# Constructors

@docs Constructors


# Property Testing

@docs fuzzType


# Serialization

@docs encodeType, decodeType, encodeDeclaration, encodeDefinition

-}

import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControl exposing (AccessControlled, encodeAccessControlled, withPublicAccess)
import Morphir.IR.FQName exposing (FQName, decodeFQName, encodeFQName, fuzzFQName)
import Morphir.IR.Name exposing (Name, decodeName, encodeName, fuzzName)
import Morphir.Pattern exposing (Pattern)
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
type Field extra
    = Field Name (Type extra)


{-| -}
type Declaration extra
    = TypeAliasDeclaration (List Name) (Type extra)
    | OpaqueTypeDeclaration (List Name)
    | CustomTypeDeclaration (List Name) (Constructors extra)


{-| -}
type Definition extra
    = TypeAliasDefinition (List Name) (Type extra)
    | CustomTypeDefinition (List Name) (AccessControlled (Constructors extra))


{-| -}
type alias Constructors extra =
    List (Constructor extra)


{-| -}
type alias Constructor extra =
    ( Name, List ( Name, Type extra ) )


definitionToDeclaration : Definition extra -> Declaration extra
definitionToDeclaration def =
    case def of
        TypeAliasDefinition params exp ->
            TypeAliasDeclaration params exp

        CustomTypeDefinition params accessControlledCtors ->
            case accessControlledCtors |> withPublicAccess of
                Just ctors ->
                    CustomTypeDeclaration params ctors

                Nothing ->
                    OpaqueTypeDeclaration params


mapType : (Type a -> a -> b) -> Type a -> Type b
mapType f tpe =
    case tpe of
        Variable name extra ->
            Variable name (f tpe extra)

        Reference fQName argTypes extra ->
            Reference fQName (argTypes |> List.map (mapType f)) (f tpe extra)

        Tuple elemTypes extra ->
            Tuple (elemTypes |> List.map (mapType f)) (f tpe extra)

        Record fields extra ->
            Record (fields |> List.map (mapFieldType (mapType f))) (f tpe extra)

        ExtensibleRecord name fields extra ->
            ExtensibleRecord name (fields |> List.map (mapFieldType (mapType f))) (f tpe extra)

        Function argType returnType extra ->
            Function (argType |> mapType f) (returnType |> mapType f) (f tpe extra)

        Unit extra ->
            Unit (f tpe extra)


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
typeAliasDeclaration : List Name -> Type extra -> Declaration extra
typeAliasDeclaration typeParams typeExp =
    TypeAliasDeclaration typeParams typeExp


{-| -}
opaqueTypeDeclaration : List Name -> Declaration extra
opaqueTypeDeclaration typeParams =
    OpaqueTypeDeclaration typeParams


{-| -}
customTypeDeclaration : List Name -> Constructors extra -> Declaration extra
customTypeDeclaration typeParams ctors =
    CustomTypeDeclaration typeParams ctors


{-| -}
matchCustomTypeDeclaration : Pattern (List Name) a -> Pattern (Constructors extra) b -> Pattern (Declaration extra) ( a, b )
matchCustomTypeDeclaration matchTypeParams matchCtors declToMatch =
    case declToMatch of
        CustomTypeDeclaration typeParams ctors ->
            Maybe.map2 Tuple.pair
                (matchTypeParams typeParams)
                (matchCtors ctors)

        _ ->
            Nothing


rewriteType : Rewrite (Type extra)
rewriteType rewriteBranch rewriteLeaf typeToRewrite =
    case typeToRewrite of
        Reference fQName argTypes extra ->
            Reference fQName (argTypes |> List.map rewriteBranch) extra

        Tuple elemTypes extra ->
            Tuple (elemTypes |> List.map rewriteBranch) extra

        Record fields extra ->
            Record (fields |> List.map (mapFieldType rewriteBranch)) extra

        ExtensibleRecord varName fields extra ->
            ExtensibleRecord varName (fields |> List.map (mapFieldType rewriteBranch)) extra

        Function argType returnType extra ->
            Function (argType |> rewriteBranch) (returnType |> rewriteBranch) extra

        _ ->
            rewriteLeaf typeToRewrite


{-| Creates a field.

    toIR { foo = Int }
        == record [ field [ "foo" ] SDK.Basics.intType ]

-}
field : Name -> Type extra -> Field extra
field fieldName fieldType =
    Field fieldName fieldType


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
matchField matchFieldName matchFieldType (Field fieldName fieldType) =
    Maybe.map2 Tuple.pair
        (matchFieldName fieldName)
        (matchFieldType fieldType)


{-| Map the name of the field to get a new field.
-}
mapFieldName : (Name -> Name) -> Field extra -> Field extra
mapFieldName f (Field name tpe) =
    Field (f name) tpe


{-| Map the type of the field to get a new field.
-}
mapFieldType : (Type a -> Type b) -> Field a -> Field b
mapFieldType f (Field name tpe) =
    Field name (f tpe)


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
encodeField encodeExtra (Field fieldName fieldType) =
    Encode.list identity
        [ encodeName fieldName
        , encodeType encodeExtra fieldType
        ]


decodeField : Decode.Decoder extra -> Decode.Decoder (Field extra)
decodeField decodeExtra =
    Decode.map2 Field
        (Decode.index 0 decodeName)
        (Decode.index 1 (decodeType decodeExtra))


{-| -}
encodeDeclaration : (extra -> Encode.Value) -> Declaration extra -> Encode.Value
encodeDeclaration encodeExtra decl =
    case decl of
        TypeAliasDeclaration params exp ->
            Encode.object
                [ ( "$type", Encode.string "typeAlias" )
                , ( "params", Encode.list encodeName params )
                , ( "exp", encodeType encodeExtra exp )
                ]

        OpaqueTypeDeclaration params ->
            Encode.object
                [ ( "$type", Encode.string "opaqueType" )
                , ( "params", Encode.list encodeName params )
                ]

        CustomTypeDeclaration params ctors ->
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

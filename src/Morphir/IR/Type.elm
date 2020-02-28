module Morphir.IR.Type exposing
    ( Type
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit
    , Field, field, matchField
    , Declaration
    , Definition
    )

{-| This module contains the building blocks of types in the Morphir IR.


# Type Expression

@docs Type


## Creation

@docs variable, reference, tuple, record, extensibleRecord, function, unit


## Matching

@docs matchVariable, matchReference, matchTuple, matchRecord, matchExtensibleRecord, matchFunction, matchUnit


# Record Field

@docs Field, field, matchField


# Declaration

@docs Declaration


# Definition

@docs Definition

-}

import Morphir.IR.AccessControl exposing (AccessControlled)
import Morphir.IR.Advanced.Type as Advanced
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.Pattern as Pattern exposing (Pattern, matchAny)
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
type alias Type =
    Advanced.Type ()


{-| An opaque representation of a field. It's made up of a name and a type.
-}
type alias Field =
    Advanced.Field ()


{-| -}
type alias Declaration =
    Advanced.Declaration ()


{-| -}
type alias Definition =
    Advanced.Definition ()


{-| -}
type alias Constructors =
    Advanced.Constructors ()


{-| Creates a type variable.

    toIR a == variable [ "a" ]

    toIR fooBar == variable [ "foo", "bar" ]

-}
variable : Name -> Type
variable name =
    Advanced.variable name ()


{-| -}
matchVariable : Pattern Name a -> Pattern Type a
matchVariable matchName =
    Advanced.matchVariable matchName matchAny
        |> Pattern.map Tuple.first


{-| Creates a fully-qualified reference to a type.

    toIR (List Int) ==
        reference SDK.List.listType [ intType ]

    toIR Foo.Bar ==
        reference
            ( [["my"],["lib"]], [["foo"]], ["bar"] )
            []

-}
reference : FQName -> List Type -> Type
reference typeName typeParameters =
    Advanced.reference typeName typeParameters ()


{-| -}
matchReference : Pattern FQName a -> Pattern (List Type) b -> Pattern Type ( a, b )
matchReference matchTypeName matchTypeParameters =
    Advanced.matchReference matchTypeName matchTypeParameters matchAny
        |> Pattern.map (\( a, b, _ ) -> ( a, b ))


{-| Creates a tuple type.

    toIR ( Int, Bool ) ==
        tuple [ basic intType, basic boolType ]

-}
tuple : List Type -> Type
tuple elementTypes =
    Advanced.tuple elementTypes ()


{-| Matches a tuple type and extracts element types.

    matchTuple (list [ matchBasic any, matchBasic any ]) (tuple [ basic intType, basic boolType ]) -- [ IntType, IntType ]

-}
matchTuple : Pattern (List Type) a -> Pattern Type a
matchTuple matchElementTypes =
    Advanced.matchTuple matchElementTypes matchAny
        |> Pattern.map Tuple.first


{-| Creates a record type.

    toIR {} == record []

    toIR { foo : Int } ==
        record
            [ field ["foo"] SDK.Basics.intType
            ]

    toIR { foo : Int, bar : Bool } ==
        record
            [ field ["foo"] SDK.Basics.intType
            , field ["bar"] SDK.Basics.boolType
            ]

-}
record : List Field -> Type
record fieldTypes =
    Advanced.record fieldTypes ()


{-| Match a record type.

    tpe =
        record
            [ field ["foo"] SDK.Basics.intType
            , field ["bar"] SDK.Basics.boolType
            ]

    pattern =
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

    pattern tpe ==
        ( SDK.Basics.intType, SDK.Basics.boolType )

-}
matchRecord : Pattern (List Field) a -> Pattern Type a
matchRecord matchFieldTypes =
    Advanced.matchRecord matchFieldTypes matchAny
        |> Pattern.map Tuple.first


{-| Creates an extensible record type.

    toIR { e | foo : Int } ==
        extensibleRecord (variable ["e"])
            [ field ["foo"] intType
            ]

    toIR { f | foo : Int, bar : Bool } ==
        extensibleRecord (variable ["f"])
            [ field ["foo"] intType
            , field ["bar"] boolType
            ]

-}
extensibleRecord : Name -> List Field -> Type
extensibleRecord variableName fieldTypes =
    Advanced.extensibleRecord variableName fieldTypes ()


{-| -}
matchExtensibleRecord : Pattern Name a -> Pattern (List Field) b -> Pattern Type ( a, b )
matchExtensibleRecord matchVariableName matchFieldTypes =
    Advanced.matchExtensibleRecord matchVariableName matchFieldTypes matchAny
        |> Pattern.map (\( a, b, _ ) -> ( a, b ))


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
function : Type -> Type -> Type
function argumentType returnType =
    Advanced.function argumentType returnType ()


{-| Matches a function type.

    tpe =
        function SDK.Basics.intType SDK.Basics.boolType

    pattern =
        matchFunction matchAny matchAny

    pattern tpe ==
        ( SDK.Basics.intType, SDK.Basics.boolType )

-}
matchFunction : Pattern Type a -> Pattern Type b -> Pattern Type ( a, b )
matchFunction matchArgType matchReturnType =
    Advanced.matchFunction matchArgType matchReturnType matchAny
        |> Pattern.map (\( a, b, _ ) -> ( a, b ))


{-| Creates a unit type.

    toIR () == unit

-}
unit : Type
unit =
    Advanced.unit ()


{-| -}
matchUnit : Pattern Type ()
matchUnit =
    Advanced.matchUnit matchAny


{-| Creates a field.

    toIR { foo : Int } ==
        record [ field ["foo"] SDK.Basics.intType ]

-}
field : Name -> Type -> Field
field fieldName fieldType =
    Advanced.field fieldName fieldType


{-| Matches a field.

    let
        field =
            field ["foo"] SDK.Basics.intType

        pattern =
            matchField matchAny matchAny
    in
    pattern field ==
        Just ( ["foo"], SDK.Basics.intType )

-}
matchField : (Name -> Maybe a) -> (Type -> Maybe b) -> Pattern Field ( a, b )
matchField matchFieldName matchFieldType =
    Advanced.matchField matchFieldName matchFieldType


mapFieldName : (Name -> Name) -> Field -> Field
mapFieldName f =
    Advanced.mapFieldName f


mapFieldType : (Type -> Type) -> Field -> Field
mapFieldType f =
    Advanced.mapFieldType f

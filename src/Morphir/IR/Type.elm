module Morphir.IR.Type exposing
    ( Type(..)
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , Field, mapFieldName, mapFieldType
    , Specification(..), typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification
    , Definition(..), typeAliasDefinition, customTypeDefinition, definitionToSpecification
    , Constructors, Constructor(..)
    , mapTypeAttributes, mapSpecificationAttributes, mapDefinitionAttributes, mapDefinition, eraseAttributes
    )

{-| This module contains the building blocks of types in the Morphir IR.


# Type Expression

@docs Type


## Creation

@docs variable, reference, tuple, record, extensibleRecord, function, unit


# Record Field

@docs Field, mapFieldName, mapFieldType


# Specification

@docs Specification, typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification


# Definition

@docs Definition, typeAliasDefinition, customTypeDefinition, definitionToSpecification


# Constructors

@docs Constructors, Constructor


# Mapping

@docs mapTypeAttributes, mapSpecificationAttributes, mapDefinitionAttributes, mapDefinition, eraseAttributes

-}

import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.ListOfResults as ListOfResults


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
type Constructor a
    = Constructor Name (List ( Name, Type a ))


{-| -}
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


{-| -}
mapSpecificationAttributes : (a -> b) -> Specification a -> Specification b
mapSpecificationAttributes f spec =
    case spec of
        TypeAliasSpecification params tpe ->
            TypeAliasSpecification params (mapTypeAttributes f tpe)

        OpaqueTypeSpecification params ->
            OpaqueTypeSpecification params

        CustomTypeSpecification params constructors ->
            CustomTypeSpecification params
                (constructors
                    |> List.map
                        (\(Constructor ctorName ctorArgs) ->
                            Constructor ctorName
                                (ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            ( argName, mapTypeAttributes f argType )
                                        )
                                )
                        )
                )


{-| -}
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
                            (\(Constructor ctorName ctorArgs) ->
                                ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            f argType
                                                |> Result.map (Tuple.pair argName)
                                        )
                                    |> ListOfResults.liftAllErrors
                                    |> Result.map (Constructor ctorName)
                            )
                        |> ListOfResults.liftAllErrors
                        |> Result.map (AccessControlled constructors.access)
                        |> Result.mapError List.concat
            in
            ctorsResult
                |> Result.map (CustomTypeDefinition params)


{-| -}
mapDefinitionAttributes : (a -> b) -> Definition a -> Definition b
mapDefinitionAttributes f def =
    case def of
        TypeAliasDefinition params tpe ->
            TypeAliasDefinition params (mapTypeAttributes f tpe)

        CustomTypeDefinition params constructors ->
            CustomTypeDefinition params
                (AccessControlled constructors.access
                    (constructors.value
                        |> List.map
                            (\(Constructor ctorName ctorArgs) ->
                                Constructor ctorName
                                    (ctorArgs
                                        |> List.map
                                            (\( argName, argType ) ->
                                                ( argName, mapTypeAttributes f argType )
                                            )
                                    )
                            )
                    )
                )


{-| -}
mapTypeAttributes : (a -> b) -> Type a -> Type b
mapTypeAttributes f tpe =
    case tpe of
        Variable a name ->
            Variable (f a) name

        Reference a fQName argTypes ->
            Reference (f a) fQName (argTypes |> List.map (mapTypeAttributes f))

        Tuple a elemTypes ->
            Tuple (f a) (elemTypes |> List.map (mapTypeAttributes f))

        Record a fields ->
            Record (f a) (fields |> List.map (mapFieldType (mapTypeAttributes f)))

        ExtensibleRecord a name fields ->
            ExtensibleRecord (f a) name (fields |> List.map (mapFieldType (mapTypeAttributes f)))

        Function a argType returnType ->
            Function (f a) (argType |> mapTypeAttributes f) (returnType |> mapTypeAttributes f)

        Unit a ->
            Unit (f a)


{-| -}
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


{-| -}
eraseAttributes : Definition a -> Definition ()
eraseAttributes typeDef =
    case typeDef of
        TypeAliasDefinition typeVars tpe ->
            TypeAliasDefinition typeVars (mapTypeAttributes (\_ -> ()) tpe)

        CustomTypeDefinition typeVars acsCtrlConstructors ->
            let
                eraseCtor : Constructor a -> Constructor ()
                eraseCtor (Constructor name types) =
                    let
                        extraErasedTypes : List ( Name, Type () )
                        extraErasedTypes =
                            types
                                |> List.map (\( n, t ) -> ( n, mapTypeAttributes (\_ -> ()) t ))
                    in
                    Constructor name extraErasedTypes

                eraseAccessControlledCtors : AccessControlled (Constructors a) -> AccessControlled (Constructors ())
                eraseAccessControlledCtors acsCtrlCtors =
                    AccessControlled.map
                        (\ctors -> ctors |> List.map eraseCtor)
                        acsCtrlCtors
            in
            CustomTypeDefinition typeVars (eraseAccessControlledCtors acsCtrlConstructors)


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
typeAliasDefinition : List Name -> Type a -> Definition a
typeAliasDefinition typeParams typeExp =
    TypeAliasDefinition typeParams typeExp


{-| -}
customTypeDefinition : List Name -> AccessControlled (Constructors a) -> Definition a
customTypeDefinition typeParams ctors =
    CustomTypeDefinition typeParams ctors


{-| -}
typeAliasSpecification : List Name -> Type a -> Specification a
typeAliasSpecification typeParams typeExp =
    TypeAliasSpecification typeParams typeExp


{-| -}
opaqueTypeSpecification : List Name -> Specification a
opaqueTypeSpecification typeParams =
    OpaqueTypeSpecification typeParams


{-| -}
customTypeSpecification : List Name -> Constructors a -> Specification a
customTypeSpecification typeParams ctors =
    CustomTypeSpecification typeParams ctors


{-| Map the name of the field to get a new field.
-}
mapFieldName : (Name -> Name) -> Field a -> Field a
mapFieldName f field =
    Field (f field.name) field.tpe


{-| Map the type of the field to get a new field.
-}
mapFieldType : (Type a -> Type b) -> Field a -> Field b
mapFieldType f field =
    Field field.name (f field.tpe)

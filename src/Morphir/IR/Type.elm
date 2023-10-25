{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.Type exposing
    ( Type(..)
    , variable, reference, tuple, record, extensibleRecord, function, unit
    , Field, mapFieldName, mapFieldType
    , Specification(..), typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification
    , Definition(..), typeAliasDefinition, customTypeDefinition, definitionToSpecification, definitionToSpecificationWithPrivate
    , Constructors, Constructor, ConstructorArgs
    , mapTypeAttributes, mapSpecificationAttributes, mapDefinitionAttributes, mapDefinition, typeAttributes
    , eraseAttributes, collectVariables, collectReferences, collectReferencesFromDefintion, substituteTypeVariables, toString, DerivedTypeSpecificationDetails
    )

{-| Like any other programming languages Morphir has a type system as well. This module defines the building blocks of
that type system. If you want to learn more about type systems check out
[Wikipedia: Type system](https://en.wikipedia.org/wiki/Type_system).

Morphir's type system is heavily inspired by Elm's type system so the best way to understand the building blocks here is
through some Elm examples. Let's take this bit of Elm code as a starting point:

    type alias MyInteger =
        Int

    type alias MyRecord a =
        { foo : List a
        }

    type Foo a
        = Bar a
        | Baz

These would translate to type definitions in Morphir which is represented by the [`Definition`](#Definition) type.
Definitions themselves don't have a name. It's the Module that contains that information in the `types` dictionary as a
key. The type parameters and the right-hand side of the declaration is contained in the [`Definition`](#Definition) type
itself. This is how the above would translate to the IR (some parts are omitted to reduce noise):

    { types =
        Dict.fromList
            [ ( [ "my", "integer" ], TypeAliasDefinition [] (...) )
            , ( [ "my", "record" ], TypeAliasDefinition [ [ "a" ] ] (...) )
            , ( [ "foo" ], CustomTypeDefinition [ [ "a" ], [ "b" ] ] (...) )
            ]
    , values =
        Dict.empty
    }

Type aliases simply assign a new name to a type expression. This type expression can be a reference to another type or
a record type or any other type expression. Custom types are defined by a list of constructors. Each of those
constructors have a list of arguments. Each argument is a type expression.

Here is the full definition for reference:

    { types =
        Dict.fromList
            [ ( [ "my", "integer" ]
              , TypeAliasDefinition []
                    (Reference (fqn "Morphir.SDK" "Basics" "Int") [])
              )
            , ( [ "my", "record" ]
              , TypeAliasDefinition [ [ "a" ] ]
                    (Record ()
                        [ Field [ "foo" ] (Reference () (fqn "Morphir.SDK" "List" "List") [ Variable () [ "a" ] ])
                        ]
                    )
              )
            , ( [ "foo" ]
              , CustomTypeDefinition [ [ "a" ], [ "b" ] ]
                    (AccessControlled.public
                        [ Constructor [ "bar" ] [ ( [ "arg", "1" ], Variable () [ "a" ] ) ]
                        , Constructor [ "baz" ] [ ( [ "arg", "1" ], Variable () [ "b" ] ) ]
                        ]
                    )
              )
            ]
    , values =
        Dict.empty
    }


# Type Expression

@docs Type


## Creation

@docs variable, reference, tuple, record, extensibleRecord, function, unit


# Record Field

@docs Field, mapFieldName, mapFieldType


# Specification

@docs Specification, typeAliasSpecification, opaqueTypeSpecification, customTypeSpecification, DerivedTypeSpecificationDetails


# Definition

@docs Definition, typeAliasDefinition, customTypeDefinition, definitionToSpecification, definitionToSpecificationWithPrivate


# Constructors

@docs Constructors, Constructor, ConstructorArgs


# Utilities

@docs mapTypeAttributes, mapSpecificationAttributes, mapDefinitionAttributes, mapDefinition, typeAttributes

@docs eraseAttributes, collectVariables, collectReferences, collectReferencesFromDefintion, substituteTypeVariables, toString

-}

import Dict exposing (Dict)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, withPrivateAccess, withPublicAccess)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.SDK.ResultList as ResultList
import Set exposing (Set)


{-| Represents a type expression that can appear in various places within the IR. It can be the right-hand-side of
a type alias declaration, input and output types of a function or as an annotation on values after type inference is
done.

Type are modeled as expression trees: a recursive data structure with various node types. The type argument `a` allows
us to assign some additional attributes to each node in the tree. Here are some details on each node type in the tree:

  - **Variable**
      - Represents a type variable.
      - It has a single argument which captures the name of the variable.
      - [Wikipedia: Type variable](https://en.wikipedia.org/wiki/Type_variable)
      - [creation](#variable), [matching](#matchVariable)
  - **Reference**
      - A fully-qualified reference to some other type or type alias within the package or one of its dependencies.
      - References to built-in types (like `Int`, `String`, ...) don't have an associated definition.
      - [creation](#reference), [matching](#matchReference)
  - **Tuple**
      - A tuple is a composition of other types (potentially other tuples).
      - The order of types is relevant so the easiest way to think about it is as a list of types.
      - A tuple can have any number of elements and there is no restriction on the element types.
      - A tuple with zero elements is equivalent with `Unit`.
      - A tuple with a single element is equivalent to the element type itself.
      - [Wikipedia: Tuple](https://en.wikipedia.org/wiki/Tuple)
      - [creation](#tuple), [matching](#matchTuple)
  - **Record**
      - A record is a composition of other types like tuples but types are identified by a field name instead of an index.
      - The best way to think of a record is as a dictionary of types.
      - Our representation captures the order of fields for convenience but the order should not be considered for type
        equivalence.
      - [Wikipedia: Record](https://en.wikipedia.org/wiki/Record_(computer_science))
      - [Elm-lang: Records](https://elm-lang.org/docs/records)
      - Utilities: [creation](#record), [matching](#matchRecord)
  - **ExtensibleRecord**
      - Similar to records but while record types declare that the underlying object has "exactly these fields" an
        extensible record declares that the object has "at least these fields".
      - Besides the list of fields you need to specify a variable name that will be used to abstract over the type
        that's being extended.
      - [Elm: Extensible records](https://ckoster22.medium.com/advanced-types-in-elm-extensible-records-67e9d804030d)
      - [creation](#extensibleRecord), [matching](#matchExtensibleRecord)
  - **Function**
      - Represents the type of a function. The two arguments are the argument and the return type of the function.
      - Multi-argument functions are represented by composing functions:
          - `a -> b -> c` is represented as `a -> (b -> c)`
      - [Wikipedia: Function type](https://en.wikipedia.org/wiki/Function_type)
      - [creation](#function), [matching](#matchFunction)
  - **Unit**
      - Unit type is used as a placeholder in situations where a type is required but the corresponding value is unused.
      - Semantically the unit type represents a set that has exactly one value which is often called unit.
      - Unit corresponds to void in some other programming languages.
      - [Wikipedia: Unit type](https://en.wikipedia.org/wiki/Unit_type)
      - [creation](#unit), [matching](#matchUnit)

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


{-| Represents the specification (in other words the interface) of a type. There are 4 different shapes:

  - **TypeAliasSpecification**
      - Represents an alias for another type.
      - An Elm example would be `type alias Foo = String`
  - **OpaqueTypeSpecification**
      - Represents a type with an unknown structure.
      - In Elm you could achieve this with a custom type that doesn't expose its constructors.
      - Opaque types cannot be automatically serialized by Morphir tools since the structure is unknown.
      - If you need a type with a platform-specific representation but with the ability to serialize use
        **DerivedTypeSpecification** instead.
  - **CustomTypeSpecification**
      - Represents a tagged union type.
      - In Elm this corresponds to a custom type: `type Foo = Bar | Baz Int`
  - **DerivedTypeSpecification**
      - Represents a type with an unknown structure but with explicit functions to map from and to a known type.
      - For example a `LocalDate` may have different representations on various platforms but we can define a standard
        way to map from and to a string.
      - Derived types are serializable by the Morphir tooling if the base type is serializable.

The first `List Name` argument represents type parameters in each variant. For example `type alias Foo a b = ...`
would map to `TypeAliasSpecification [ ["a"], ["b"] ] ...`.

-}
type Specification a
    = TypeAliasSpecification (List Name) (Type a)
    | OpaqueTypeSpecification (List Name)
    | CustomTypeSpecification (List Name) (Constructors a)
    | DerivedTypeSpecification (List Name) (DerivedTypeSpecificationDetails a)

{-| Details of the base type of a Derived Type
-}
type alias DerivedTypeSpecificationDetails a =
    { baseType : Type a
    , fromBaseType : FQName
    , toBaseType : FQName
    }


{-| This syntax represents a type definition. For example:

  - `type alias Foo a = {bar : Maybe a, qux : Int}`
  - `type MyList a = End | Cons a (MyList a)`

In the definition, the `List Name` refers to type parameters on the LHS
and `Type extra` refers to the RHS

-}
type Definition a
    = TypeAliasDefinition (List Name) (Type a)
    | CustomTypeDefinition (List Name) (AccessControlled (Constructors a))


{-| Constructors in a dictionary keyed by their name. The values are the argument types for each constructor.
-}
type alias Constructors a =
    Dict Name (ConstructorArgs a)


{-| Represents a single constructor with a name and arguments.
-}
type alias Constructor a =
    ( Name, ConstructorArgs a )


{-| Represents a list of constructor arguments.
-}
type alias ConstructorArgs a =
    List ( Name, Type a )


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
definitionToSpecificationWithPrivate : Definition a -> Specification a
definitionToSpecificationWithPrivate def =
    case def of
        TypeAliasDefinition params exp ->
            TypeAliasSpecification params exp

        CustomTypeDefinition params accessControlledCtors ->
            accessControlledCtors
                |> withPrivateAccess
                |> CustomTypeSpecification params


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
                    |> Dict.map
                        (\_ ctorArgs ->
                            ctorArgs
                                |> List.map
                                    (\( argName, argType ) ->
                                        ( argName, mapTypeAttributes f argType )
                                    )
                        )
                )

        DerivedTypeSpecification params config ->
            DerivedTypeSpecification params
                { baseType = mapTypeAttributes f config.baseType
                , fromBaseType = config.fromBaseType
                , toBaseType = config.toBaseType
                }


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
                        |> Dict.toList
                        |> List.map
                            (\( ctorName, ctorArgs ) ->
                                ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            f argType
                                                |> Result.map (Tuple.pair argName)
                                        )
                                    |> ResultList.keepAllErrors
                                    |> Result.map (Tuple.pair ctorName)
                            )
                        |> ResultList.keepAllErrors
                        |> Result.map (Dict.fromList >> AccessControlled constructors.access)
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
                        |> Dict.map
                            (\_ ctorArgs ->
                                ctorArgs
                                    |> List.map
                                        (\( argName, argType ) ->
                                            ( argName, mapTypeAttributes f argType )
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
        Variable a _ ->
            a

        Reference a _ _ ->
            a

        Tuple a _ ->
            a

        Record a _ ->
            a

        ExtensibleRecord a _ _ ->
            a

        Function a _ _ ->
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
                eraseCtor : List ( Name, Type a ) -> List ( Name, Type () )
                eraseCtor types =
                    types
                        |> List.map (\( n, t ) -> ( n, mapTypeAttributes (\_ -> ()) t ))

                eraseAccessControlledCtors : AccessControlled (Constructors a) -> AccessControlled (Constructors ())
                eraseAccessControlledCtors acsCtrlCtors =
                    AccessControlled.map
                        (\ctors -> ctors |> Dict.map (\_ -> eraseCtor))
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


{-| Collect all variables in a type recursively.
-}
collectVariables : Type ta -> Set Name
collectVariables tpe =
    let
        collectUnion : List (Type ta) -> Set Name
        collectUnion values =
            values
                |> List.map collectVariables
                |> List.foldl Set.union Set.empty
    in
    case tpe of
        Variable _ name ->
            Set.singleton name

        Reference _ _ args ->
            collectUnion args

        Tuple _ elements ->
            collectUnion elements

        Record _ fields ->
            collectUnion (fields |> List.map .tpe)

        ExtensibleRecord _ subjectName fields ->
            collectUnion (fields |> List.map .tpe)
                |> Set.insert subjectName

        Function _ argType returnType ->
            collectUnion [ argType, returnType ]

        Unit _ ->
            Set.empty


{-| Collect all references in a type recursively.
-}
collectReferences : Type ta -> Set FQName
collectReferences tpe =
    let
        collectUnion : List (Type ta) -> Set FQName
        collectUnion values =
            values
                |> List.map collectReferences
                |> List.foldl Set.union Set.empty
    in
    case tpe of
        Variable _ _ ->
            Set.empty

        Reference _ fQName args ->
            collectUnion args
                |> Set.insert fQName

        Tuple _ elements ->
            collectUnion elements

        Record _ fields ->
            collectUnion (fields |> List.map .tpe)

        ExtensibleRecord _ _ fields ->
            collectUnion (fields |> List.map .tpe)

        Function _ argType returnType ->
            collectUnion [ argType, returnType ]

        Unit _ ->
            Set.empty


{-| Collect references from a Type Definition
-}
collectReferencesFromDefintion : Definition ta -> Set FQName
collectReferencesFromDefintion typeDef =
    case typeDef of
        TypeAliasDefinition _ tpe ->
            collectReferences tpe

        CustomTypeDefinition _ accessControlledType ->
            accessControlledType.value
                |> Dict.values
                |> List.concat
                |> List.map (Tuple.second >> collectReferences)
                |> List.foldl Set.union Set.empty


{-| Substitute type variables recursively.
-}
substituteTypeVariables : Dict Name (Type ta) -> Type ta -> Type ta
substituteTypeVariables mapping original =
    case original of
        Variable a varName ->
            mapping
                |> Dict.get varName
                |> Maybe.withDefault original

        Reference a fQName typeArgs ->
            Reference a
                fQName
                (typeArgs
                    |> List.map (substituteTypeVariables mapping)
                )

        Tuple a elemTypes ->
            Tuple a
                (elemTypes
                    |> List.map (substituteTypeVariables mapping)
                )

        Record a fields ->
            Record a
                (fields
                    |> List.map
                        (\field ->
                            Field field.name (substituteTypeVariables mapping field.tpe)
                        )
                )

        ExtensibleRecord a name fields ->
            ExtensibleRecord a
                name
                (fields
                    |> List.map
                        (\field ->
                            Field field.name (substituteTypeVariables mapping field.tpe)
                        )
                )

        Function a argType returnType ->
            Function a
                (substituteTypeVariables mapping argType)
                (substituteTypeVariables mapping returnType)

        Unit a ->
            Unit a


{-| Get a compact string representation of the type.
-}
toString : Type a -> String
toString tpe =
    case tpe of
        Variable _ name ->
            Name.toCamelCase name

        Reference _ ( packageName, moduleName, localName ) args ->
            let
                referenceName : String
                referenceName =
                    String.join "."
                        [ Path.toString Name.toTitleCase "." packageName
                        , Path.toString Name.toTitleCase "." moduleName
                        , Name.toTitleCase localName
                        ]
            in
            referenceName
                :: List.map toString args
                |> String.join " "

        Tuple _ elems ->
            String.concat
                [ "( ", List.map toString elems |> String.join ", ", " )" ]

        Record _ fields ->
            String.concat
                [ "{ "
                , fields
                    |> List.map
                        (\field ->
                            String.concat [ Name.toCamelCase field.name, " : ", toString field.tpe ]
                        )
                    |> String.join ", "
                , " }"
                ]

        ExtensibleRecord _ varName fields ->
            String.concat
                [ "{ "
                , Name.toCamelCase varName
                , " | "
                , fields
                    |> List.map
                        (\field ->
                            String.concat [ Name.toCamelCase field.name, " : ", toString field.tpe ]
                        )
                    |> String.join ", "
                , " }"
                ]

        Function _ ((Function _ _ _) as argType) returnType ->
            String.concat [ "(", toString argType, ") -> ", toString returnType ]

        Function _ argType returnType ->
            String.concat [ toString argType, " -> ", toString returnType ]

        Unit _ ->
            "()"

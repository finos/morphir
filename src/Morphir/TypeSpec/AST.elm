module Morphir.TypeSpec.AST exposing (..)

import Dict exposing (Dict)


type alias Name =
    String


type alias FieldDef =
    { tpe : Type
    , optional : Bool
    }


type alias Fields =
    Dict Name FieldDef


type ImportDeclaration
    = LibraryImport String
    | FileImport String


type alias NamespaceDeclaration =
    Dict Name TypeDefinition


type alias TemplateArgs =
    List Name


type alias Namespace =
    List Name


type alias EnumValues =
    List Name


type TypeDefinition
    = Alias TemplateArgs Type
    | Model TemplateArgs Fields
    | Enum EnumValues
    | ScalarDefinition ScalarType


{-| Scalar Types are types without fields. Some types are
-}
type ScalarType
    = Boolean
    | String
    | Integer
    | Float
    | PlainDate
    | PlainTime
    | Null


{-| -}
type Type
    = Scalar ScalarType
    | Array ArrayType
    | Variable Name
    | Reference (List Type) Namespace Name
    | Union (List Type)
    | Const String
    | Object Fields


{-| Array type in TypeSpec is a superset that represents both the
-}
type ArrayType
    = ListType Type
    | TupleType (List Type)

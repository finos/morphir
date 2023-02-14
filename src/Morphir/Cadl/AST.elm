module Morphir.Cadl.AST exposing (..)

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


type Type
    = Boolean
    | String
    | Integer
    | Float
    | PlainDate
    | PlainTime
    | Array ArrayType
    | Variable Name
    | Reference (List Type) Namespace Name
    | Union (List Type)
    | Const String
    | Object Fields
    | Null


type ArrayType
    = ListType Type
    | TupleType (List Type)

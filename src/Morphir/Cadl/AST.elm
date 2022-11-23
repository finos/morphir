module Morphir.Cadl.AST exposing (..)

import Dict exposing (Dict)


type alias Name =
    String


type alias Field =
    { name : Name
    , tpe : Type
    }


type alias NamespaceDeclaration =
    Dict Name TypeDefinition


type alias Templates =
    List Type


type TypeDefinition
    = Alias Name (List Name) Type
    | Model Name Namespace (List Field)


type alias Namespace =
    List Name


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
    | Null


type ArrayType
    = ListType Type
    | TupleType (List Type)

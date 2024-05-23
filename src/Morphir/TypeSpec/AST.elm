module Morphir.TypeSpec.AST exposing (..)

import Dict exposing (Dict)


type alias Name =
    String


{-| This represents a field in a model with a type and specifying if a value is required or not
-}
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


{-| TemplateArgs are a list of various types' name which a type definition could be based on.
This concept is similar to Generics in other Languages.
-}
type alias TemplateArgs =
    List Name


type alias Namespace =
    List Name


type alias EnumValues =
    List Name


{-|

  - **Alias** - Expressing a type as a named alias.
    Eg: alias Address = string;

  - **Model** - Used to express a type with typed fields
    Eg: model Person {
    firstname: string,
    lastname: string,
    ...
    }

  - **Enums** - These are group types expressed as a single unit and
    any value using or returning this type can only be of one of its type.
    Eg: enum Currency {
    USD,
    GBP,
    ...
    }
      - **ScalarDefinition**
        IN a mode

-}
type TypeDefinition
    = Alias TemplateArgs Type
    | Model TemplateArgs Fields
    | Enum EnumValues
    | ScalarDefinition Type


{-| Scalar Types are types without fields.
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

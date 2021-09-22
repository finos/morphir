module Morphir.TypeScript.AST exposing
    ( TypeDef(..), TypeExp(..), FieldDef
    , CompilationUnit
    )

{-| This module contains the TypeScript AST (Abstract Syntax Tree). The purpose of this AST is to make it easier to
generate valid TypeScript source code and to separate the language syntax from low-level formatting concerns. We use
this AST as the output of the TypeScript backend and also as the input of the pretty-printer that turns it into the
final text representation.

The AST is maintained manually and it does not have to cover the whole language. We focus on the parts of the language
that we use in the backend.

@docs TypeDef, TypeExp, FieldDef

-}


{-| -}
type alias CompilationUnit =
    { dirPath : List String
    , fileName : String
    , typeDefs : List TypeDef
    }


{-| Represents a type definition.
-}
type TypeDef
    = TypeAlias String TypeExp
    | Interface String (List FieldDef)


{-| A type expression represents the right-hand side of a type annotation or a type alias.

The structure follows the documentation here:
<https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#the-primitives-string-number-and-boolean>

Only a small subset of the type-system is currently implemented.

-}
type TypeExp
    = String
    | Number
    | Boolean
    | Union (List TypeExp)
    | TypeRef String
    | Any
    | UnhandledType String


{-| Represents a field as a name and type pair.
-}
type alias FieldDef =
    ( String, TypeExp )

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


module Morphir.Scala.AST exposing
    ( Name, Path, Documented, Annotated, withAnnotation, withoutAnnotation, CompilationUnit, PackageDecl
    , ImportDecl, ImportName(..), Mod(..), TypeDecl(..), ArgDecl, ArgValue(..), MemberDecl(..)
    , Type(..), Value(..), Pattern(..), Lit(..), Generator(..)
    , nameOfTypeDecl
    )

{-| Scala's abstract-syntax tree. This is a custom built AST that focuses on the subset of Scala features that our
generator uses. It's a relatively large portion of the language but it's not aiming to be complete.


# Abstract Syntax Tree

@docs Name, Path, Documented, Annotated, withAnnotation, withoutAnnotation, CompilationUnit, PackageDecl
@docs ImportDecl, ImportName, Mod, TypeDecl, ArgDecl, ArgValue, MemberDecl
@docs Type, Value, Pattern, Lit, Generator


# Utilities

@docs nameOfTypeDecl

-}

import Decimal exposing (Decimal)

{-| -}
type alias Name =
    String


{-| -}
type alias Path =
    List Name


{-| -}
type alias Documented a =
    { doc : Maybe String
    , value : a
    }


{-| -}
type alias Annotated a =
    { annotations : List String
    , value : a
    }


{-| Wrap in Annotated without any annotation values.
-}
withoutAnnotation : a -> Annotated a
withoutAnnotation a =
    Annotated [] a


{-| Wrap in Annotated with an annotation value.
-}
withAnnotation : List String -> a -> Annotated a
withAnnotation annotations a =
    Annotated annotations a


{-| -}
type alias CompilationUnit =
    { dirPath : List String
    , fileName : String
    , packageDecl : PackageDecl
    , imports : List ImportDecl
    , typeDecls : List (Documented (Annotated TypeDecl))
    }


{-| -}
type alias PackageDecl =
    List String


{-| -}
type alias ImportDecl =
    { isAbsolute : Bool
    , packagePrefix : List String
    , importNames : List ImportName
    }


{-| -}
type ImportName
    = ImportName String
    | ImportRename String String


{-| -}
type Mod
    = Sealed
    | Final
    | Case
    | Val
    | Package
    | Implicit
    | Private (Maybe String)
    | Abstract


{-| -}
type TypeDecl
    = Trait
        { modifiers : List Mod
        , name : Name
        , typeArgs : List Type
        , extends : List Type
        , members : List (Annotated MemberDecl)
        }
    | Class
        { modifiers : List Mod
        , name : Name
        , typeArgs : List Type
        , ctorArgs : List (List ArgDecl)
        , extends : List Type
        , members : List (Annotated MemberDecl)
        , body : List Value
        }
    | Object
        { modifiers : List Mod
        , name : Name
        , extends : List Type
        , members : List (Annotated MemberDecl)
        , body : Maybe Value
        }


{-| -}
type alias ArgDecl =
    { modifiers : List Mod
    , tpe : Type
    , name : Name
    , defaultValue : Maybe Value
    }


{-| -}
type ArgValue
    = ArgValue (Maybe Name) Value


{-| -}
type MemberDecl
    = TypeAlias
        { alias : Name
        , typeArgs : List Type
        , tpe : Type
        }
    | ValueDecl
        { modifiers : List Mod
        , pattern : Pattern
        , valueType : Maybe Type
        , value : Value
        }
    | FunctionDecl
        { modifiers : List Mod
        , name : Name
        , typeArgs : List Type
        , args : List (List ArgDecl)
        , returnType : Maybe Type
        , body : Maybe Value
        }
    | MemberTypeDecl TypeDecl


{-| -}
type Type
    = TypeVar Name
    | TypeRef Path Name
    | TypeOfValue Path
    | TypeApply Type (List Type)
    | TypeParametrized Type (List Type) Type
    | TupleType (List Type)
    | StructuralType (List MemberDecl)
    | FunctionType Type Type
    | CommentedType Type String


{-| Type that represents a Scala Value.

These are the supported Values:

  - **Literal**
      - Specifies a Scala literal
  - **Variable**
      - Specifies a Scala variable
  - **Ref**
      - Represents a Scala function reference
  - **Select**
      - Represents an operation with a target expression and a name, where the name is applied with a '.' to the target.
      - For example, '..obj.mymethod(param1, param2)' where 'mymethod' is the name and '..obj' is the target expression.
      - Any argument list needed, such as '(param1, param2)', is appended to the Select value.
  - **Wildcard**
  - **Apply**
      - Apply a Scala function
  - **UnOp**
  - **BinOp**
      - Scala binary operation
  - **Lambda**
  - **Block**
  - **MatchCases**
  - **Match**
  - **IfElse**
  - **Tuple**
  - **StructuralValue**
  - **Unit**
      - Return type of a Scala function which doesn't return anything
      - Unit is represented as '{}'
  - **This**
  - **CommentedValue**
  - **ForComp**
  - **TypeAscripted**

-}
type Value
    = Literal Lit
    | Variable Name
    | Ref Path Name
    | Select Value Name
    | Wildcard
    | Apply Value (List ArgValue)
    | UnOp String Value
    | BinOp Value String Value
    | Lambda (List ( Name, Maybe Type )) Value
    | Block (List MemberDecl) Value
    | MatchCases (List ( Pattern, Value ))
    | Match Value Value
    | IfElse Value Value Value
    | Tuple (List Value)
    | StructuralValue (List ( Name, Value ))
    | Unit
    | This
    | CommentedValue Value String
    | ForComp (List Generator) Value
    | TypeAscripted Value Type
    | New Path Name (List ArgValue)
    | Throw Value


{-| -}
type Generator
    = Extract Pattern Value
    | Bind Pattern Value
    | Guard Value


{-| -}
type Pattern
    = WildcardMatch
    | NamedMatch Name
    | AliasedMatch Name Pattern
    | LiteralMatch Lit
    | UnapplyMatch Path Name (List Pattern)
    | TupleMatch (List Pattern)
    | EmptyListMatch
    | HeadTailMatch Pattern Pattern
    | CommentedPattern Pattern String


{-| -}
type Lit
    = BooleanLit Bool
    | CharacterLit Char
    | StringLit String
    | IntegerLit Int
    | FloatLit Float
    | DecimalLit Decimal
    | NullLit


{-| -}
nameOfTypeDecl : TypeDecl -> Name
nameOfTypeDecl typeDecl =
    case typeDecl of
        Trait data ->
            data.name

        Class data ->
            data.name

        Object data ->
            data.name

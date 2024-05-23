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


module SlateX.DevBot.Java.Ast exposing (..)

{-| Java AST based on: https://docs.oracle.com/javase/specs/jls/se7/html/jls-18.html
-}
type alias TODO = Never


type alias Identifier =
    String


type alias QualifiedIdentifier =
    List Identifier


type alias CompilationUnit =
    { filePath : List String
    , fileName : String
    , packageDecl : Maybe PackageDeclaration
    , imports : List ImportDeclaration
    , typeDecls : List TypeDeclaration
    }


type alias PackageDeclaration =
    { annotations : List Annotation
    , qualifiedName : QualifiedIdentifier
    }


type ImportDeclaration
    = Import QualifiedIdentifier Bool
    | StaticImport QualifiedIdentifier Bool


type TypeDeclaration
    = Class
        { modifiers : List Modifier
        , name : Identifier
        , typeParams : List Identifier
        , extends : Maybe Type
        , implements : List Type
        , members : List MemberDecl
        }
    | Interface
        { modifiers : List Modifier
        , name : Identifier
        , typeParams : List Identifier
        , extends : List Type
        , members : List MemberDecl
        }
    | Enum
        { modifiers : List Modifier
        , name : Identifier
        , implements : List Type
        , values : List Identifier
        }


type Modifier
    = Public
    | Private
    | Static
    | Abstract
    | Final

type MemberDecl
    = Field
        { modifiers : List Modifier
        , tpe : Type
        , name : Identifier
        }
    | Constructor
        { modifiers : List Modifier
        , args : List ( Identifier, Type )
        , body : Maybe (List Exp)
        }
    | Method
        { modifiers : List Modifier
        , typeParams : List Identifier
        , returnType : Type
        , name : Identifier
        , args : List ( Identifier, Type )
        , body : List Exp
        }


type Type
    = Void
    | TypeRef QualifiedIdentifier
    | TypeConst QualifiedIdentifier (List Type)
    | TypeVar Identifier
    | Predicate Type
    | Function Type Type


type alias Annotation = TODO


type Exp
    = VariableDecl (List Modifier) Type Identifier (Maybe Exp)
    | Assign Exp Exp
    | Return Exp
    | Throw Exp
    | Statements (List Exp) 
    | BooleanLit Bool
    | StringLit String
    | IntLit Int
    | Variable Identifier
    | This
    | Select Exp Identifier
    | BinOp Exp String Exp
    | ValueRef QualifiedIdentifier
    | Apply Exp (List Exp)
    | Lambda (List Identifier) Exp
    | Ternary Exp Exp Exp
    | IfElse Exp (List Exp) (List Exp)
    | ConstructorRef QualifiedIdentifier
    | UnaryOp String Exp
    | Cast Type Exp
    | Null
    --| Switch Exp (List ( Exp, Exp )) (Maybe Exp)

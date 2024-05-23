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


module SlateX.DevBot.Scala.AST exposing (..)


type alias Name = String


type alias Path = List Name


type alias CompilationUnit =
    { dirPath : List String
    , fileName : String
    , packageDecl : PackageDecl
    , imports : List ImportDecl
    , typeDecls : List TypeDecl
    }


type alias PackageDecl = List String


type alias ImportDecl =
    { isAbsolute : Bool
    , packagePrefix : List String
    , importNames : List ImportName
    }


type ImportName
    = ImportName String
    | ImportRename String String


type Mod
    = Sealed
    | Final
    | Case
    | Val
    | Package
    | Implicit


type TypeDecl
    = Trait 
        { modifiers : List Mod
        , name : Name
        , typeArgs : List Type
        , extends : List Type
        , members : List MemberDecl
        }
    | Class    
        { modifiers : List Mod
        , name : Name
        , typeArgs : List Type
        , ctorArgs : List (List ArgDecl)
        , extends : List Type
        }
    | Object
        { modifiers : List Mod
        , name : Name
        , extends : List Type
        , members : List MemberDecl
        }


type alias ArgDecl = 
    { modifiers : List Mod
    , tpe : Type
    , name : Name
    , defaultValue : Maybe Value
    }


type alias ArgValue =
    { name : Maybe Name
    , value : Value
    }    


type MemberDecl
    = TypeAlias 
        { alias : Name 
        , typeArgs : (List Type) 
        , tpe : Type
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


type Type
    = TypeVar Name
    | TypeRef Path Name
    | TypeApply Type (List Type)
    | TupleType (List Type)
    | StructuralType (List MemberDecl)
    | FunctionType Type Type
    | CommentedType Type String


type Value
    = Literal Lit
    | Var Name
    | Ref Path Name
    | Select Value Name
    | Wildcard
    | Apply Value (List ArgValue)
    | UnOp String Value
    | BinOp Value String Value
    | Lambda (List Name) Value
    | LetBlock (List ( Pattern, Value )) Value
    | MatchCases (List ( Pattern, Value )) 
    | Match Value Value
    | IfElse Value Value Value
    | Tuple (List Value)
    | CommentedValue Value String


type Pattern
    = WildcardMatch
    | AliasMatch Name
    | LiteralMatch Lit
    | UnapplyMatch Path Name (List Pattern)
    | TupleMatch (List Pattern)
    | ListItemsMatch (List Pattern)
    | HeadTailMatch Pattern Pattern
    | CommentedPattern Pattern String


type Lit
    = BooleanLit Bool
    | CharacterLit Char
    | StringLit String
    | IntegerLit Int
    | FloatLit Float

nameOfTypeDecl : TypeDecl -> Name
nameOfTypeDecl typeDecl =
    case typeDecl of
        Trait data -> data.name
        Class data -> data.name
        Object data -> data.name

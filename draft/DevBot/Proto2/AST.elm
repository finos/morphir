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


module SlateX.DevBot.Proto2.AST exposing (..)


type alias ProtoFile =
    { decls : List Decl 
    }


type Decl
    = Message MessageDecl
    | Enum EnumDecl


type alias MessageDecl =
    { name : String
    , members : List MemberDecl
    }


type MemberDecl 
    = Field FieldDecl
    | OneOf OneOfDecl


type alias FieldDecl =
    { rule : FieldRule
    , tpe : FieldType 
    , name : String
    , number : Int
    , comment : Maybe String
    }


type FieldRule
    = Required
    | Optional
    | Repeated


type FieldType
    = TypeRef String
    | Double
    | Float
    | Int32
    | Int64
    | Bool
    | String
    | Bytes


type alias OneOfDecl =
    { name : String
    , fields : List OneOfFieldDecl
    }


type alias OneOfFieldDecl =
    { tpe : FieldType 
    , name : String
    , number : Int
    }


type alias EnumDecl =
    { name : String
    , values : List ( String, Int )
    }

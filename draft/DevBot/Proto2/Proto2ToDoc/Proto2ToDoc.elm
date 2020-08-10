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


module SlateX.DevBot.Proto2.Proto2ToDoc.Proto2ToDoc exposing (..)


import SlateX.DevBot.Source exposing (..)
import SlateX.DevBot.Proto2.AST exposing (..)


type alias Options =
    { indentDepth : Int
    , maxWidth : Int
    }


mapProtoFile : Options -> ProtoFile -> String
mapProtoFile opt protoFile =
    protoFile.decls
        |> List.map (mapDecl opt)
        |> List.intersperse newLine
        |> String.join newLine


mapDecl : Options -> Decl -> String
mapDecl opt decl =
    case decl of
        Message d ->
            mapMessage opt d

        Enum d ->
            mapEnum opt d


mapMessage : Options -> MessageDecl -> String
mapMessage opt messageDecl =
    "message " ++ messageDecl.name ++ " {" ++ newLine ++
        indentLines opt.indentDepth
            (messageDecl.members
                |> List.map mapMemberDecl
            ) ++ newLine ++ "}"    


mapEnum : Options -> EnumDecl -> String
mapEnum opt enumDecl =
    "enum " ++ enumDecl.name ++ " {" ++ newLine ++
        indentLines opt.indentDepth
            (enumDecl.values
                |> List.map 
                    (\( name, number ) ->
                        name ++ " = " ++ String.fromInt number ++ semi
                    )
            ) ++ newLine ++ "}"    


mapMemberDecl : MemberDecl -> String
mapMemberDecl memberDecl =
    case memberDecl of
        Field decl ->
            mapFieldDecl decl

        OneOf decl ->
            empty    


mapFieldDecl : FieldDecl -> String
mapFieldDecl fieldDecl =
    mapFieldRule fieldDecl.rule ++ space ++ mapFieldType fieldDecl.tpe ++ space ++ fieldDecl.name ++ " = " ++ String.fromInt fieldDecl.number ++ semi


mapFieldRule : FieldRule -> String
mapFieldRule rule =
    case rule of
        Required ->
            "required"

        Optional ->
            "optional"

        Repeated ->
            "repeated"


mapFieldType : FieldType -> String
mapFieldType fieldType =
    case fieldType of
        TypeRef ref ->
            ref

        Double ->
            "double"

        Float ->
            "float"

        Int32 ->
            "int32"

        Int64 ->
            "int64"

        Bool ->
            "bool"

        String ->
            "string"

        Bytes ->
            "bytes"



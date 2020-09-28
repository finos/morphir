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


module Morphir.SDK.Annotations exposing (..)

import Morphir.File.SourceCode exposing (newLine)
import Morphir.Scala.AST as Scala exposing (Annotated, TypeDecl)


type Annotations
    = Jackson


getAnnotations : Maybe Annotations -> List Scala.Name -> TypeDecl -> Annotated TypeDecl
getAnnotations annotations names memberTypeDecl =
    case ( annotations, memberTypeDecl ) of
        ( Just Jackson, Scala.Trait _ ) ->
            Annotated
                (Just
                    [ "@com.fasterxml.jackson.annotation.JsonTypeInfo(use = com.fasterxml.jackson.annotation.JsonTypeInfo.Id.NAME,"
                        ++ newLine
                        ++ "include = com.fasterxml.jackson.annotation.JsonTypeInfo.As.PROPERTY, property = \"type\")"
                        ++ newLine
                        ++ "@com.fasterxml.jackson.annotation.JsonSubTypes(Array"
                        ++ newLine
                        ++ "("
                        ++ newLine
                        ++ (names
                                |> List.map
                                    (\name ->
                                        "new com.fasterxml.jackson.annotation.JsonSubTypes.Type(value = classOf["
                                            ++ name
                                            ++ "], name = \""
                                            ++ name
                                            ++ "\"),"
                                            ++ newLine
                                    )
                                |> String.concat
                           )
                        ++ "))"
                    ]
                )
                memberTypeDecl

        ( Just Jackson, Scala.Class _ ) ->
            Annotated (Just [ "@org.springframework.context.annotation.Bean" ]) memberTypeDecl

        _ ->
            Annotated Nothing memberTypeDecl


caseClassesToAnnotate : Maybe Annotations -> List TypeDecl -> List Scala.Name
caseClassesToAnnotate annotations types =
    case annotations of
        Just Jackson ->
            List.filterMap
                (\member ->
                    case member of
                        Scala.Class a ->
                            Just a.name

                        _ ->
                            Nothing
                )
                types

        _ ->
            []

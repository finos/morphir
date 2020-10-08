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


module Morphir.SpringBoot.PrettyPrinter exposing (..)

import Morphir.File.SourceCode exposing (Doc, concat, dot, dotSep, empty, indent, indentLines, newLine, parens, space)
import Morphir.Scala.AST exposing (Documented, TypeDecl(..))
import Morphir.Scala.PrettyPrinter exposing (mapTypeDecl)
import Morphir.SpringBoot.AST exposing (..)

type alias Options =
    { indentDepth : Int
    , maxWidth : Int
    }


mapDocumented : (a -> Doc) -> Documented (Annotated a) -> Doc
mapDocumented valueToDoc documented =
    (case documented.doc  of
        (Just doc) ->
            concat
                [ concat [ "/** ", doc, newLine ]
                , concat [ "*/", newLine ]
                ]
        Nothing ->
            ""
    ) ++
    (case documented.value.annotation of
         Just value ->
            concat
                [ dotSep value ++ newLine
                , valueToDoc documented.value.value ++ newLine

                ]
         Nothing ->
            valueToDoc documented.value.value
    )



mapCompilationUnit : Options -> CompilationUnit -> Doc
mapCompilationUnit opt cu =
    concat
        [ concat [ "package ", dotSep cu.packageDecl, newLine ]
        , newLine
        , cu.typeDecls
            |> List.map (mapDocumented (mapTypeDecl opt))
            |> String.join (newLine ++ newLine)
        ]



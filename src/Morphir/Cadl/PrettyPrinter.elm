module Morphir.Cadl.PrettyPrinter exposing (..)

import Dict
import Morphir.Cadl.AST exposing (Name, Namespace)
import Morphir.File.SourceCode exposing (Doc, concat, newLine, semi, space)


mapNamespace : Namespace -> Doc
mapNamespace namespace =
    let
        printNamespace : Name -> Doc
        printNamespace namespaceName =
            "namespace"
                ++ space
                ++ namespaceName
                ++ semi
                ++ newLine
                ++ newLine
    in
    namespace
        |> Dict.toList
        |> List.map (\( name, _ ) -> printNamespace name)
        |> concat

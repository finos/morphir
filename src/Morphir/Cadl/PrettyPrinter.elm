module Morphir.Cadl.PrettyPrinter exposing (..)

import Dict
import Morphir.Cadl.AST as AST exposing (Name, NamespaceDeclaration)
import Morphir.File.SourceCode exposing (Doc, concat, empty, indent, newLine, semi, space)


mapNamespace : Name -> NamespaceDeclaration -> Doc
mapNamespace namespaceName namespace =
    let
        namespaceContent : Doc
        namespaceContent =
            indent 3
                (namespace
                    |> Dict.toList
                    |> List.map
                        (\( tpeName, tpeDef ) ->
                            tpeDef
                                |> mapTypeDefinition tpeName
                        )
                    |> List.intersperse (newLine ++ newLine)
                    |> concat
                )
    in
    "namespace"
        ++ space
        ++ namespaceName
        ++ space
        ++ "{"
        ++ newLine
        ++ namespaceContent
        ++ newLine
        ++ "}"


mapTypeDefinition : Name -> AST.TypeDefinition -> Doc
mapTypeDefinition nm typeDefinition =
    let
        printTemplateArgs : List Name -> Doc
        printTemplateArgs templates =
            if templates |> List.isEmpty then
                empty

            else
                "<"
                    ++ (templates
                            |> List.intersperse ","
                            |> concat
                       )
                    ++ ">"
    in
    case typeDefinition of
        AST.Alias name lstOfNames tpe ->
            "alias" ++ space ++ name ++ printTemplateArgs lstOfNames ++ " = " ++ mapType tpe ++ semi

        AST.Model name namespace fields ->
            ""


mapType : AST.Type -> String
mapType tpe =
    case tpe of
        AST.Boolean ->
            "boolean"

        AST.String ->
            "string"

        AST.Integer ->
            "integer"

        AST.Float ->
            "float"

        AST.PlainDate ->
            "plainDate"

        AST.PlainTime ->
            "plainTime"

        AST.Array arrayType ->
            case arrayType of
                AST.ListType typ ->
                    "Array<" ++ mapType typ ++ ">"

                AST.TupleType types ->
                    "["
                        ++ (types
                                |> List.map mapType
                                |> List.intersperse ","
                                |> String.concat
                           )
                        ++ "]"

        AST.Reference templates namespace name ->
            "reference"

        AST.Null ->
            "null"

        AST.Variable name ->
            name

        AST.Union types ->
            types
                |> List.map mapType
                |> List.intersperse "|"
                |> concat

        AST.Const string ->
            [ "\"", string, "\"" ]
                |> concat


mapFields : List AST.Field -> Doc
mapFields fields =
    Debug.todo ""

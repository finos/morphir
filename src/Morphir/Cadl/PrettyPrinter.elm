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
    [ "namespace"
    , space
    , namespaceName
    , space
    , "{"
    , newLine
    , namespaceContent
    , newLine
    , "}"
    ]
        |> concat


mapTypeDefinition : Name -> AST.TypeDefinition -> Doc
mapTypeDefinition name typeDefinition =
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
        AST.Alias templateArgs tpe ->
            [ "alias"
            , space
            , name
            , printTemplateArgs templateArgs
            , space
            , "="
            , space
            , mapType tpe
            , semi
            ]
                |> concat

        AST.Model templateArgs fields ->
            [ "model"
            , space
            , name
            , printTemplateArgs templateArgs
            , space
            , "{"
            , newLine
            , indent 3 (mapField fields)
            , newLine
            , "}"
            , semi
            ]
                |> concat

        AST.Enum enumValues ->
            let
                mapEnumValues =
                    enumValues
                        |> List.intersperse (space ++ "," ++ newLine)
                        |> concat
            in
            [ "enum"
            , space
            , name
            , space
            , "{"
            , newLine
            , indent 3 mapEnumValues
            , newLine
            , "}"
            , semi
            ]
                |> concat


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

        AST.Reference _ namespace name ->
            name
                :: List.drop 1 namespace
                |> List.reverse
                |> List.intersperse "."
                |> concat

        AST.Null ->
            "null"

        AST.Variable name ->
            name

        AST.Union types ->
            types
                |> List.map mapType
                |> List.intersperse " | "
                |> concat

        AST.Const string ->
            [ "\"", string, "\"" ]
                |> concat

        AST.Object fields ->
            mapField fields


mapField : AST.Fields -> Doc
mapField fields =
    let
        mapFieldDef : AST.FieldDef -> Doc
        mapFieldDef fieldDef =
            mapType fieldDef.tpe
                |> (\typeSoFar ->
                        if fieldDef.optional == True then
                            [ space, "?:", space, typeSoFar, semi ]

                        else
                            [ space, ":", space, typeSoFar, semi ]
                   )
                |> concat
    in
    fields
        |> Dict.toList
        |> List.map
            (\( fieldName, fieldDef ) ->
                [ fieldName, mapFieldDef fieldDef, newLine ]
            )
        |> List.concat
        |> concat

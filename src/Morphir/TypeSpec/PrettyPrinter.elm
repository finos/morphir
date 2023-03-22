module Morphir.TypeSpec.PrettyPrinter exposing (..)

import Dict exposing (Dict)
import Morphir.File.SourceCode exposing (Doc, concat, empty, indent, newLine, semi, space)
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.TypeSpec.AST as AST exposing (ImportDeclaration(..), Name, Namespace, NamespaceDeclaration, ScalarType)


prettyPrint : PackageName -> List ImportDeclaration -> Dict Namespace NamespaceDeclaration -> Doc
prettyPrint packageName imports namespaces =
    let
        importsDoc : List Doc
        importsDoc =
            imports
                |> List.map mapImports

        namespacesDoc : List Doc
        namespacesDoc =
            namespaces
                |> Dict.toList
                |> List.map
                    (\( namespaceName, namespace ) ->
                        namespace
                            |> mapNamespace packageName namespaceName
                    )
    in
    importsDoc
        ++ namespacesDoc
        |> concat


mapImports : ImportDeclaration -> Doc
mapImports importDecl =
    case importDecl of
        LibraryImport morphirTypeSpecLibrary ->
            [ "import"
            , space
            , "\""
            , morphirTypeSpecLibrary
            , "\""
            , semi
            , newLine
            ]
                |> concat

        FileImport filePath ->
            [ "import"
            , space
            , "\""
            , filePath
            , "\""
            , semi
            , newLine
            ]
                |> concat


mapNamespace : PackageName -> Namespace -> NamespaceDeclaration -> Doc
mapNamespace pckgName namespaceName namespace =
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
    , pckgName |> Path.toString Name.toTitleCase "."
    , "."
    , namespaceName |> String.join "."
    , space
    , "{"
    , newLine
    , namespaceContent
    , newLine
    , "}"
    , newLine
    , newLine
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

        AST.ScalarDefinition typ ->
            [ "scalar"
            , space
            , name
            , space
            , "extends"
            , space
            , mapType typ
            , semi
            ]
                |> concat


mapScalarType : ScalarType -> Doc
mapScalarType tpe =
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

        AST.Null ->
            "null"


mapType : AST.Type -> Doc
mapType tpe =
    case tpe of
        AST.Scalar scalarTyp ->
            mapScalarType scalarTyp

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
                |> List.singleton
                |> List.append namespace
                |> List.intersperse "."
                |> concat

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

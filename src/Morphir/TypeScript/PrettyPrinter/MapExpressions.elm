module Morphir.TypeScript.PrettyPrinter.MapExpressions exposing (Options, mapGenericVariables, mapObjectExp, mapTypeExp, namespaceNameFromPackageAndModule)

import Morphir.File.SourceCode exposing (Doc, concat, indentLines, newLine)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.TypeScript.AST exposing (ObjectExp, Privacy(..), TypeDef(..), TypeExp(..))


{-| Formatting options.
-}
type alias Options =
    { indentDepth : Int
    }


mapGenericVariables : Options -> List TypeExp -> String
mapGenericVariables opt variables =
    case List.length variables of
        0 ->
            ""

        _ ->
            concat
                [ "<"
                , String.join ", " (variables |> List.map (mapTypeExp opt))
                , ">"
                ]


{-| Map an object expression or interface definiton to text
-}
mapObjectExp : Options -> ObjectExp -> Doc
mapObjectExp opt objectExp =
    let
        mapField : ( String, TypeExp ) -> Doc
        mapField ( fieldName, fieldType ) =
            concat [ fieldName, ": ", mapTypeExp opt fieldType, ";" ]
    in
    concat
        [ "{"
        , newLine
        , objectExp
            |> List.map mapField
            |> indentLines opt.indentDepth
        , newLine
        , "}"
        ]


{-| Map a type expression to text.
-}
mapTypeExp : Options -> TypeExp -> Doc
mapTypeExp opt typeExp =
    case typeExp of
        Any ->
            "any"

        Boolean ->
            "boolean"

        List listType ->
            "Array<" ++ mapTypeExp opt listType ++ ">"

        LiteralString stringval ->
            "\"" ++ stringval ++ "\""

        Number ->
            "number"

        Object fieldList ->
            mapObjectExp opt fieldList

        String ->
            "string"

        Tuple tupleTypesList ->
            concat
                [ "["
                , tupleTypesList
                    |> List.map (mapTypeExp opt)
                    |> String.join ", "
                , "]"
                ]

        TypeRef fQName variables ->
            let
                processed_name : String
                processed_name =
                    case fQName of
                        ( [], [], localName ) ->
                            concat
                                [ localName |> Name.toTitleCase
                                ]

                        ( packagePath, modulePath, localName ) ->
                            concat
                                [ namespaceNameFromPackageAndModule packagePath modulePath
                                , "."
                                , localName |> Name.toTitleCase
                                ]
            in
            concat
                [ processed_name
                , mapGenericVariables opt variables
                ]

        Union types ->
            types |> List.map (mapTypeExp opt) |> String.join " | "

        Variable name ->
            name

        UnhandledType tpe ->
            concat
                [ "any"
                , " /* Unhandled type: "
                , tpe
                , " */"
                ]


namespaceNameFromPackageAndModule : Path -> Path -> String
namespaceNameFromPackageAndModule packagePath modulePath =
    (packagePath ++ modulePath)
        |> List.map Name.toTitleCase
        |> String.join "_"

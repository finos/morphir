module Morphir.TypeScript.PrettyPrinter.Expressions exposing (..)

import Morphir.File.SourceCode exposing (Doc, concat, indentLines, newLine)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.TypeScript.AST exposing (ObjectExp, Parameter, Privacy(..), TypeDef(..), TypeExp(..), namespaceNameFromPackageAndModule)


defaultIndent =
    2


mapGenericVariables : List TypeExp -> String
mapGenericVariables variables =
    case List.length variables of
        0 ->
            ""

        _ ->
            concat
                [ "<"
                , String.join ", " (variables |> List.map mapTypeExp)
                , ">"
                ]


mapParameter : Parameter -> String
mapParameter { modifiers, name, typeAnnotation } =
    concat
        [ modifiers |> String.join " "
        , " "
        , name
        , mapMaybeAnnotation typeAnnotation
        ]


mapMaybeAnnotation : Maybe TypeExp -> String
mapMaybeAnnotation maybeTypeExp =
    case maybeTypeExp of
        Nothing ->
            ""

        Just typeExp ->
            ": " ++ mapTypeExp typeExp


{-| Map a field to text (from an object or interface)
-}
mapField : ( String, TypeExp ) -> Doc
mapField ( fieldName, fieldType ) =
    concat [ fieldName, ": ", mapTypeExp fieldType, ";" ]


{-| Map an object expression or interface definiton to text
-}
mapObjectExp : ObjectExp -> Doc
mapObjectExp objectExp =
    concat
        [ "{"
        , newLine
        , objectExp
            |> List.map mapField
            |> indentLines defaultIndent
        , newLine
        , "}"
        ]


{-| Map a type expression to text.
-}
mapTypeExp : TypeExp -> Doc
mapTypeExp typeExp =
    case typeExp of
        Any ->
            "any"

        Boolean ->
            "boolean"

        FunctionTypeExp params rtnTypeExp ->
            concat
                [ "("
                , params |> List.map mapParameter |> String.join ", "
                , ") => "
                , mapTypeExp rtnTypeExp
                ]

        List listType ->
            "Array<" ++ mapTypeExp listType ++ ">"

        LiteralString stringval ->
            "\"" ++ stringval ++ "\""

        Map keyType valueType ->
            concat
                [ "Map"
                , "<"
                , mapTypeExp keyType
                , ", "
                , mapTypeExp valueType
                , ">"
                ]

        Number ->
            "number"

        Object fieldList ->
            mapObjectExp fieldList

        String ->
            "string"

        Tuple tupleTypesList ->
            concat
                [ "["
                , tupleTypesList
                    |> List.map mapTypeExp
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
                , mapGenericVariables variables
                ]

        Union types ->
            types |> List.map mapTypeExp |> String.join " | "

        Variable name ->
            name

        UnhandledType tpe ->
            concat
                [ "any"
                , " /* Unhandled type: "
                , tpe
                , " */"
                ]

        Nullable tpe ->
            concat [ mapTypeExp tpe, " | null" ]


namespaceNameFromPackageAndModule : Path -> Path -> String
namespaceNameFromPackageAndModule packagePath modulePath =
    (packagePath ++ modulePath)
        |> List.map Name.toTitleCase
        |> String.join "_"

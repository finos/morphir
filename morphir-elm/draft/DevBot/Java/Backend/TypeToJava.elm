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


module SlateX.DevBot.Java.Backend.TypeToJava exposing (..)



import Dict
import SlateX.AST.Path exposing (Path)
import SlateX.AST.QName exposing (QName)
import SlateX.AST.Type as Type
import SlateX.AST.Package.Annotated as AnnotatedPackage
import SlateX.Mapping.Naming as Naming
import SlateX.DevBot.Java.Ast as Java


tupleToType : AnnotatedPackage.Package Type.Exp -> Path -> List Type.Exp -> Java.Type
tupleToType lib currentModulePath elems =
    case elems of
        [] ->
            Java.Void

        [ single ] ->
            typeExpToType lib currentModulePath single

        head :: tail ->
            Java.TypeConst [ "java", "util", "Map", "Entry" ]
                [ (typeExpToType lib currentModulePath head)
                , (tupleToType lib currentModulePath tail)
                ]


typeExpToType : AnnotatedPackage.Package Type.Exp -> Path -> Type.Exp -> Java.Type
typeExpToType lib currentModulePath typeExp =
    case typeExp of
        Type.Constructor ref args ->
            Java.TypeConst (typeRefToJavaQName lib currentModulePath ref)
                (args |> List.map (typeExpToType lib currentModulePath))

        Type.Tuple elems ->
            tupleToType lib currentModulePath elems

        Type.Function argType (Type.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "basics" ] ], [ "bool" ] ) []) ->
            Java.Predicate (typeExpToType lib currentModulePath argType)

        Type.Function argType returnType ->
            Java.Function (typeExpToType lib currentModulePath argType) (typeExpToType lib currentModulePath returnType)

        Type.Variable name ->
            Java.TypeVar (name |> Naming.toTitleCase)        

        _ ->
            Debug.todo "TODO"


typeRefToJavaQName : AnnotatedPackage.Package Type.Exp -> Path -> QName -> Java.QualifiedIdentifier
typeRefToJavaQName lib currentModulePath ref =
    let
        userDefinedType modulePath localName =
            case ( List.reverse modulePath, localName ) of
                ( moduleName :: modulePathReversed, _ ) ->
                    let
                        maybeUnionTypeName =
                            lib.implementation
                                |> Dict.get modulePath
                                |> Maybe.andThen
                                    (\moduleDef ->
                                        moduleDef.unionTypes
                                            |> Dict.toList
                                            |> List.filterMap
                                                (\( unionTypeName, typeDecl ) ->
                                                    let
                                                        matchingCaseFound =
                                                            typeDecl.cases
                                                                |> List.any
                                                                    (\( constructorName, args ) ->
                                                                        constructorName == localName
                                                                        && List.isEmpty args
                                                                    )

                                                    in
                                                        if matchingCaseFound then
                                                            Just unionTypeName
                                                        else
                                                            Nothing
                                                )
                                            |> List.head
                                    )

                    in
                        case maybeUnionTypeName of
                            Just unionTypeName ->
                                (pathToPackageName modulePath) ++ [ Naming.toTitleCase unionTypeName, localName |> Naming.toSnakeCase |> String.toUpper ]

                            Nothing ->
                                (pathToPackageName modulePath) ++ [ Naming.toTitleCase localName ]

                _ ->
                    Debug.todo "TODO"

    in
    case ref of
        ( modulePath, localName ) ->
            case modulePath of
                [ [ "slate", "x" ], [ "core" ], [ "basics" ] ] ->
                    case localName of
                        [ "bool" ] ->
                            [ "boolean" ]

                        [ "int" ] ->
                            [ "java", "math", "BigInteger" ]

                        [ "int", "8" ] ->
                            [ "byte" ]

                        [ "int", "16" ] ->
                            [ "short" ]

                        [ "int", "32" ] ->
                            [ "int" ]

                        [ "int", "64" ] ->
                            [ "long" ]

                        [ "float" ] ->
                            [ "float" ]

                        [ "float", "32" ] ->
                            [ "float" ]

                        [ "float", "64" ] ->
                            [ "double" ]

                        [ "decimal" ] ->
                            [ "java", "math", "BigDecimal" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "char" ] ] ->
                    case localName of
                        [ "char" ] ->
                            [ "char" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "string" ] ] ->
                    case localName of
                        [ "string" ] ->
                            [ "String" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "list" ] ] ->
                    case localName of
                        [ "list" ] ->
                            [ "java", "util", "stream", "Stream" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "dict" ] ] ->
                    case localName of
                        [ "dict" ] ->
                            [ "java", "util", "Map" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "maybe" ] ] ->
                    case localName of
                        [ "maybe" ] ->
                            [ "java", "util", "Optional" ]

                        [ "just" ] ->
                            [ "java", "util", "Optional", "of" ]

                        _ ->
                            userDefinedType modulePath localName

                [ [ "slate", "x" ], [ "core" ], [ "local", "date" ] ] ->
                    case localName of
                        [ "local", "date" ] ->
                            [ "java", "time", "LocalDate" ]

                        _ ->
                            userDefinedType modulePath localName

                _ ->
                    userDefinedType modulePath localName


pathToPackageName : Path -> Java.QualifiedIdentifier
pathToPackageName path =
    path |> List.map (String.join "")


isPrimitive : Type.Exp -> Bool
isPrimitive tpe =
    case tpe of
        Type.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "basics" ] ], typeName ) [] ->
            List.member typeName [ [ "bool" ], [ "int", "8" ], [ "int", "16" ], [ "int", "32" ], [ "int", "64" ], [ "float" ], [ "float", "32" ], [ "float", "64" ], [ "char" ] ]

        _ ->
            False    


primitiveToWrapper : Type.Exp -> Maybe Java.QualifiedIdentifier
primitiveToWrapper tpe =
    case tpe of
        Type.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "basics" ] ], typeName ) [] ->
            case typeName of
                [ "bool" ] ->
                    Just [ "java", "lang", "Boolean" ]

                [ "int", "8" ] ->
                    Just [ "java", "lang", "Byte" ]

                [ "int", "16" ] ->
                    Just [ "java", "lang", "Short" ]

                [ "int", "32" ] ->
                    Just [ "java", "lang", "Integer" ]

                [ "int", "64" ] ->
                    Just [ "java", "lang", "Long" ]

                [ "float" ] ->
                    Just [ "java", "lang", "Float" ]

                [ "float", "32" ] ->
                    Just [ "java", "lang", "Float" ]

                [ "float", "64" ] ->
                    Just [ "java", "lang", "Double" ]

                [ "char" ] ->
                    Just [ "java", "lang", "Char" ]

                _ ->
                    Nothing

        _ ->
            Nothing    

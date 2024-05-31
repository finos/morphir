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


module SlateX.DevBot.Java.Backend exposing (equalsMethod, hashCodeMethod, isEnum, isEnumType, isEnumTypeName, membersForFields, methodsForFields, moduleToCompilationUnits, nameToTypeIdentifier, packageToCompilationUnits, packageToFiles, toStringMethod, typeAliasToCompilationUnits, typeExpToArgAndReturnTypes, unionTypeToCompilationUnits, valuesToCompilationUnits, zipArgNamesWithTypes)

import Dict exposing (Dict)
import Set
import SlateX.AST.Module.Annotated as AnnotatedModule
import SlateX.AST.Name as Name exposing (Name)
import SlateX.AST.Package.Annotated as AnnotatedPackage
import SlateX.AST.Path exposing (Path)
import SlateX.AST.QName exposing (QName)
import SlateX.AST.Type as Type
import SlateX.AST.Type.Collect as TypeCollect exposing (collector)
import SlateX.AST.Value.Annotated as A
import SlateX.DevBot.Java.Ast as Java
import SlateX.DevBot.Java.Backend.TypeToJava as TypeToJava
import SlateX.DevBot.Java.Backend.ValueToJava as ValueToJava
import SlateX.DevBot.Java.Imports as Imports
import SlateX.DevBot.Java.Options exposing (Options)
import SlateX.DevBot.Java.ToDoc as ToDoc
import SlateX.Mapping.Naming as Naming


packageToFiles : AnnotatedPackage.Package Type.Exp -> Options -> List ( Path, String, String )
packageToFiles package opt =
    packageToCompilationUnits package
        |> List.map
            (\( modulePath, cu ) ->
                let
                    sourceCode =
                        cu
                            |> ToDoc.compilationUnitToDoc opt

                    filePath =
                        (cu.filePath ++ [ cu.fileName ++ ".java" ])
                            |> String.join "/"
                in
                ( modulePath, filePath, sourceCode )
            )


packageToCompilationUnits : AnnotatedPackage.Package Type.Exp -> List ( Path, Java.CompilationUnit )
packageToCompilationUnits package =
    package.implementation
        |> Dict.toList
        |> List.concatMap
            (\( path, moduleDef ) ->
                moduleToCompilationUnits package path moduleDef
                    |> List.map Imports.generate
                    |> List.map
                        (\cu ->
                            ( path, cu )
                        )
            )


moduleToCompilationUnits : AnnotatedPackage.Package Type.Exp -> Path -> AnnotatedModule.Implementation Type.Exp -> List Java.CompilationUnit
moduleToCompilationUnits lib modulePath moduleDef =
    [ moduleDef.typeAliases
        |> Dict.toList
        |> List.concatMap
            (\( name, unionType ) ->
                typeAliasToCompilationUnits lib modulePath moduleDef name unionType
            )
    , moduleDef.unionTypes
        |> Dict.toList
        |> List.concatMap
            (\( name, unionType ) ->
                unionTypeToCompilationUnits lib modulePath moduleDef name unionType
            )
    , valuesToCompilationUnits lib modulePath moduleDef
    ]
        |> List.concat


typeAliasToCompilationUnits : AnnotatedPackage.Package Type.Exp -> Path -> AnnotatedModule.Implementation Type.Exp -> Name -> Type.TypeAliasDeclaration -> List Java.CompilationUnit
typeAliasToCompilationUnits lib currentModulePath moduleDef typeName typeDef =
    case typeDef.exp of
        Type.Record fields ->
            let
                interface =
                    Java.CompilationUnit
                        (TypeToJava.pathToPackageName currentModulePath)
                        (nameToTypeIdentifier typeName)
                        (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName currentModulePath)))
                        []
                        -- no imports
                        [ Java.Interface
                            { modifiers = [ Java.Public ]
                            , name = nameToTypeIdentifier typeName
                            , typeParams = []
                            , extends = []
                            , members = methodsForFields lib currentModulePath fields
                            }
                        ]

                functionFields =
                    fields
                        |> List.filter
                            (\( fieldName, fieldType ) ->
                                case fieldType of
                                    Type.Function _ _ ->
                                        True

                                    _ ->
                                        False
                            )
            in
            if functionFields |> List.isEmpty then
                [ interface
                , Java.CompilationUnit
                    (TypeToJava.pathToPackageName currentModulePath)
                    (nameToTypeIdentifier (typeName ++ [ "value" ]))
                    (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName currentModulePath)))
                    []
                    -- no imports
                    [ Java.Class
                        { modifiers = [ Java.Public ]
                        , name = nameToTypeIdentifier (typeName ++ [ "value" ])
                        , typeParams = []
                        , extends = Nothing
                        , implements =
                            [ Java.TypeRef (TypeToJava.typeRefToJavaQName lib currentModulePath ( currentModulePath, typeName ))
                            , Java.TypeRef [ "java", "io", "Serializable" ]
                            ]
                        , members =
                            membersForFields lib currentModulePath typeName fields
                        }
                    ]
                ]

            else
                [ interface ]

        Type.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "native" ] ], [ "native" ] ) _ ->
            []

        Type.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "annotation" ] ], [ "undefined" ] ) _ ->
            []

        _ ->
            []


unionTypeToCompilationUnits : AnnotatedPackage.Package Type.Exp -> Path -> AnnotatedModule.Implementation Type.Exp -> Name -> Type.UnionTypeDeclaration -> List Java.CompilationUnit
unionTypeToCompilationUnits lib currentModulePath moduleDef typeName typeDef =
    if isEnum typeDef then
        [ Java.CompilationUnit
            (TypeToJava.pathToPackageName currentModulePath)
            (nameToTypeIdentifier typeName)
            (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName currentModulePath)))
            []
            -- no imports
            [ Java.Enum
                { modifiers = [ Java.Public ]
                , name = nameToTypeIdentifier typeName
                , implements = []
                , values =
                    typeDef.cases
                        |> List.map
                            (\( name, _ ) ->
                                name |> Naming.toSnakeCase |> String.toUpper
                            )
                }
            ]
        ]

    else
        let
            typeInterface =
                Java.CompilationUnit
                    (TypeToJava.pathToPackageName currentModulePath)
                    (nameToTypeIdentifier typeName)
                    (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName currentModulePath)))
                    []
                    -- no imports
                    [ Java.Interface
                        { modifiers = [ Java.Public ]
                        , name = nameToTypeIdentifier typeName
                        , typeParams = []
                        , extends = []
                        , members = []
                        }
                    ]

            caseClass name args =
                let
                    argNamesAndTypes =
                        let
                            maybeNamedArgs =
                                moduleDef.values
                                    |> Dict.get name
                                    |> Maybe.map (zipArgNamesWithTypes args)
                        in
                        maybeNamedArgs
                            |> Maybe.withDefault
                                (args
                                    |> List.indexedMap
                                        (\index argType ->
                                            ( [ "arg" ++ Debug.toString index ], argType )
                                        )
                                )
                in
                Java.CompilationUnit
                    (TypeToJava.pathToPackageName currentModulePath)
                    (nameToTypeIdentifier name)
                    (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName currentModulePath)))
                    []
                    -- no imports
                    [ Java.Class
                        { modifiers = [ Java.Public ]
                        , name = nameToTypeIdentifier name
                        , typeParams = []
                        , extends = Nothing
                        , implements =
                            if List.length typeDef.cases > 1 then
                                [ Java.TypeRef (TypeToJava.pathToPackageName currentModulePath ++ [ nameToTypeIdentifier typeName ])
                                , Java.TypeRef [ "java", "io", "Serializable" ]
                                ]

                            else
                                []
                        , members =
                            membersForFields lib currentModulePath typeName argNamesAndTypes
                        }
                    ]

            caseClasses =
                typeDef.cases
                    |> List.map
                        (\( name, args ) ->
                            caseClass name args
                        )
        in
        if List.length typeDef.cases > 1 then
            typeInterface :: caseClasses

        else
            caseClasses


valuesToCompilationUnits : AnnotatedPackage.Package Type.Exp -> Path -> AnnotatedModule.Implementation Type.Exp -> List Java.CompilationUnit
valuesToCompilationUnits lib currentModulePath moduleDef =
    if Dict.isEmpty moduleDef.values then
        []

    else
        case List.reverse currentModulePath of
            moduleName :: modulePathReversed ->
                [ Java.CompilationUnit
                    (TypeToJava.pathToPackageName (List.reverse modulePathReversed))
                    (nameToTypeIdentifier moduleName)
                    (Just (Java.PackageDeclaration [] (TypeToJava.pathToPackageName (List.reverse modulePathReversed))))
                    []
                    -- no imports
                    [ Java.Class
                        { modifiers = [ Java.Public ]
                        , name = nameToTypeIdentifier moduleName
                        , typeParams = []
                        , extends = Nothing
                        , implements = []
                        , members =
                            moduleDef.valueTypes
                                |> Dict.toList
                                |> List.map
                                    (\( valueName, tpe ) ->
                                        let
                                            ( argTypes, returnType ) =
                                                typeExpToArgAndReturnTypes tpe

                                            maybeNamedArgs =
                                                moduleDef.values
                                                    |> Dict.get valueName
                                                    |> Maybe.map (zipArgNamesWithTypes argTypes)

                                            argNamesAndTypes =
                                                maybeNamedArgs
                                                    |> Maybe.withDefault
                                                        (argTypes
                                                            |> List.indexedMap
                                                                (\index argType ->
                                                                    ( [ "arg" ++ Debug.toString index ], argType )
                                                                )
                                                        )

                                            valueBody value =
                                                case value of
                                                    A.Lambda _ body _ ->
                                                        valueBody body

                                                    _ ->
                                                        value

                                            typeVarCollector =
                                                { collector
                                                    | exp =
                                                        \exp ->
                                                            case exp of
                                                                Type.Variable n ->
                                                                    [ n |> Naming.toTitleCase ]

                                                                _ ->
                                                                    []
                                                }

                                            typeParams =
                                                TypeCollect.collectExp typeVarCollector tpe
                                                    |> Set.fromList
                                                    |> Set.toList
                                        in
                                        Java.Method
                                            { modifiers = [ Java.Public, Java.Static ]
                                            , typeParams = typeParams
                                            , returnType = TypeToJava.typeExpToType lib currentModulePath returnType
                                            , name = Naming.toCamelCase valueName
                                            , args =
                                                argNamesAndTypes
                                                    |> List.map
                                                        (\( argName, argType ) ->
                                                            ( Naming.toCamelCase argName, TypeToJava.typeExpToType lib currentModulePath argType )
                                                        )
                                            , body =
                                                case moduleDef.values |> Dict.get valueName of
                                                    Just value ->
                                                        ValueToJava.valueExpToReturn lib currentModulePath (valueBody value)

                                                    Nothing ->
                                                        []
                                            }
                                    )
                        }
                    ]
                ]

            _ ->
                []


zipArgNamesWithTypes : List Type.Exp -> A.Exp Type.Exp -> List ( Name, Type.Exp )
zipArgNamesWithTypes argTypes value =
    case ( argTypes, value ) of
        ( argType :: restOfArgTypes, A.Lambda (A.MatchAnyAlias argName _) body _ ) ->
            ( argName, argType ) :: zipArgNamesWithTypes restOfArgTypes body

        _ ->
            []


isEnum : Type.UnionTypeDeclaration -> Bool
isEnum unionType =
    unionType.cases
        |> List.all
            (\( _, args ) ->
                List.isEmpty args
            )


typeExpToArgAndReturnTypes : Type.Exp -> ( List Type.Exp, Type.Exp )
typeExpToArgAndReturnTypes tpe =
    case tpe of
        Type.Function argType returnType ->
            let
                ( childArgTypes, childReturnType ) =
                    typeExpToArgAndReturnTypes returnType
            in
            ( argType :: childArgTypes, childReturnType )

        _ ->
            ( [], tpe )


methodsForFields : AnnotatedPackage.Package Type.Exp -> Path -> List ( Name, Type.Exp ) -> List Java.MemberDecl
methodsForFields lib currentModulePath fields =
    [ fields
        |> List.map
            (\( argName, argType ) ->
                case argType of
                    Type.Function _ _ ->
                        let
                            args tpe =
                                case tpe of
                                    Type.Function at rt ->
                                        at :: args rt

                                    other ->
                                        []

                            returnType tpe =
                                case tpe of
                                    Type.Function _ rt ->
                                        returnType rt

                                    other ->
                                        other
                        in
                        Java.Method
                            { modifiers = []
                            , typeParams = []
                            , returnType =
                                returnType argType
                                    |> TypeToJava.typeExpToType lib currentModulePath
                            , name = Naming.toCamelCase argName
                            , args =
                                args argType
                                    |> List.indexedMap
                                        (\index tpe ->
                                            ( "arg" ++ Debug.toString index, TypeToJava.typeExpToType lib currentModulePath tpe )
                                        )
                            , body = []
                            }

                    _ ->
                        Java.Method
                            { modifiers = []
                            , typeParams = []
                            , returnType = TypeToJava.typeExpToType lib currentModulePath argType
                            , name = "get" ++ Naming.toTitleCase argName
                            , args = []
                            , body = []
                            }
            )
    ]
        |> List.concat


membersForFields : AnnotatedPackage.Package Type.Exp -> Path -> Name -> List ( Name, Type.Exp ) -> List Java.MemberDecl
membersForFields lib currentModulePath typeName fields =
    [ fields
        |> List.map
            (\( argName, argType ) ->
                Java.Field
                    { modifiers = [ Java.Private ]
                    , tpe = TypeToJava.typeExpToType lib currentModulePath argType
                    , name = Naming.toCamelCase argName
                    }
            )
    , [ Java.Constructor
            { modifiers = [ Java.Public ]
            , args =
                fields
                    |> List.map
                        (\( argName, argType ) ->
                            ( Naming.toCamelCase argName, TypeToJava.typeExpToType lib currentModulePath argType )
                        )
            , body =
                fields
                    |> List.map
                        (\( argName, argType ) ->
                            Java.Assign
                                (Java.Select Java.This (Naming.toCamelCase argName))
                                (Java.Variable (Naming.toCamelCase argName))
                        )
                    |> Just
            }
      ]
    , fields
        |> List.map
            (\( argName, argType ) ->
                Java.Method
                    { modifiers = [ Java.Public ]
                    , typeParams = []
                    , returnType =
                        TypeToJava.typeExpToType lib currentModulePath argType
                    , name =
                        "get" ++ Naming.toTitleCase argName
                    , args = []
                    , body =
                        [ Java.Return
                            (Java.Select Java.This (Naming.toCamelCase argName))
                        ]
                    }
            )
    , [ equalsMethod typeName fields
      , hashCodeMethod typeName fields
      , toStringMethod typeName fields
      ]
    ]
        |> List.concat


equalsMethod : Name -> List ( Name, Type.Exp ) -> Java.MemberDecl
equalsMethod typeName fields =
    Java.Method
        { modifiers = [ Java.Public ]
        , typeParams = []
        , returnType = Java.TypeRef [ "boolean" ]
        , name = "equals"
        , args =
            [ ( "o", Java.TypeRef [ "java", "lang", "Object" ] )
            ]
        , body =
            let
                classType =
                    Java.TypeRef [ nameToTypeIdentifier (typeName ++ [ "value" ]) ]

                compare fieldName fieldType =
                    ValueToJava.isEqual fieldType
                        (Java.Select Java.This (Naming.toCamelCase fieldName))
                        (Java.Select (Java.Variable "that") (Naming.toCamelCase fieldName))

                comparisons =
                    case fields of
                        [] ->
                            Java.BooleanLit False

                        ( firstName, firstType ) :: rest ->
                            rest
                                |> List.foldl
                                    (\( fieldName, fieldType ) soFar ->
                                        Java.BinOp soFar "&&" (compare fieldName fieldType)
                                    )
                                    (compare firstName firstType)
            in
            [ Java.IfElse
                (Java.BinOp Java.This "==" (Java.Variable "o"))
                [ Java.Return (Java.BooleanLit True)
                ]
                [ Java.IfElse
                    (Java.BinOp
                        (Java.BinOp (Java.Variable "o") "==" Java.Null)
                        "||"
                        (Java.BinOp
                            (Java.Apply (Java.Select Java.This "getClass") [])
                            "!="
                            (Java.Apply (Java.Select (Java.Variable "o") "getClass") [])
                        )
                    )
                    [ Java.Return (Java.BooleanLit False)
                    ]
                    [ Java.VariableDecl [ Java.Final ] classType "that" (Just (Java.Cast classType (Java.Variable "o")))
                    , Java.Return comparisons
                    ]
                ]
            ]
        }


hashCodeMethod : Name -> List ( Name, Type.Exp ) -> Java.MemberDecl
hashCodeMethod typeName fields =
    Java.Method
        { modifiers = [ Java.Public ]
        , typeParams = []
        , returnType = Java.TypeRef [ "int" ]
        , name = "hashCode"
        , args = []
        , body =
            let
                hashOf fieldName fieldType =
                    case TypeToJava.primitiveToWrapper fieldType of
                        Just wrapper ->
                            Java.Apply
                                (Java.Select
                                    (Java.ValueRef wrapper)
                                    "hashCode"
                                )
                                [ Java.Select Java.This (Naming.toCamelCase fieldName)
                                ]

                        Nothing ->
                            Java.Apply
                                (Java.Select
                                    (Java.Select Java.This (Naming.toCamelCase fieldName))
                                    "hashCode"
                                )
                                []

                components =
                    case fields of
                        [] ->
                            [ Java.VariableDecl [] (Java.TypeRef [ "int" ]) "result" (Just (Java.IntLit 0))
                            ]

                        ( firstName, firstType ) :: rest ->
                            rest
                                |> List.map
                                    (\( fieldName, fieldType ) ->
                                        Java.Assign
                                            (Java.Variable "result")
                                            (Java.BinOp
                                                (Java.BinOp
                                                    (Java.IntLit 31)
                                                    "*"
                                                    (Java.Variable "result")
                                                )
                                                "+"
                                                (hashOf fieldName fieldType)
                                            )
                                    )
                                |> (::) (Java.VariableDecl [] (Java.TypeRef [ "int" ]) "result" (Just (hashOf firstName firstType)))
            in
            components ++ [ Java.Return (Java.Variable "result") ]
        }


toStringMethod : Name -> List ( Name, Type.Exp ) -> Java.MemberDecl
toStringMethod typeName fields =
    Java.Method
        { modifiers = [ Java.Public ]
        , typeParams = []
        , returnType = Java.TypeRef [ "java", "lang", "String" ]
        , name = "toString"
        , args = []
        , body =
            let
                typeNameString =
                    nameToTypeIdentifier (typeName ++ [ "value" ])

                stringLit =
                    case fields of
                        [] ->
                            Java.StringLit typeNameString

                        ( firstName, firstType ) :: rest ->
                            let
                                prefix =
                                    Java.StringLit (typeNameString ++ "{")

                                middle =
                                    rest
                                        |> List.foldl
                                            (\( fieldName, fieldType ) soFar ->
                                                Java.BinOp
                                                    soFar
                                                    "+"
                                                    (Java.BinOp
                                                        (Java.StringLit (", " ++ Naming.toCamelCase fieldName ++ "="))
                                                        "+"
                                                        (Java.Variable (Naming.toCamelCase fieldName))
                                                    )
                                            )
                                            (Java.BinOp
                                                (Java.StringLit (Naming.toCamelCase firstName ++ "="))
                                                "+"
                                                (Java.Variable (Naming.toCamelCase firstName))
                                            )

                                suffix =
                                    Java.StringLit "}"
                            in
                            Java.BinOp
                                (Java.BinOp prefix "+" middle)
                                "+"
                                suffix
            in
            [ Java.Return stringLit ]
        }


isEnumType : AnnotatedPackage.Package Type.Exp -> Type.Exp -> Bool
isEnumType package typeExp =
    case typeExp of
        Type.Constructor ( modulePath, typeName ) _ ->
            isEnumTypeName package ( modulePath, typeName )

        _ ->
            False


isEnumTypeName : AnnotatedPackage.Package Type.Exp -> QName -> Bool
isEnumTypeName package ( modulePath, typeName ) =
    package.implementation
        |> Dict.get modulePath
        |> Maybe.andThen
            (\moduleImpl ->
                moduleImpl.unionTypes
                    |> Dict.get typeName
                    |> Maybe.map (\_ -> True)
            )
        |> Maybe.withDefault False


nameToTypeIdentifier : Name -> Java.Identifier
nameToTypeIdentifier name =
    Naming.toTitleCase name

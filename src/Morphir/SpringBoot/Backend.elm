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


module Morphir.SpringBoot.Backend exposing (..)

import Dict
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (dotSep)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Value(..))
import Morphir.SDK.Annotations exposing (Annotations(..), mapCustomTypeDefinition, mapType)
import Morphir.Scala.AST exposing (Annotated, CompilationUnit, Documented, MemberDecl(..), Mod(..), Type(..), TypeDecl(..), ArgDecl)
import Morphir.Scala.Backend exposing (mapValue)
import Morphir.Scala.PrettyPrinter as PrettyPrinter



type alias Options = {}

mapDistribution : Options -> Package.Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Package.Library packagePath packageDef ->
            mapPackageDefinition opt packagePath packageDef


mapPackageDefinition : Options -> Package.PackagePath -> Package.Definition ta tv -> FileMap
mapPackageDefinition opt packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                 (mapStatefulAppDefinition opt packagePath modulePath moduleImpl
                        |> List.map
                            (\compilationUnit ->
                                let
                                    fileContent =
                                        compilationUnit
                                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                                in
                                    ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                            )
                    )
            )
        |> Dict.fromList

mapStatefulAppDefinition : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition ta tv) -> List CompilationUnit
mapStatefulAppDefinition opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
        functionName: Name
        functionName =
            case accessControlledModuleDef.access of
                Public ->
                    case accessControlledModuleDef.value of
                        { types, values } ->
                            case (Dict.get (Name.fromString "app") values) of
                                Just acsCtrlValueDef ->
                                    case acsCtrlValueDef.access of
                                        Public ->
                                            case acsCtrlValueDef.value.body of
                                                Value.Apply _ (Constructor  _ _) (Value.Reference _ (FQName _ _ name)) ->
                                                    name
                                                _ -> []
                                        _ -> []
                                _ -> []
                _ -> []
        _ = Debug.log "functionName" functionName

        statefulAppConsTypes : List Type
        statefulAppConsTypes =
            accessControlledModuleDef.value.values
                |> Dict.toList
                    |> List.concatMap
                        (\( valueName, accessControlledValueDef ) ->
                            case (accessControlledValueDef.value.inputTypes, accessControlledValueDef.value.outputType) of
                                ((stateVariable :: commandVariable :: []) , Type.Tuple _ (stateType :: eventType :: []) ) ->
                                        [mapType eventType]
                                        |> List.append (accessControlledValueDef.value.inputTypes
                                        |> List.map
                                            (\( _, _, argType ) ->
                                                mapType argType
                                            )
                                        |> List.reverse)

                                _ -> []
                        )

        statefulAppDefinition :  List (Documented (Annotated MemberDecl))
        statefulAppDefinition =
            accessControlledModuleDef.value.values
                |> Dict.toList
                    |> List.concatMap
                        (\( valueName, accessControlledValueDef ) ->
                            case (accessControlledValueDef.value.inputTypes, accessControlledValueDef.value.outputType) of
                                ((stateVariable :: commandVariable :: []) , Type.Tuple _ (stateType :: eventType :: []) ) ->
                                    [(Documented (Nothing)
                                       (Annotated (Just ["@org.springframework.web.bind.annotation.RequestMapping(value = Array(\"/" ++ (valueName |> Name.toCamelCase) ++ "\"), method = Array(org.springframework.web.bind.annotation.RequestMethod.GET))"])
                                       <|
                                        (FunctionDecl
                                            { modifiers = []
                                            , name =
                                                (valueName |> Name.toCamelCase)
                                            , typeArgs =
                                                []
                                            , args =
                                                if List.isEmpty accessControlledValueDef.value.inputTypes then
                                                    []
                                                else
                                                    [ accessControlledValueDef.value.inputTypes
                                                        |> List.map
                                                            (\( argName, a, argType ) ->
                                                                { modifiers = []
                                                                , tpe = mapType argType
                                                                , name = argName |> Name.toCamelCase
                                                                , defaultValue = Nothing
                                                                }
                                                            )
                                                    ]
                                            , returnType =
                                                Just (mapType accessControlledValueDef.value.outputType)
                                            , body =
                                               Just (mapValue accessControlledValueDef.value.body)
                                            }
                                         )
                                        )
                                        )]
                                _ ->
                                    []

                        )

        typeMembers : List MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
                                [
                                    MemberTypeDecl
                                    (Class
                                        { modifiers = [ Case ]
                                        , name = typeName |> Name.toTitleCase
                                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> TypeVar)
                                        , ctorArgs =
                                            fields
                                                |> List.map
                                                    (\field ->
                                                        { modifiers = []
                                                        , tpe = mapType field.tpe
                                                        , name = ""
                                                        , defaultValue = Nothing
                                                        }
                                                    )
                                                |> List.singleton
                                        , extends = []
                                        , members = []
                                        }
                                    )
                                ]

                            Type.TypeAliasDefinition typeParams typeExp ->
                                [
                                    TypeAlias
                                    { alias =
                                        typeName |> Name.toTitleCase
                                    , typeArgs =
                                        typeParams |> List.map (Name.toTitleCase >> TypeVar)
                                    , tpe =
                                        mapType typeExp
                                    }
                                ]

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                    mapCustomTypeDefinition Nothing currentPackagePath currentModulePath typeName typeParams accessControlledCtors
                    )

        ( scalaPackagePath, moduleName ) =
                    case currentModulePath |> List.reverse of
                        [] ->
                            ( [], [] )

                        lastName :: reverseModulePath ->
                            ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        moduleUnit : CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ "SpringBoot1" ++ ".scala"
            , packageDecl = ["morphir.sdk"]
            , imports = []
            , typeDecls =
                [
                 (Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Annotated (Just ["@org.springframework.web.bind.annotation.RestController"])
                         <|
                         (Class
                             { modifiers =
                                 []
                             , name =
                                 (moduleName |> Name.toTitleCase) ++ "SpringBoot"
                             , typeArgs =
                                 []
                             , ctorArgs =
                                 []
                             , extends =
                                 [TypeParametrized (TypeVar "SpringBootStatefulAppAdapter")
                                    statefulAppConsTypes (TypeVar ("StatefulApp (" ++ (dotSep scalaPackagePath) ++
                                            "." ++ (moduleName |> Name.toTitleCase) ++ "."
                                            ++ (functionName |> Name.toList |> String.join "") ++ ")" ))]
                             , members =
                                 []
                             }
                         )
                    )
                 )
                ]
            }
    in
    [ moduleUnit ]


mapStatefulAppDefinitionOld : Options -> Package.PackagePath -> Path -> AccessControlled (Module.Definition ta tv) -> List CompilationUnit
mapStatefulAppDefinitionOld opt currentPackagePath currentModulePath accessControlledModuleDef =
    let
        functionName: Name
        functionName =
            case accessControlledModuleDef.access of
                Public ->
                    case accessControlledModuleDef.value of
                        { types, values } ->
                            case (Dict.get (Name.fromString "app") values) of
                                Just acsCtrlValueDef ->
                                    case acsCtrlValueDef.access of
                                        Public ->
                                            case acsCtrlValueDef.value.body of
                                                Value.Apply _ (Constructor  _ _) (Value.Reference _ (FQName _ _ name)) ->
                                                    name
                                                _ -> []
                                        _ -> []
                                _ -> []
                _ -> []
        _ = Debug.log "functionName" functionName

        statefulAppDefinition :  List (Documented (Annotated MemberDecl))
        statefulAppDefinition =
            accessControlledModuleDef.value.values
                |> Dict.toList
                    |> List.concatMap
                        (\( valueName, accessControlledValueDef ) ->
                            case (accessControlledValueDef.value.inputTypes, accessControlledValueDef.value.outputType) of
                                ((stateVariable :: commandVariable :: []) , Type.Tuple _ (stateType :: eventType :: []) ) ->
                                    [(Documented (Nothing)
                                       (Annotated (Just ["@org.springframework.web.bind.annotation.RequestMapping(value = Array(\"/" ++ (valueName |> Name.toCamelCase) ++ "\"), method = Array(org.springframework.web.bind.annotation.RequestMethod.GET))"])
                                       <|
                                        (FunctionDecl
                                            { modifiers = []
                                            , name =
                                                (valueName |> Name.toCamelCase)
                                            , typeArgs =
                                                []
                                            , args =
                                                if List.isEmpty accessControlledValueDef.value.inputTypes then
                                                    []
                                                else
                                                    [ accessControlledValueDef.value.inputTypes
                                                        |> List.map
                                                            (\( argName, a, argType ) ->
                                                                { modifiers = []
                                                                , tpe = mapType argType
                                                                , name = argName |> Name.toCamelCase
                                                                , defaultValue = Nothing
                                                                }
                                                            )
                                                    ]
                                            , returnType =
                                                Just (mapType accessControlledValueDef.value.outputType)
                                            , body =
                                               Just (mapValue accessControlledValueDef.value.body)
                                            }
                                         )
                                        )
                                        )]
                                _ ->
                                    []

                        )

        typeMembers : List MemberDecl
        typeMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        case accessControlledDocumentedTypeDef.value.value of
                            Type.TypeAliasDefinition typeParams (Type.Record _ fields) ->
                                [
                                    MemberTypeDecl
                                    (Class
                                        { modifiers = [ Case ]
                                        , name = typeName |> Name.toTitleCase
                                        , typeArgs = typeParams |> List.map (Name.toTitleCase >> TypeVar)
                                        , ctorArgs =
                                            fields
                                                |> List.map
                                                    (\field ->
                                                        { modifiers = []
                                                        , tpe = mapType field.tpe
                                                        , name = ""
                                                        , defaultValue = Nothing
                                                        }
                                                    )
                                                |> List.singleton
                                        , extends = []
                                        , members = []
                                        }
                                    )
                                ]

                            Type.TypeAliasDefinition typeParams typeExp ->
                                [
                                    TypeAlias
                                    { alias =
                                        typeName |> Name.toTitleCase
                                    , typeArgs =
                                        typeParams |> List.map (Name.toTitleCase >> TypeVar)
                                    , tpe =
                                        mapType typeExp
                                    }
                                ]

                            Type.CustomTypeDefinition typeParams accessControlledCtors ->
                                    mapCustomTypeDefinition Nothing currentPackagePath currentModulePath typeName typeParams accessControlledCtors
                    )

        ( scalaPackagePath, moduleName ) =
                    case currentModulePath |> List.reverse of
                        [] ->
                            ( [], [] )

                        lastName :: reverseModulePath ->
                            ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        moduleUnit : CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = "Controller" ++ (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [
                 (Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Annotated (Just ["@org.springframework.web.bind.annotation.RestController"])
                         <|
                         (Class
                             { modifiers =
                                 []
                             , name =
                                 (moduleName |> Name.toTitleCase) ++ "Controller"
                             , typeArgs =
                                 []
                             , ctorArgs =
                                 []
                             , extends =
                                 []
                             , members =
                                 typeMembers
                                   |> List.map
                                     (\( typed ) ->
                                         (Documented (Nothing)
                                            (Annotated (Nothing)
                                             <| typed
                                             )
                                         )
                                     )
                                   |> List.append statefulAppDefinition
                             }
                         )
                    )
                 )
                ]
            }
    in
    [ moduleUnit ]
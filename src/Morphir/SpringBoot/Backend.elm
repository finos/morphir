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
import List.Extra exposing (unique, uniqueBy)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.File.SourceCode exposing (dotSep)
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution, lookupTypeSpecification)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module exposing (Definition)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Specification(..))
import Morphir.IR.Value as Value exposing (Value(..))
import Morphir.SDK.Customization exposing (Customization(..))
import Morphir.Scala.AST as Scala exposing (Annotated, ArgDecl, CompilationUnit, Documented, MemberDecl(..), Mod(..), Type(..), TypeDecl(..))
import Morphir.Scala.Backend exposing (mapFunctionBody, mapType, maptypeMember)
import Morphir.Scala.PrettyPrinter as PrettyPrinter


type alias Options =
    {}


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packagePath dependencies packageDef ->
            mapPackageDefinition opt distro packagePath packageDef


mapPackageDefinition : Options -> Distribution -> Package.PackageName -> Package.Definition ta va -> FileMap
mapPackageDefinition opt distribution packagePath packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.concatMap
            (\( modulePath, moduleImpl ) ->
                mapStatefulAppDefinition opt distribution packagePath modulePath moduleImpl
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
        |> Dict.fromList


mapStatefulAppDefinition : Options -> Distribution -> Package.PackageName -> Path -> AccessControlled (Module.Definition ta tv) -> List CompilationUnit
mapStatefulAppDefinition opt distribution currentPackagePath currentModulePath accessControlledModuleDef =
    let
        functionName : Name
        functionName =
            case accessControlledModuleDef.access of
                Public ->
                    case accessControlledModuleDef.value of
                        { types, values } ->
                            case Dict.get (Name.fromString "app") values of
                                Just acsCtrlValueDef ->
                                    case acsCtrlValueDef.access of
                                        Public ->
                                            case acsCtrlValueDef.value.body of
                                                Value.Apply _ (Constructor _ _) (Value.Reference _ (FQName _ _ name)) ->
                                                    name

                                                _ ->
                                                    []

                                        _ ->
                                            []

                                _ ->
                                    []

                _ ->
                    []

        functionMembers : List Scala.MemberDecl
        functionMembers =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        if (valueName |> Name.toTitleCase) == (functionName |> Name.toTitleCase) then
                            [ Scala.FunctionDecl
                                { modifiers =
                                    case accessControlledValueDef.access of
                                        AccessControlled.Public ->
                                            []

                                        AccessControlled.Private ->
                                            [ Scala.Private Nothing ]
                                , name =
                                    valueName |> Name.toCamelCase
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
                                    Just (mapFunctionBody distribution accessControlledValueDef.value.body)
                                }
                            ]

                        else
                            []
                    )

        statefulAppTypes : List Type
        statefulAppTypes =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( _, a ) ->
                        case a.value.outputType of
                            Type.Reference _ (FQName mod package name) list ->
                                case
                                    ( Path.toString Name.toTitleCase "." mod
                                    , Path.toString Name.toTitleCase "." package
                                    , name |> Name.toTitleCase
                                    )
                                of
                                    ( "Morphir.SDK", "StatefulApp", "StatefulApp" ) ->
                                        List.map mapType list

                                    _ ->
                                        []

                            _ ->
                                []
                    )

        typeNamesStatefulApp : List Scala.Name
        typeNamesStatefulApp =
            case statefulAppTypes of
                (TypeRef _ keyTypeName) :: (TypeRef _ commandTypeName) :: (TypeRef _ stateTypeName) :: (TypeRef _ eventTypeName) :: [] ->
                    [ keyTypeName, commandTypeName, stateTypeName, eventTypeName ]

                _ ->
                    []

        innerTypesNamesStatefulApp : List Scala.Name
        innerTypesNamesStatefulApp =
            typeNamesStatefulApp
                |> List.concatMap
                    (\name ->
                        case lookupTypeSpecification currentPackagePath currentModulePath (Name.fromString name) distribution of
                            Just (TypeAliasSpecification _ aliasType) ->
                                case mapType aliasType of
                                    TypeRef _ typeName ->
                                        [ typeName ]

                                    _ ->
                                        []

                            Just (CustomTypeSpecification _ constructors) ->
                                constructors
                                    |> List.concatMap
                                        (\constructor ->
                                            case constructor of
                                                Type.Constructor _ types ->
                                                    types
                                                        |> List.concatMap
                                                            (\( _, consType ) ->
                                                                case consType of
                                                                    Type.Reference _ (FQName _ _ consTypeName) _ ->
                                                                        [ consTypeName |> Name.toTitleCase ]

                                                                    _ ->
                                                                        []
                                                            )
                                        )

                            _ ->
                                []
                    )
                |> unique

        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    ( List.append (currentPackagePath |> List.map (Name.toCamelCase >> String.toLower)) (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower)), lastName )

        stateFulImplAdapter : CompilationUnit
        stateFulImplAdapter =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ "SpringBoot" ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Annotated (Just [ "@org.springframework.web.bind.annotation.RestController" ]) <|
                        Class
                            { modifiers =
                                []
                            , name =
                                (moduleName |> Name.toTitleCase) ++ "SpringBoot"
                            , typeArgs =
                                []
                            , ctorArgs =
                                []
                            , extends =
                                [ TypeParametrized (TypeVar "SpringBootStatefulAppAdapter")
                                    statefulAppTypes
                                    (TypeVar
                                        ("StatefulApp ("
                                            ++ dotSep scalaPackagePath
                                            ++ "."
                                            ++ (moduleName |> Name.toTitleCase)
                                            ++ "."
                                            ++ (functionName |> Name.toList |> String.join "")
                                            ++ ")"
                                        )
                                    )
                                ]
                            , members =
                                []
                            }
                    )
                ]
            }

        memberStatefulApp : Maybe Customization -> Scala.Name -> List MemberDecl
        memberStatefulApp annot name =
            case Dict.get (Name.fromString name) accessControlledModuleDef.value.types of
                Just accessControlledDocumentedTypeDef ->
                    maptypeMember annot currentPackagePath currentModulePath accessControlledModuleDef ( Name.fromString name, accessControlledDocumentedTypeDef )

                _ ->
                    []

        statefulAppMembers : List MemberDecl
        statefulAppMembers =
            case typeNamesStatefulApp of
                keyTypeName :: commandTypeName :: stateTypeName :: eventTypeName :: [] ->
                    memberStatefulApp Nothing keyTypeName
                        |> List.append (memberStatefulApp (Just Jackson) eventTypeName)
                        |> List.append (memberStatefulApp (Just Jackson) commandTypeName)
                        |> List.append (memberStatefulApp Nothing stateTypeName)

                _ ->
                    []

        innerMembers : List MemberDecl
        innerMembers =
            accessControlledModuleDef.value.types
                |> Dict.toList
                |> List.concatMap
                    (\( typeName, accessControlledDocumentedTypeDef ) ->
                        if List.member (typeName |> Name.toTitleCase) innerTypesNamesStatefulApp then
                            maptypeMember Nothing currentPackagePath currentModulePath accessControlledModuleDef ( typeName, accessControlledDocumentedTypeDef )

                        else
                            []
                    )

        statefulModule : CompilationUnit
        statefulModule =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Annotated Nothing <|
                        Object
                            { modifiers =
                                []
                            , name =
                                moduleName |> Name.toTitleCase
                            , extends =
                                []
                            , members =
                                functionMembers
                                    |> List.append statefulAppMembers
                                    |> List.append innerMembers
                            }
                    )
                ]
            }
    in
    [ stateFulImplAdapter, statefulModule ]

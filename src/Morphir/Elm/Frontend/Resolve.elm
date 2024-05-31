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


module Morphir.Elm.Frontend.Resolve exposing (Context, Error(..), ImportedNames, LocalNames, ModuleResolver, collectImportedNames, createModuleResolver, encodeError, errorToMessage)

{-| This module contains tools to resolve local names in the Elm source code to [fully-qualified names](../../../IR/FQName) in the IR.
-}

import Dict exposing (Dict)
import Elm.Syntax.Exposing exposing (ExposedType, Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range, emptyRange)
import Json.Encode as Encode
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Name.Codec exposing (encodeName)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Path.Codec exposing (encodePath)
import Morphir.IR.Type as Type
import Morphir.JsonExtra as JsonExtra
import Morphir.SDK.ResultList as ListOfResults
import Set


type alias ModuleName =
    List String


type alias LocalName =
    String


type Error
    = CouldNotFindLocalName Trace NameType LocalName
    | CouldNotFindNameInModule NameType Path Path Name
    | CouldNotFindModule Path
    | AmbiguousImports LocalName (List ( Path, Path ))
    | AmbiguousModulePath Path (List ( Path, Path ))


errorToMessage : Error -> String
errorToMessage error =
    case error of
        CouldNotFindLocalName trace target localName ->
            String.concat [ "Could not find local name '", localName, "'" ]

        CouldNotFindNameInModule nameType packagePath modulePath localName ->
            String.concat
                [ "Could not find name '"
                , Name.toCamelCase localName
                , "' in module '"
                , Path.toString Name.toCamelCase "." modulePath
                , "' in package '"
                , Path.toString Name.toCamelCase "." packagePath
                , "'"
                ]

        CouldNotFindModule packageAndModulePath ->
            String.concat
                [ "Could not find module '"
                , Path.toString Name.toCamelCase "." packageAndModulePath
                ]

        AmbiguousImports localName modulePaths ->
            String.concat
                [ "Ambiguous local name imports. The local name `"
                , localName
                , "' is imported from multiple modules: "
                , modulePaths
                    |> List.map
                        (\( packagePath, modulePath ) ->
                            String.join "."
                                [ Path.toString Name.toCamelCase "." packagePath
                                , Path.toString Name.toCamelCase "." modulePath
                                ]
                        )
                    |> String.join ", "
                ]

        AmbiguousModulePath packageAndModulePath matchingPaths ->
            String.concat
                [ "Ambiguous module imports. The module name `"
                , Path.toString Name.toCamelCase "." packageAndModulePath
                , "' matches multiple modules: "
                , matchingPaths
                    |> List.map
                        (\( packagePath, modulePath ) ->
                            String.join "."
                                [ Path.toString Name.toCamelCase "." packagePath
                                , Path.toString Name.toCamelCase "." modulePath
                                ]
                        )
                    |> String.join ", "
                ]


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        CouldNotFindLocalName trace target localName ->
            JsonExtra.encodeConstructor "CouldNotFindLocalName"
                [ encodeTrace trace
                , encodeNameType target
                , Encode.string localName
                ]

        CouldNotFindNameInModule nameType packagePath modulePath localName ->
            JsonExtra.encodeConstructor "CouldNotFindNameInModule"
                [ encodeNameType nameType
                , packagePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , modulePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , localName |> Name.toTitleCase |> Encode.string
                ]

        CouldNotFindModule packageAndModulePath ->
            JsonExtra.encodeConstructor "CouldNotFindModule"
                [ encodePath packageAndModulePath
                ]

        AmbiguousImports localName modulePaths ->
            JsonExtra.encodeConstructor "AmbiguousImports"
                [ Encode.string localName
                , modulePaths
                    |> Encode.list
                        (\( packagePath, modulePath ) ->
                            Encode.list identity
                                [ encodePath packagePath
                                , encodePath modulePath
                                ]
                        )
                ]

        AmbiguousModulePath packageAndModulePath matchingPaths ->
            JsonExtra.encodeConstructor "AmbiguousModulePath"
                [ encodePath packageAndModulePath
                , matchingPaths
                    |> Encode.list
                        (\( packagePath, modulePath ) ->
                            Encode.list identity
                                [ encodePath packagePath
                                , encodePath modulePath
                                ]
                        )
                ]


type NameType
    = Type
    | Ctor
    | Value


encodeNameType : NameType -> Encode.Value
encodeNameType kind =
    case kind of
        Type ->
            Encode.string "type"

        Ctor ->
            Encode.string "ctor"

        Value ->
            Encode.string "value"


type Trace
    = ResolveTarget NameType ModuleName LocalName
    | ScannedLocalNames LocalNames Trace


encodeTrace : Trace -> Encode.Value
encodeTrace trace =
    case trace of
        ResolveTarget nameType moduleName localName ->
            Encode.list identity
                [ Encode.string "resolve_target"
                , encodeNameType nameType
                , Encode.list Encode.string moduleName
                , Encode.string localName
                ]

        ScannedLocalNames localNames nestedTrace ->
            Encode.list identity
                [ Encode.string "scanned_local_names"
                , encodeLocalNames localNames
                , encodeTrace nestedTrace
                ]


type alias LocalNames =
    { typeNames : List Name
    , ctorNames : Dict Name (List Name)
    , valueNames : List Name
    }


type alias ImportedNames =
    { typeNames : Dict Name (List ( Path, Path ))
    , ctorNames : Dict Name (List ( Path, Path ))
    , valueNames : Dict Name (List ( Path, Path ))
    }


encodeLocalNames : LocalNames -> Encode.Value
encodeLocalNames localNames =
    Encode.object
        [ ( "typeNames", Encode.list encodeName localNames.typeNames )
        , ( "ctorNames"
          , localNames.ctorNames
                |> Dict.toList
                |> Encode.list
                    (\( typeName, ctorNames ) ->
                        Encode.list identity
                            [ encodeName typeName
                            , Encode.list encodeName ctorNames
                            ]
                    )
          )
        , ( "valueNames", Encode.list encodeName localNames.valueNames )
        ]


type alias ModuleResolver =
    { resolveType : ModuleName -> LocalName -> Result Error FQName
    , resolveCtor : ModuleName -> LocalName -> Result Error FQName
    , resolveValue : ModuleName -> LocalName -> Result Error FQName
    }


defaultImports : List Import
defaultImports =
    let
        er : Range
        er =
            emptyRange

        -- empty node
        en : a -> Node a
        en a =
            Node emptyRange a
    in
    [ Import (en [ "Basics" ]) Nothing (Just (en (All emptyRange)))
    , Import (en [ "List" ]) Nothing (Just (en (Explicit [ en (TypeOrAliasExpose "List") ])))
    , Import (en [ "Maybe" ]) Nothing (Just (en (Explicit [ en (TypeExpose (ExposedType "Maybe" (Just er))) ])))
    , Import (en [ "Result" ]) Nothing (Just (en (Explicit [ en (TypeExpose (ExposedType "Result" (Just er))) ])))
    , Import (en [ "String" ]) Nothing (Just (en (Explicit [ en (TypeOrAliasExpose "String") ])))
    , Import (en [ "Char" ]) Nothing (Just (en (Explicit [ en (TypeOrAliasExpose "Char") ])))
    , Import (en [ "Tuple" ]) Nothing Nothing
    ]


moduleMapping : Dict Path Path
moduleMapping =
    let
        sdkModule m =
            List.append
                (Path.fromString "Morphir.SDK")
                [ m ]
    in
    Dict.fromList
        [ ( [ [ "basics" ] ], sdkModule [ "basics" ] )
        , ( [ [ "list" ] ], sdkModule [ "list" ] )
        , ( [ [ "dict" ] ], sdkModule [ "dict" ] )
        , ( [ [ "set" ] ], sdkModule [ "set" ] )
        , ( [ [ "maybe" ] ], sdkModule [ "maybe" ] )
        , ( [ [ "result" ] ], sdkModule [ "result" ] )
        , ( [ [ "string" ] ], sdkModule [ "string" ] )
        , ( [ [ "char" ] ], sdkModule [ "char" ] )
        , ( [ [ "tuple" ] ], sdkModule [ "tuple" ] )
        , ( [ [ "regex" ] ], sdkModule [ "regex" ] )
        ]


type alias Context ta va =
    { dependencies : Dict Path (Package.Specification ())
    , currentPackagePath : Path
    , currentPackageModules : Dict Path (Module.Specification ())
    , explicitImports : List Import
    , currentModulePath : Path
    , moduleDef : Module.Definition ta va
    }


createModuleResolver : Context ta va -> ModuleResolver
createModuleResolver ctx =
    let
        -- As we resolve names we will first have to look at local names so we collect them here.
        localNames : LocalNames
        localNames =
            { typeNames =
                ctx.moduleDef.types
                    |> Dict.keys
            , ctorNames =
                ctx.moduleDef.types
                    |> Dict.toList
                    |> List.filterMap
                        (\( typeName, accessControlledDocumentedTypeDef ) ->
                            case accessControlledDocumentedTypeDef.value.value of
                                Type.CustomTypeDefinition _ accessControlledCtors ->
                                    Just
                                        ( typeName
                                        , accessControlledCtors.value |> Dict.keys
                                        )

                                Type.TypeAliasDefinition _ (Type.Record _ _) ->
                                    Just ( typeName, [ typeName ] )

                                _ ->
                                    Nothing
                        )
                    |> Dict.fromList
            , valueNames =
                ctx.moduleDef.values
                    |> Dict.keys
            }

        -- Elm has default imports that are included automatically so we prepend that to the explicit imports.
        imports : List Import
        imports =
            defaultImports ++ ctx.explicitImports

        -- Combine current package with dependencies to get a full dictionary of packages
        packageSpecs : Dict Path (Package.Specification ())
        packageSpecs =
            let
                currentPackageSpec : Package.Specification ()
                currentPackageSpec =
                    Package.Specification ctx.currentPackageModules
            in
            ctx.dependencies
                |> Dict.insert ctx.currentPackagePath currentPackageSpec

        importedNamesResult : Result Error ImportedNames
        importedNamesResult =
            imports
                |> collectImportedNames
                    (\packageAndModulePath ->
                        locateModule packageSpecs packageAndModulePath
                            |> Result.map
                                (\( packagePath, modulePath, moduleSpec ) ->
                                    ( packagePath, modulePath, moduleSpecToLocalNames moduleSpec )
                                )
                    )

        importedModulesResult : Result Error (Dict ModuleName ( Path, Path, Module.Specification () ))
        importedModulesResult =
            imports
                |> List.map
                    (\imp ->
                        let
                            moduleName =
                                imp.moduleName |> Node.value
                        in
                        case imp.moduleAlias of
                            Nothing ->
                                locateModule packageSpecs (moduleName |> List.map Name.fromString)
                                    |> Result.map
                                        (\resolved ->
                                            [ ( moduleName, resolved )
                                            ]
                                        )

                            Just (Node _ alias) ->
                                locateModule packageSpecs (moduleName |> List.map Name.fromString)
                                    |> Result.map
                                        (\resolved ->
                                            [ ( moduleName, resolved )
                                            , ( alias, resolved )
                                            ]
                                        )
                    )
                |> ListOfResults.keepFirstError
                |> Result.map (List.concat >> Dict.fromList)

        resolveWithoutModuleName : Trace -> NameType -> LocalName -> Result Error FQName
        resolveWithoutModuleName trace nameType sourceLocalName =
            let
                localName : Name
                localName =
                    sourceLocalName |> Name.fromString

                localToFullyQualified : Dict Name (List ( Path, Path )) -> Result Error FQName
                localToFullyQualified imported =
                    imported
                        |> Dict.get localName
                        |> Result.fromMaybe (CouldNotFindLocalName trace nameType sourceLocalName)
                        |> Result.andThen
                            (\modulePaths ->
                                -- deduplicate module paths before the check
                                case modulePaths |> Set.fromList |> Set.toList of
                                    [] ->
                                        Err (CouldNotFindLocalName trace nameType sourceLocalName)

                                    [ ( packagePath, modulePath ) ] ->
                                        Ok (fQName packagePath modulePath localName)

                                    _ ->
                                        Err (AmbiguousImports sourceLocalName modulePaths)
                            )
            in
            importedNamesResult
                |> Result.andThen
                    (\importedNames ->
                        case nameType of
                            Type ->
                                localToFullyQualified importedNames.typeNames

                            Ctor ->
                                localToFullyQualified importedNames.ctorNames

                            Value ->
                                localToFullyQualified importedNames.valueNames
                    )

        resolveWithModuleName : Trace -> NameType -> ModuleName -> LocalName -> Result Error FQName
        resolveWithModuleName trace nameType sourceModuleName sourceLocalName =
            let
                localName : Name
                localName =
                    sourceLocalName |> Name.fromString
            in
            importedModulesResult
                |> Result.andThen
                    (\importedModules ->
                        importedModules
                            |> Dict.get sourceModuleName
                            |> Result.fromMaybe (CouldNotFindModule (sourceModuleName |> List.map Name.fromString))
                            |> Result.andThen
                                (\( packagePath, modulePath, moduleSpec ) ->
                                    if isAmongLocalNames nameType localName (moduleSpecToLocalNames moduleSpec) then
                                        Ok (fQName packagePath modulePath localName)

                                    else
                                        Err (CouldNotFindNameInModule nameType packagePath modulePath localName)
                                )
                    )

        resolve : NameType -> ModuleName -> LocalName -> Result Error FQName
        resolve nameType elmModuleName elmLocalNameToResolve =
            let
                trace : Trace
                trace =
                    ResolveTarget nameType elmModuleName elmLocalNameToResolve

                localNameToResolve =
                    elmLocalNameToResolve |> Name.fromString
            in
            if List.isEmpty elmModuleName then
                -- If the name is not prefixed with a module we need to look it up within the module first
                if isAmongLocalNames nameType localNameToResolve localNames then
                    Ok (fQName ctx.currentPackagePath ctx.currentModulePath localNameToResolve)

                else
                    resolveWithoutModuleName (ScannedLocalNames localNames trace) nameType elmLocalNameToResolve

            else
                -- If the name is prefixed with a module we can skip the local resolution
                resolveWithModuleName trace nameType elmModuleName elmLocalNameToResolve
    in
    ModuleResolver (resolve Type) (resolve Ctor) (resolve Value)


isAmongLocalNames : NameType -> Name -> LocalNames -> Bool
isAmongLocalNames nameType localName localNames =
    case nameType of
        Type ->
            localNames.typeNames |> List.member localName

        Ctor ->
            localNames.ctorNames |> Dict.values |> List.concat |> List.member localName

        Value ->
            localNames.valueNames |> List.member localName


{-| Finds a module among all the visible packages based on a single path that contains both
the package path and the module path within that package. This requires identifying all packages
that match the path prefix and checking if the module is part of it.
-}
locateModule : Dict Path (Package.Specification ()) -> Path -> Result Error ( Path, Path, Module.Specification () )
locateModule packageSpecs packageAndModulePath =
    let
        mappedPackageAndModulePath =
            moduleMapping
                |> Dict.get packageAndModulePath
                |> Maybe.withDefault packageAndModulePath

        matchingModules =
            packageSpecs
                |> Dict.toList
                |> List.filterMap
                    (\( packagePath, packageSpec ) ->
                        if packagePath |> Path.isPrefixOf mappedPackageAndModulePath then
                            let
                                modulePath : Path
                                modulePath =
                                    mappedPackageAndModulePath
                                        |> List.drop (List.length packagePath)
                            in
                            packageSpec.modules
                                |> Dict.get modulePath
                                |> Maybe.map
                                    (\moduleSpec ->
                                        ( packagePath, modulePath, moduleSpec )
                                    )

                        else
                            Nothing
                    )
    in
    case matchingModules of
        [] ->
            Err (CouldNotFindModule packageAndModulePath)

        [ matchingModule ] ->
            Ok matchingModule

        multipleMatches ->
            Err
                (AmbiguousModulePath packageAndModulePath
                    (multipleMatches
                        |> List.map
                            (\( packagePath, modulePath, _ ) ->
                                ( packagePath, modulePath )
                            )
                    )
                )


{-| Extract exposed local names from a module specification.
-}
moduleSpecToLocalNames : Module.Specification () -> LocalNames
moduleSpecToLocalNames moduleSpec =
    { typeNames =
        moduleSpec.types
            |> Dict.keys
    , ctorNames =
        moduleSpec.types
            |> Dict.toList
            |> List.filterMap
                (\( typeName, typeSpec ) ->
                    case typeSpec.value of
                        Type.OpaqueTypeSpecification _ ->
                            Just ( typeName, [] )

                        Type.CustomTypeSpecification _ ctors ->
                            Just
                                ( typeName
                                , ctors |> Dict.keys
                                )

                        Type.TypeAliasSpecification _ (Type.Record _ _) ->
                            Just ( typeName, [ typeName ] )

                        _ ->
                            Nothing
                )
            |> Dict.fromList
    , valueNames =
        moduleSpec.values
            |> Dict.keys
    }


{-| We loop through the imports and create a mapping from local name to module names. Notice that the same
name can be imported from multiple modules which will only cause a collision if the names are actually used.
We will detect and report that during resolution.
-}
collectImportedNames : (Path -> Result Error ( Path, Path, LocalNames )) -> List Import -> Result Error ImportedNames
collectImportedNames getModulesExposedNames imports =
    imports
        |> List.foldl
            (\nextImport importedNamesSoFar ->
                nextImport.moduleName
                    |> Node.value
                    |> List.map Name.fromString
                    |> getModulesExposedNames
                    |> Result.andThen
                        (\( importPackagePath, importModulePath, exposedLocalNames ) ->
                            let
                                appendValue : comparable -> v -> Dict comparable (List v) -> Dict comparable (List v)
                                appendValue key value =
                                    Dict.update key
                                        (\currentValue ->
                                            case currentValue of
                                                Just values ->
                                                    Just (List.append values [ value ])

                                                Nothing ->
                                                    Just [ value ]
                                        )

                                addTypeName : Name -> ImportedNames -> ImportedNames
                                addTypeName localName importedNames =
                                    { importedNames
                                        | typeNames =
                                            importedNames.typeNames
                                                |> appendValue localName ( importPackagePath, importModulePath )
                                    }

                                addCtorName : Name -> ImportedNames -> ImportedNames
                                addCtorName localName importedNames =
                                    { importedNames
                                        | ctorNames =
                                            importedNames.ctorNames
                                                |> appendValue localName ( importPackagePath, importModulePath )
                                    }

                                addValueName : Name -> ImportedNames -> ImportedNames
                                addValueName localName importedNames =
                                    { importedNames
                                        | valueNames =
                                            importedNames.valueNames
                                                |> appendValue localName ( importPackagePath, importModulePath )
                                    }

                                addNames : (Name -> ImportedNames -> ImportedNames) -> List Name -> ImportedNames -> ImportedNames
                                addNames addName localNames importedNames =
                                    List.foldl addName importedNames localNames
                            in
                            case nextImport.exposingList of
                                Just (Node _ expose) ->
                                    case expose of
                                        Explicit exposeList ->
                                            exposeList
                                                |> List.foldl
                                                    (\(Node _ nextTopLevelExpose) explicitImportedNamesSoFar ->
                                                        case nextTopLevelExpose of
                                                            InfixExpose _ ->
                                                                -- Infix declarations are ignored
                                                                explicitImportedNamesSoFar

                                                            FunctionExpose sourceName ->
                                                                explicitImportedNamesSoFar
                                                                    |> Result.map (addValueName (sourceName |> Name.fromString))

                                                            TypeOrAliasExpose sourceName ->
                                                                explicitImportedNamesSoFar
                                                                    |> Result.map (addTypeName (sourceName |> Name.fromString))
                                                                    |> Result.map
                                                                        (addNames addCtorName
                                                                            (case exposedLocalNames.ctorNames |> Dict.get (sourceName |> Name.fromString) of
                                                                                Just [ ctorName ] ->
                                                                                    if (sourceName |> Name.fromString) == ctorName then
                                                                                        [ ctorName ]

                                                                                    else
                                                                                        []

                                                                                _ ->
                                                                                    []
                                                                            )
                                                                        )

                                                            TypeExpose exposedType ->
                                                                case exposedType.open of
                                                                    Just _ ->
                                                                        explicitImportedNamesSoFar
                                                                            |> Result.map (addTypeName (exposedType.name |> Name.fromString))
                                                                            |> Result.map
                                                                                (addNames addCtorName
                                                                                    (exposedLocalNames.ctorNames
                                                                                        |> Dict.get (exposedType.name |> Name.fromString)
                                                                                        |> Maybe.withDefault []
                                                                                    )
                                                                                )

                                                                    Nothing ->
                                                                        explicitImportedNamesSoFar
                                                                            |> Result.map (addTypeName (exposedType.name |> Name.fromString))
                                                    )
                                                    importedNamesSoFar

                                        All _ ->
                                            importedNamesSoFar
                                                |> Result.map (addNames addTypeName exposedLocalNames.typeNames)
                                                |> Result.map (addNames addCtorName (exposedLocalNames.ctorNames |> Dict.values |> List.concat))
                                                |> Result.map (addNames addValueName exposedLocalNames.valueNames)

                                Nothing ->
                                    importedNamesSoFar
                        )
            )
            (Ok (ImportedNames Dict.empty Dict.empty Dict.empty))

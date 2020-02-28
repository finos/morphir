module Morphir.Elm.Frontend.Resolve exposing (Error, ModuleResolver, PackageResolver, createModuleResolver)

import Dict exposing (Dict)
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.Pattern exposing (matchAny)
import Set exposing (Set)


type alias ModuleName =
    List String


type alias LocalName =
    String


type Error
    = ModuleDoesNotExpose ModuleName LocalName
    | CouldNotDecompose ModuleName
    | CouldNotFindLocalName LocalName
    | CouldNotFindName Path Path Name
    | CouldNotFindModule Path Path
    | CouldNotFindPackage Path
    | ModuleNotImported ModuleName
    | AliasNotFound String


type alias ModuleResolver =
    { resolveType : ModuleName -> LocalName -> Result Error FQName
    , resolveValue : ModuleName -> LocalName -> Result Error FQName
    }


type alias PackageResolver =
    { ctorNames : ModuleName -> LocalName -> Result Error (List String)
    , exposesType : ModuleName -> LocalName -> Result Error Bool
    , exposesValue : ModuleName -> LocalName -> Result Error Bool
    , decomposeModuleName : ModuleName -> Result Error ( Path, Path )
    }


createPackageResolver : Dict Path (Package.Declaration a) -> Path -> Dict Path (Module.Declaration a) -> PackageResolver
createPackageResolver dependencies currentPackagePath currentPackageModules =
    let
        lookupModule : Path -> Path -> Result Error (Module.Declaration a)
        lookupModule packagePath modulePath =
            let
                modulesResult =
                    if packagePath == currentPackagePath then
                        Ok currentPackageModules

                    else
                        dependencies
                            |> Dict.get packagePath
                            |> Result.fromMaybe (CouldNotFindPackage packagePath)
                            |> Result.map .modules
            in
            modulesResult
                |> Result.andThen
                    (\modules ->
                        modules
                            |> Dict.get modulePath
                            |> Result.fromMaybe (CouldNotFindModule currentPackagePath modulePath)
                    )

        ctorNames : ModuleName -> LocalName -> Result Error (List String)
        ctorNames moduleName localName =
            let
                typeName : Name
                typeName =
                    Name.fromString localName
            in
            decomposeModuleName moduleName
                |> Result.andThen
                    (\( packagePath, modulePath ) ->
                        lookupModule packagePath modulePath
                            |> Result.andThen
                                (\moduleDecl ->
                                    moduleDecl.types
                                        |> Dict.get typeName
                                        |> Result.fromMaybe (CouldNotFindName packagePath modulePath typeName)
                                )
                            |> Result.map
                                (\typeDecl ->
                                    typeDecl
                                        |> Type.matchCustomTypeDeclaration matchAny matchAny
                                        |> Maybe.map
                                            (\( _, ctors ) ->
                                                ctors
                                                    |> List.map (Tuple.first >> Name.toTitleCase)
                                            )
                                        |> Maybe.withDefault []
                                )
                    )

        exposesType : ModuleName -> LocalName -> Result Error Bool
        exposesType moduleName localName =
            let
                typeName : Name
                typeName =
                    Name.fromString localName
            in
            decomposeModuleName moduleName
                |> Result.andThen
                    (\( packagePath, modulePath ) ->
                        lookupModule packagePath modulePath
                            |> Result.map
                                (\moduleDecl ->
                                    moduleDecl.types
                                        |> Dict.get typeName
                                        |> Maybe.map (\_ -> True)
                                        |> Maybe.withDefault False
                                )
                    )

        exposesValue : ModuleName -> LocalName -> Result Error Bool
        exposesValue moduleName localName =
            let
                valueName : Name
                valueName =
                    Name.fromString localName
            in
            decomposeModuleName moduleName
                |> Result.andThen
                    (\( packagePath, modulePath ) ->
                        lookupModule packagePath modulePath
                            |> Result.map
                                (\moduleDecl ->
                                    moduleDecl.values
                                        |> Dict.get valueName
                                        |> Maybe.map (\_ -> True)
                                        |> Maybe.withDefault False
                                )
                    )

        decomposeModuleName : ModuleName -> Result Error ( Path, Path )
        decomposeModuleName moduleName =
            let
                suppliedModulePath : Path
                suppliedModulePath =
                    moduleName
                        |> List.map Name.fromString

                matchModuleToPackagePath modulePath packagePath =
                    if packagePath |> Path.isPrefixOf modulePath then
                        Just ( packagePath, modulePath |> List.drop (List.length packagePath) )

                    else
                        Nothing
            in
            matchModuleToPackagePath suppliedModulePath currentPackagePath
                |> Maybe.map Just
                |> Maybe.withDefault
                    (dependencies
                        |> Dict.keys
                        |> List.filterMap (matchModuleToPackagePath suppliedModulePath)
                        |> List.head
                    )
                |> Result.fromMaybe (CouldNotDecompose moduleName)
    in
    PackageResolver ctorNames exposesType exposesValue decomposeModuleName


createModuleResolver : PackageResolver -> List Import -> ModuleResolver
createModuleResolver packageResolver imports =
    let
        explicitNames : (ModuleName -> TopLevelExpose -> List LocalName) -> Dict LocalName ModuleName
        explicitNames matchExpose =
            imports
                |> List.concatMap
                    (\{ moduleName, exposingList } ->
                        case exposingList of
                            Nothing ->
                                []

                            Just (Node _ expose) ->
                                case expose of
                                    All _ ->
                                        []

                                    Explicit explicitExposeNodes ->
                                        explicitExposeNodes
                                            |> List.map Node.value
                                            |> List.concatMap (matchExpose (Node.value moduleName))
                                            |> List.map
                                                (\localName ->
                                                    ( localName
                                                    , Node.value moduleName
                                                    )
                                                )
                    )
                |> Dict.fromList

        explicitTypeNames : Dict LocalName ModuleName
        explicitTypeNames =
            explicitNames
                (\_ topLevelExpose ->
                    case topLevelExpose of
                        TypeOrAliasExpose name ->
                            [ name ]

                        TypeExpose { name } ->
                            [ name ]

                        _ ->
                            []
                )

        explicitValueNames : Dict LocalName ModuleName
        explicitValueNames =
            explicitNames
                (\moduleName topLevelExpose ->
                    case topLevelExpose of
                        FunctionExpose name ->
                            [ name ]

                        TypeExpose { name, open } ->
                            open
                                |> Maybe.andThen
                                    (\_ ->
                                        packageResolver.ctorNames moduleName name
                                            |> Result.toMaybe
                                    )
                                |> Maybe.withDefault []

                        _ ->
                            []
                )

        allExposeModules : List ModuleName
        allExposeModules =
            imports
                |> List.filterMap
                    (\{ moduleName, exposingList } ->
                        case exposingList of
                            Just (Node _ (All _)) ->
                                Just (Node.value moduleName)

                            _ ->
                                Nothing
                    )

        importedModuleNames : Set ModuleName
        importedModuleNames =
            imports
                |> List.map (\{ moduleName } -> Node.value moduleName)
                |> Set.fromList

        moduleAliases : Dict String ModuleName
        moduleAliases =
            imports
                |> List.filterMap
                    (\{ moduleName, moduleAlias } ->
                        moduleAlias
                            |> Maybe.map
                                (\aliasNode ->
                                    ( aliasNode |> Node.value |> String.join "."
                                    , Node.value moduleName
                                    )
                                )
                    )
                |> Dict.fromList

        resolveWithoutModuleName : Bool -> LocalName -> Maybe ModuleName
        resolveWithoutModuleName isType localName =
            let
                explNames =
                    if isType then
                        explicitTypeNames

                    else
                        explicitValueNames

                exposes =
                    if isType then
                        packageResolver.exposesType

                    else
                        packageResolver.exposesValue
            in
            case explNames |> Dict.get localName of
                Just moduleName ->
                    Just moduleName

                Nothing ->
                    allExposeModules
                        |> List.filterMap
                            (\moduleName ->
                                case exposes moduleName localName of
                                    Ok True ->
                                        Just moduleName

                                    _ ->
                                        Nothing
                            )
                        |> List.head

        resolveModuleName : Bool -> ModuleName -> LocalName -> Result Error ModuleName
        resolveModuleName isType moduleName localName =
            case moduleName of
                [] ->
                    resolveWithoutModuleName isType localName
                        |> Result.fromMaybe (CouldNotFindLocalName localName)

                [ moduleAlias ] ->
                    moduleAliases
                        |> Dict.get moduleAlias
                        |> Result.fromMaybe (AliasNotFound moduleAlias)

                fullModuleName ->
                    if importedModuleNames |> Set.member fullModuleName then
                        Ok fullModuleName

                    else
                        Err (ModuleNotImported fullModuleName)

        resolve : Bool -> ModuleName -> LocalName -> Result Error FQName
        resolve isType moduleName localName =
            resolveModuleName isType moduleName localName
                |> Result.andThen packageResolver.decomposeModuleName
                |> Result.map
                    (\( packagePath, modulePath ) ->
                        fQName packagePath modulePath (Name.fromString localName)
                    )

        resolveType : ModuleName -> LocalName -> Result Error FQName
        resolveType =
            resolve True

        resolveValue : ModuleName -> LocalName -> Result Error FQName
        resolveValue =
            resolve False
    in
    ModuleResolver resolveType resolveValue

module Morphir.Elm.Frontend.Resolve exposing (Error(..), ModuleResolver, PackageResolver, createModuleResolver, createPackageResolver, encodeError)

import Dict exposing (Dict)
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (emptyRange)
import Json.Encode as Encode
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type
import Morphir.JsonExtra as JsonExtra
import Set exposing (Set)


type alias ModuleName =
    List String


type alias LocalName =
    String


type Error
    = CouldNotDecompose ModuleName
    | CouldNotFindLocalName LocalName
    | CouldNotFindName Path Path Name
    | CouldNotFindModule Path Path
    | CouldNotFindPackage Path
    | ModuleNotImported ModuleName
    | AliasNotFound String
    | PackageNotPrefixOfModule Path Path


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        CouldNotDecompose moduleName ->
            JsonExtra.encodeConstructor "CouldNotDecompose"
                [ Encode.string (String.join "." moduleName) ]

        CouldNotFindLocalName localName ->
            JsonExtra.encodeConstructor "CouldNotFindLocalName"
                [ Encode.string localName ]

        CouldNotFindName packagePath modulePath localName ->
            JsonExtra.encodeConstructor "CouldNotFindName"
                [ packagePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , modulePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , localName |> Name.toTitleCase |> Encode.string
                ]

        CouldNotFindModule packagePath modulePath ->
            JsonExtra.encodeConstructor "CouldNotFindModule"
                [ packagePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , modulePath |> Path.toString Name.toTitleCase "." |> Encode.string
                ]

        CouldNotFindPackage packagePath ->
            JsonExtra.encodeConstructor "CouldNotFindPackage"
                [ packagePath |> Path.toString Name.toTitleCase "." |> Encode.string ]

        ModuleNotImported moduleName ->
            JsonExtra.encodeConstructor "ModuleNotImported"
                [ Encode.string (String.join "." moduleName) ]

        AliasNotFound alias ->
            JsonExtra.encodeConstructor "AliasNotFound"
                [ Encode.string alias ]

        PackageNotPrefixOfModule packagePath modulePath ->
            JsonExtra.encodeConstructor "PackageNotPrefixOfModule"
                [ packagePath |> Path.toString Name.toTitleCase "." |> Encode.string
                , modulePath |> Path.toString Name.toTitleCase "." |> Encode.string
                ]


type alias ModuleResolver =
    { resolveType : ModuleName -> LocalName -> Result Error FQName
    , resolveValue : ModuleName -> LocalName -> Result Error FQName
    }


type alias PackageResolver =
    { packagePath : Path
    , ctorNames : ModuleName -> LocalName -> Result Error (List String)
    , exposesType : ModuleName -> LocalName -> Result Error Bool
    , exposesValue : ModuleName -> LocalName -> Result Error Bool
    , decomposeModuleName : ModuleName -> Result Error ( Path, Path )
    }


defaultImports : List Import
defaultImports =
    let
        importExplicit : ModuleName -> Maybe String -> List TopLevelExpose -> Import
        importExplicit moduleName maybeAlias exposingList =
            Import
                (Node emptyRange moduleName)
                (maybeAlias
                    |> Maybe.map (List.singleton >> Node emptyRange)
                )
                (exposingList
                    |> List.map (Node emptyRange)
                    |> Explicit
                    |> Node emptyRange
                    |> Just
                )
    in
    [ importExplicit [ "Morphir", "SDK", "Bool" ] Nothing [ TypeOrAliasExpose "Bool" ]
    , importExplicit [ "Morphir", "SDK", "Char" ] (Just "Char") [ TypeOrAliasExpose "Char" ]
    , importExplicit [ "Morphir", "SDK", "Int" ] Nothing [ TypeOrAliasExpose "Int" ]
    , importExplicit [ "Morphir", "SDK", "Float" ] Nothing [ TypeOrAliasExpose "Float" ]
    , importExplicit [ "Morphir", "SDK", "String" ] (Just "String") [ TypeOrAliasExpose "String" ]
    , importExplicit [ "Morphir", "SDK", "Maybe" ] (Just "Maybe") [ TypeOrAliasExpose "Maybe" ]
    , importExplicit [ "Morphir", "SDK", "Result" ] (Just "Result") [ TypeOrAliasExpose "Result" ]
    , importExplicit [ "Morphir", "SDK", "List" ] (Just "List") [ TypeOrAliasExpose "List" ]
    , importExplicit [ "Morphir", "SDK", "Regex" ] (Just "Regex") [ TypeOrAliasExpose "Regex" ]
    , importExplicit [ "Morphir", "SDK", "Tuple" ] (Just "Tuple") []
    , importExplicit [ "Morphir", "SDK", "StatefulApp" ] Nothing [ TypeOrAliasExpose "StatefulApp" ]
    ]


moduleMapping : Dict ModuleName ModuleName
moduleMapping =
    Dict.fromList
        [ ( [ "Dict" ], [ "Morphir", "SDK", "Dict" ] )
        ]


createPackageResolver : Dict Path (Package.Specification a) -> Path -> Dict Path (Module.Specification a) -> PackageResolver
createPackageResolver dependencies currentPackagePath currentPackageModules =
    let
        lookupModule : Path -> Path -> Result Error (Module.Specification a)
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
                                (\documentedTypeDecl ->
                                    case documentedTypeDecl.value of
                                        Type.CustomTypeSpecification _ ctors ->
                                            ctors
                                                |> List.map
                                                    (\(Type.Constructor ctorName _) ->
                                                        ctorName |> Name.toTitleCase
                                                    )

                                        _ ->
                                            []
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
                morphirModuleName : ModuleName
                morphirModuleName =
                    moduleMapping |> Dict.get moduleName |> Maybe.withDefault moduleName

                suppliedModulePath : Path
                suppliedModulePath =
                    morphirModuleName
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
                |> Result.fromMaybe (CouldNotDecompose morphirModuleName)
    in
    PackageResolver currentPackagePath ctorNames exposesType exposesValue decomposeModuleName


createModuleResolver : PackageResolver -> List Import -> Path -> Module.Definition a -> ModuleResolver
createModuleResolver packageResolver elmImports currenctModulePath moduleDef =
    let
        explicitImports : List Import
        explicitImports =
            elmImports
                |> List.map
                    (\imp ->
                        { imp
                            | moduleName =
                                imp.moduleName
                                    |> Node.map
                                        (\moduleName ->
                                            moduleMapping
                                                |> Dict.get moduleName
                                                |> Maybe.withDefault moduleName
                                        )
                        }
                    )

        imports : List Import
        imports =
            defaultImports ++ explicitImports

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

        resolveExternally : Bool -> ModuleName -> LocalName -> Result Error FQName
        resolveExternally isType moduleName localName =
            resolveModuleName isType moduleName localName
                |> Result.andThen packageResolver.decomposeModuleName
                |> Result.map
                    (\( packagePath, modulePath ) ->
                        fQName packagePath modulePath (Name.fromString localName)
                    )

        resolve : Bool -> ModuleName -> LocalName -> Result Error FQName
        resolve isType elmModuleName elmLocalName =
            if List.isEmpty elmModuleName then
                -- If the name is not prefixed with a module we need to look it up within the module first
                let
                    localNames =
                        if isType then
                            moduleDef.types |> Dict.keys

                        else
                            moduleDef.values |> Dict.keys

                    localName =
                        elmLocalName |> Name.fromString
                in
                if localNames |> List.member localName then
                    if Path.isPrefixOf currenctModulePath packageResolver.packagePath then
                        Ok (fQName packageResolver.packagePath (currenctModulePath |> List.drop (List.length packageResolver.packagePath)) localName)

                    else
                        Err (PackageNotPrefixOfModule packageResolver.packagePath currenctModulePath)

                else
                    resolveExternally isType elmModuleName elmLocalName

            else
                -- If the name is prefixed with a module we can skip the local resolution
                resolveExternally isType elmModuleName elmLocalName

        resolveType : ModuleName -> LocalName -> Result Error FQName
        resolveType moduleName =
            resolve True
                (moduleMapping |> Dict.get moduleName |> Maybe.withDefault moduleName)

        resolveValue : ModuleName -> LocalName -> Result Error FQName
        resolveValue moduleName =
            resolve False
                (moduleMapping |> Dict.get moduleName |> Maybe.withDefault moduleName)
    in
    ModuleResolver resolveType resolveValue

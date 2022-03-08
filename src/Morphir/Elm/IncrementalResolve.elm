module Morphir.Elm.IncrementalResolve exposing (..)

import Dict exposing (Dict)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Repo as Repo exposing (Repo)
import Set exposing (Set)


type Error
    = NoMorphirPackageFoundForElmModule (List String)
    | ModuleNotImported (List String)
    | ModuleOrAliasNotImported String
    | ModuleDoesNotExposeLocalName PackageName ModuleName Name KindOfName
    | ModulesDoNotExposeLocalName String (List QualifiedModuleName) Name KindOfName
    | MultipleModulesExposeLocalName (List QualifiedModuleName) Name KindOfName
    | LocalNameNotImported Name KindOfName


type KindOfName
    = Type
    | Ctor
    | Value


{-| Type that represents the combination of a package and a module name. It's called qualified module name because
module names are only unique within a package and to make them globally unique they need to be qualified with the
package name.
-}
type alias QualifiedModuleName =
    ( PackageName, ModuleName )


type alias ResolvedImports =
    { visibleNamesByModuleName : Dict QualifiedModuleName VisibleNames
    , moduleNamesByAliasOrSingleModuleName : Dict String (Set QualifiedModuleName)
    , moduleNamesByLocalName : Dict Name (Set QualifiedModuleName)
    }


type alias VisibleNames =
    { types : Set Name
    , ctors : Set Name
    , values : Set Name
    }


resolveImports : Repo -> List Import -> Result Error ResolvedImports
resolveImports repo imports =
    let
        -- Utility to update a Set value in a Dict
        insertOrCreate : comparable -> Maybe (Set comparable) -> Maybe (Set comparable)
        insertOrCreate item maybeSet =
            case maybeSet of
                Just set ->
                    set |> Set.insert item |> Just

                Nothing ->
                    Set.singleton item |> Just

        -- Add the alias if the import has one
        maybeAddAlias : Import -> QualifiedModuleName -> ResolvedImports -> ResolvedImports
        maybeAddAlias imp moduleName resolvedImports =
            case imp.moduleAlias of
                -- We are only matching on single word aliases because even though the Elm-syntax library
                -- returns a list here, Elm does not allow aliases with dots in it
                Just (Node _ [ alias ]) ->
                    { resolvedImports
                        | moduleNamesByAliasOrSingleModuleName =
                            resolvedImports.moduleNamesByAliasOrSingleModuleName
                                |> Dict.update alias (insertOrCreate moduleName)
                    }

                _ ->
                    resolvedImports

        -- Add module name from import if it's a single name module (like Dict or String)
        maybeAddModuleName : Import -> QualifiedModuleName -> ResolvedImports -> ResolvedImports
        maybeAddModuleName imp moduleName resolvedImports =
            case imp.moduleName of
                Node _ [ singleModuleName ] ->
                    { resolvedImports
                        | moduleNamesByAliasOrSingleModuleName =
                            resolvedImports.moduleNamesByAliasOrSingleModuleName
                                |> Dict.update singleModuleName (insertOrCreate moduleName)
                    }

                _ ->
                    resolvedImports

        addLocalNames : Import -> QualifiedModuleName -> ResolvedImports -> ResolvedImports
        addLocalNames imp moduleName resolvedImports =
            resolvedImports
    in
    imports
        |> List.foldl
            (\nextImport resolvedImportsSoFar ->
                nextImport.moduleName
                    |> Node.value
                    |> resolveModuleName repo
                    |> Result.andThen
                        (\moduleName ->
                            resolvedImportsSoFar
                                |> Result.map (maybeAddAlias nextImport moduleName)
                                |> Result.map (maybeAddModuleName nextImport moduleName)
                         --|> Result.map add
                        )
            )
            (Ok (ResolvedImports Dict.empty Dict.empty Dict.empty))


resolveModuleName : Repo -> List String -> Result Error QualifiedModuleName
resolveModuleName repo elmModuleName =
    let
        modulePath : Path
        modulePath =
            elmModuleName
                |> List.map Name.fromString

        visiblePackageNames : Set PackageName
        visiblePackageNames =
            Repo.dependsOnPackages repo
                |> Set.insert (Repo.getPackageName repo)

        findMatchingPackage : List PackageName -> Result Error QualifiedModuleName
        findMatchingPackage packageNames =
            case packageNames of
                [] ->
                    Err (NoMorphirPackageFoundForElmModule elmModuleName)

                nextPackage :: remainingPackages ->
                    if nextPackage |> Path.isPrefixOf modulePath then
                        Ok ( nextPackage, modulePath |> List.drop (List.length nextPackage) )

                    else
                        findMatchingPackage remainingPackages
    in
    findMatchingPackage (Set.toList visiblePackageNames)


resolveLocalName : Repo -> ModuleName -> VisibleNames -> ResolvedImports -> List String -> String -> KindOfName -> Result Error FQName
resolveLocalName repo currentModuleName localNames resolvedImports elmModuleName elmLocalName kindOfName =
    let
        localName : Name
        localName =
            Name.fromString elmLocalName
    in
    case elmModuleName of
        -- If there is no module prefix in the Elm code we need to search in the current module and all the imports
        [] ->
            -- First we check the local names
            if localNames |> isNameVisible localName kindOfName then
                Ok ( Repo.getPackageName repo, currentModuleName, localName )

            else
                -- If it's not a local name then we search through the imports
                resolvedImports.moduleNamesByLocalName
                    |> Dict.get localName
                    -- Report an error if the local name is not found
                    |> Result.fromMaybe (LocalNameNotImported localName kindOfName)
                    |> Result.andThen
                        (\moduleNames ->
                            case moduleNames |> Set.toList of
                                -- Report an error if the name is found but no corresponding modules are found
                                -- (which shouldn't happen if we did resolution cleanly)
                                [] ->
                                    Err (LocalNameNotImported localName kindOfName)

                                -- If there's exactly one module for this local name we return with it
                                [ ( packageName, moduleName ) ] ->
                                    Ok ( packageName, moduleName, localName )

                                -- If there's more than one module for this local name then the import is ambiguous
                                multipleModuleNames ->
                                    Err (MultipleModulesExposeLocalName multipleModuleNames localName kindOfName)
                        )

        -- If there is a module prefix with a single name then it could be a full module name or a module alias
        [ elmModuleOrAlias ] ->
            -- Look for single-name modules and aliases
            resolvedImports.moduleNamesByAliasOrSingleModuleName
                |> Dict.get elmModuleOrAlias
                -- If the module name or alias is not found immediately report as error
                |> Result.fromMaybe (ModuleOrAliasNotImported elmModuleOrAlias)
                -- Otherwise there might be multiple matches because Elm allows the same alias for multiple modules
                -- as long as the local names that you are looking for don't clash
                |> Result.andThen
                    (\matchingPackageAndModuleNames ->
                        let
                            -- Find all the module that import this specific local name
                            modulesThatContainLocalName : List QualifiedModuleName
                            modulesThatContainLocalName =
                                matchingPackageAndModuleNames
                                    |> Set.filter
                                        (\packageAndModuleName ->
                                            resolvedImports.visibleNamesByModuleName
                                                |> Dict.get packageAndModuleName
                                                |> Maybe.map (isNameVisible localName kindOfName)
                                                |> Maybe.withDefault False
                                        )
                                    |> Set.toList
                        in
                        case modulesThatContainLocalName of
                            -- If none of the identified modules contain the local name
                            [] ->
                                -- Report descriptive error depending on how many modules match the alias
                                case matchingPackageAndModuleNames |> Set.toList of
                                    [] ->
                                        Err (ModuleOrAliasNotImported elmModuleOrAlias)

                                    [ ( matchingPackageName, matchingModuleName ) ] ->
                                        Err (ModuleDoesNotExposeLocalName matchingPackageName matchingModuleName localName kindOfName)

                                    matchingModuleNames ->
                                        Err (ModulesDoNotExposeLocalName elmModuleOrAlias matchingModuleNames localName kindOfName)

                            -- If there's exactly one module that imports this local name we return that in the fully-qualified name
                            [ ( matchingPackageName, matchingModuleName ) ] ->
                                Ok ( matchingPackageName, matchingModuleName, localName )

                            -- If multiple modules import this name then we have an ambiguous reference and we should fail
                            _ ->
                                Err (MultipleModulesExposeLocalName modulesThatContainLocalName localName kindOfName)
                    )

        -- If the module prefix is a path it can only be a full module name (not an alias)
        _ ->
            -- Find out the Morphir package and module name of this Elm module
            resolveModuleName repo elmModuleName
                |> Result.andThen
                    (\(( packageName, moduleName ) as packageAndModuleName) ->
                        -- Find the imports for this module
                        resolvedImports.visibleNamesByModuleName
                            |> Dict.get packageAndModuleName
                            -- If it's not found the module is not imported at all
                            |> Result.fromMaybe (ModuleNotImported elmModuleName)
                            |> Result.andThen
                                (\moduleImports ->
                                    -- If the module is imported, check if the specific type is imported too
                                    if moduleImports |> isNameVisible localName kindOfName then
                                        Ok ( packageName, moduleName, localName )

                                    else
                                        Err (ModuleDoesNotExposeLocalName packageName moduleName localName kindOfName)
                                )
                    )


isNameVisible : Name -> KindOfName -> VisibleNames -> Bool
isNameVisible name kindOfName moduleImports =
    let
        setOfNames : Set Name
        setOfNames =
            case kindOfName of
                Type ->
                    moduleImports.types

                Ctor ->
                    moduleImports.ctors

                Value ->
                    moduleImports.values
    in
    setOfNames |> Set.member name

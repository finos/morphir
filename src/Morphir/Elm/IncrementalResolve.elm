module Morphir.Elm.IncrementalResolve exposing
    ( resolveModuleName, resolveImports, resolveLocalName, ResolvedImports, VisibleNames
    , Error(..)
    )

{-| This module contains functionality to resolve names in the Elm code into Morphir fully-qualified names. The process
is relatively complex due to the many ways names can be imported in an Elm module. Here, we split up the overall process
into three main steps following the structure of an Elm module:

@docs resolveModuleName, resolveImports, resolveLocalName, ResolvedImports, VisibleNames


# Errors

@docs Error

-}

import Dict exposing (Dict)
import Elm.Syntax.Exposing as Exposing
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range, emptyRange)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.KindOfName exposing (KindOfName(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.IR.Type as Type
import Set exposing (Set)


{-| Type that represents all the possible errors during the name resolution process. Here are the possible errors:

  - **NoMorphirPackageFoundForElmModule**
      - Reported during the process of mapping the Elm module name into a pair of Morphir package and module name.
      - Arguments: Elm module name
  - **ModuleNotImported**
      - Reported when the module that a name refers to is not mentioned in the imports
      - Arguments: Elm module name
  - **ModuleOrAliasNotImported**
      - Reported when a single name module prefix is not found in the imports. This could either refer to an alias or a
        top-level module but we don't know which one since it's not imported.
      - Arguments: Elm module name or alias
  - **ModuleDoesNotExposeLocalName**
      - Reported when we know which module a name is supposed to be in but that module does not expose or doesn't contain
        that name.
      - Arguments: package name, module name, local name, kind of name (type, constructor or value)
  - **ModulesDoNotExposeLocalName**
      - Reported when it's not clear which module should contain the local name but neither contains or exposes it.
      - Arguments: the alias that was used in the Elm code, matching module names, local name, kind of name (type, constructor or value)
  - **MultipleModulesExposeLocalName**
      - Reported when multiple modules expose the local name and it's unclear which one the user meant.
      - Arguments: matching module names, local name, kind of name (type, constructor or value)
  - **LocalNameNotImported**
      - Reported when a local name is not found in the imports.
      - Arguments: local name, kind of name (type, constructor or value)
  - **ImportedModuleNotFound**
      - Reported when a module is imported but not available in the Repo.
      - Arguments: package and module name
  - **ImportedLocalNameNotFound**
      - Reported when a local name is imported but not found in the Repo.
      - Arguments: package and module name, local name, kind of name (type, constructor or value)
  - **ImportingConstructorsOfNonCustomType**
      - Reported when an import is trying to expose constructors of a type but the type name does not refer to a custom type
      - Arguments: package and module name, local name

-}
type Error
    = NoMorphirPackageFoundForElmModule (List String)
    | ModuleNotImported (List String)
    | ModuleOrAliasNotImported String
    | ModuleDoesNotExposeLocalName PackageName ModuleName Name KindOfName
    | ModulesDoNotExposeLocalName String (List QualifiedModuleName) Name KindOfName
    | MultipleModulesExposeLocalName (List QualifiedModuleName) Name KindOfName
    | LocalNameNotImported Name KindOfName
    | ImportedModuleNotFound QualifiedModuleName
    | ImportedLocalNameNotFound QualifiedModuleName Name KindOfName
    | ImportingConstructorsOfNonCustomType QualifiedModuleName Name


{-| Type that represents the combination of a package and a module name. It's called qualified module name because
module names are only unique within a package and to make them globally unique they need to be qualified with the
package name.
-}
type alias QualifiedModuleName =
    ( PackageName, ModuleName )


{-| Internal data structure for efficient lookup of names based on imports.
-}
type alias ResolvedImports =
    { visibleNamesByModuleName : Dict QualifiedModuleName VisibleNames
    , moduleNamesByAliasOrSingleModuleName : Dict String (Set QualifiedModuleName)
    , moduleNamesByLocalTypeName : Dict Name (Set QualifiedModuleName)
    , moduleNamesByLocalValueName : Dict Name (Set QualifiedModuleName)
    , moduleNamesByLocalConstructorName : Dict Name (Set QualifiedModuleName)
    }


{-| Represents the names that a module exposes or makes internally available.
-}
type alias VisibleNames =
    { types : Set Name
    , constructors : Set Name
    , values : Set Name
    }


{-| Default imports implicitly included while processing Elm modules.
-}
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

        defaultBasicTypeImports =
            List.map
                en
                [ Exposing.TypeOrAliasExpose "Int"
                , Exposing.TypeOrAliasExpose "Float"
                , Exposing.TypeExpose (Exposing.ExposedType "Order" (Just er))
                , Exposing.TypeOrAliasExpose "Bool"
                , Exposing.TypeOrAliasExpose "Never"
                ]

        defaultBasicValueImports =
            List.map (Exposing.FunctionExpose >> en)
                [ "toFloat"
                , "round"
                , "floor"
                , "ceiling"
                , "truncate"
                , "max"
                , "min"
                , "compare"
                , "not"
                , "xor"
                , "modBy"
                , "remainderBy"
                , "negate"
                , "abs"
                , "clamp"
                , "sqrt"
                , "logBase"
                , "e"
                , "pi"
                , "cos"
                , "sin"
                , "tan"
                , "acos"
                , "asin"
                , "atan"
                , "atan2"
                , "degrees"
                , "radians"
                , "turns"
                , "toPolar"
                , "fromPolar"
                , "isNaN"
                , "isInfinite"
                , "identity"
                , "always"
                , "never"
                ]

        defaultBasicImports =
            defaultBasicTypeImports ++ defaultBasicValueImports
    in
    [ Import (en [ "Basics" ]) Nothing (Just (en (Exposing.Explicit defaultBasicImports)))
    , Import (en [ "List" ]) Nothing (Just (en (Exposing.Explicit [ en (Exposing.TypeOrAliasExpose "List") ])))
    , Import (en [ "Maybe" ]) Nothing (Just (en (Exposing.Explicit [ en (Exposing.TypeExpose (Exposing.ExposedType "Maybe" (Just er))) ])))
    , Import (en [ "Result" ]) Nothing (Just (en (Exposing.Explicit [ en (Exposing.TypeExpose (Exposing.ExposedType "Result" (Just er))) ])))
    , Import (en [ "String" ]) Nothing (Just (en (Exposing.Explicit [ en (Exposing.TypeOrAliasExpose "String") ])))
    , Import (en [ "Char" ]) Nothing (Just (en (Exposing.Explicit [ en (Exposing.TypeOrAliasExpose "Char") ])))
    , Import (en [ "Tuple" ]) Nothing Nothing
    ]


{-| Map elm/core modules to Morphir SDK modules.
-}
sdkModuleMapping : Dict (List String) (List String)
sdkModuleMapping =
    let
        morphirSdkPrefix : String -> ( List String, List String )
        morphirSdkPrefix elmModuleName =
            ( [ elmModuleName ], [ "Morphir", "SDK", elmModuleName ] )
    in
    Dict.fromList
        [ morphirSdkPrefix "Basics"
        , morphirSdkPrefix "List"
        , morphirSdkPrefix "Dict"
        , morphirSdkPrefix "Set"
        , morphirSdkPrefix "Maybe"
        , morphirSdkPrefix "Result"
        , morphirSdkPrefix "String"
        , morphirSdkPrefix "Char"
        , morphirSdkPrefix "Tuple"
        , morphirSdkPrefix "Regex"
        ]


mapImport : Import -> Import
mapImport imp =
    case sdkModuleMapping |> Dict.get (imp.moduleName |> Node.value) of
        Just sdkModuleName ->
            { imp
                | moduleName = imp.moduleName |> Node.map (always sdkModuleName)
                , moduleAlias = Just imp.moduleName
            }

        Nothing ->
            imp


{-| Resolve the imports into an internal data structure that makes it easier to resolve names within the module. This is
done once per module.
-}
resolveImports : Repo -> List Import -> Result Error ResolvedImports
resolveImports repo imports =
    let
        -- Add the alias if the import has one
        maybeAddAlias : Import -> QualifiedModuleName -> ResolvedImports -> ResolvedImports
        maybeAddAlias imp resolvedModuleName resolvedImports =
            case imp.moduleAlias of
                -- We are only matching on single word aliases because even though the Elm-syntax library
                -- returns a list here, Elm does not allow aliases with dots in it
                Just (Node _ [ alias ]) ->
                    { resolvedImports
                        | moduleNamesByAliasOrSingleModuleName =
                            resolvedImports.moduleNamesByAliasOrSingleModuleName
                                |> Dict.update alias (insertOrCreateSet resolvedModuleName)
                    }

                _ ->
                    resolvedImports

        -- Add module name from import if it's a single name module (like Dict or String)
        maybeAddModuleName : Import -> QualifiedModuleName -> ResolvedImports -> ResolvedImports
        maybeAddModuleName imp resolvedModuleName resolvedImports =
            case imp.moduleName of
                Node _ [ singleModuleName ] ->
                    { resolvedImports
                        | moduleNamesByAliasOrSingleModuleName =
                            resolvedImports.moduleNamesByAliasOrSingleModuleName
                                |> Dict.update singleModuleName (insertOrCreateSet resolvedModuleName)
                    }

                _ ->
                    resolvedImports

        moduleSpecToVisibleNames : Module.Specification () -> VisibleNames
        moduleSpecToVisibleNames moduleSpec =
            { types =
                moduleSpec.types |> Dict.keys |> Set.fromList
            , constructors =
                moduleSpec.types
                    |> Dict.toList
                    |> List.concatMap
                        (\( _, typeSpec ) ->
                            case typeSpec.value of
                                Type.CustomTypeSpecification _ constructors ->
                                    constructors |> Dict.keys

                                _ ->
                                    []
                        )
                    |> Set.fromList
            , values =
                moduleSpec.values |> Dict.keys |> Set.fromList
            }

        addModuleSpec : QualifiedModuleName -> Module.Specification () -> ResolvedImports -> ResolvedImports
        addModuleSpec qualifiedModuleName moduleSpec resolvedImports =
            { resolvedImports
                | visibleNamesByModuleName =
                    resolvedImports.visibleNamesByModuleName
                        |> Dict.update qualifiedModuleName (always (Just (moduleSpecToVisibleNames moduleSpec)))
            }

        addLocalName : KindOfName -> QualifiedModuleName -> Name -> ResolvedImports -> ResolvedImports
        addLocalName kindOfName qualifiedModuleName name resolvedImports =
            case kindOfName of
                Type ->
                    { resolvedImports
                        | visibleNamesByModuleName =
                            resolvedImports.visibleNamesByModuleName
                                |> Dict.update qualifiedModuleName (insertOrCreateVisibleNames kindOfName name)
                        , moduleNamesByLocalTypeName =
                            resolvedImports.moduleNamesByLocalTypeName
                                |> Dict.update name (insertOrCreateSet qualifiedModuleName)
                    }

                Constructor ->
                    { resolvedImports
                        | visibleNamesByModuleName =
                            resolvedImports.visibleNamesByModuleName
                                |> Dict.update qualifiedModuleName (insertOrCreateVisibleNames kindOfName name)
                        , moduleNamesByLocalConstructorName =
                            resolvedImports.moduleNamesByLocalConstructorName
                                |> Dict.update name (insertOrCreateSet qualifiedModuleName)
                    }

                Value ->
                    { resolvedImports
                        | visibleNamesByModuleName =
                            resolvedImports.visibleNamesByModuleName
                                |> Dict.update qualifiedModuleName (insertOrCreateVisibleNames kindOfName name)
                        , moduleNamesByLocalValueName =
                            resolvedImports.moduleNamesByLocalValueName
                                |> Dict.update name (insertOrCreateSet qualifiedModuleName)
                    }

        addLocalNames : Import -> QualifiedModuleName -> Module.Specification () -> ResolvedImports -> Result Error ResolvedImports
        addLocalNames imp qualifiedModuleName moduleSpec resolvedImports =
            case imp.exposingList of
                Just (Node _ exposingList) ->
                    case exposingList of
                        Exposing.All _ ->
                            let
                                addTypes : ResolvedImports -> ResolvedImports
                                addTypes resolved =
                                    moduleSpec.types
                                        |> Dict.keys
                                        |> List.foldl (addLocalName Type qualifiedModuleName) resolved

                                addCtors : ResolvedImports -> ResolvedImports
                                addCtors resolved =
                                    moduleSpec.types
                                        |> Dict.toList
                                        |> List.concatMap
                                            (\( typeName, documentedTypeSpec ) ->
                                                case documentedTypeSpec.value of
                                                    Type.TypeAliasSpecification _ (Type.Record _ _) ->
                                                        -- Record aliases define an implicit type constructor
                                                        [ typeName ]

                                                    Type.CustomTypeSpecification _ ctors ->
                                                        ctors |> Dict.keys

                                                    _ ->
                                                        []
                                            )
                                        |> List.foldl (addLocalName Constructor qualifiedModuleName) resolved

                                addValues : ResolvedImports -> ResolvedImports
                                addValues resolved =
                                    moduleSpec.values
                                        |> Dict.keys
                                        |> List.foldl (addLocalName Value qualifiedModuleName) resolved
                            in
                            resolvedImports
                                |> addTypes
                                |> addCtors
                                |> addValues
                                |> Ok

                        Exposing.Explicit explicitExposeNodes ->
                            explicitExposeNodes
                                |> List.foldl
                                    (\(Node _ explicitExpose) resolvedImportsSoFar ->
                                        let
                                            addTypeOrConstructor : Name -> Result Error ResolvedImports
                                            addTypeOrConstructor typeName =
                                                moduleSpec.types
                                                    |> Dict.get typeName
                                                    |> Result.fromMaybe (ImportedLocalNameNotFound qualifiedModuleName typeName Type)
                                                    |> Result.andThen
                                                        (\documentedTypeSpec ->
                                                            case documentedTypeSpec.value of
                                                                Type.TypeAliasSpecification _ (Type.Record _ _) ->
                                                                    -- Record aliases define an implicit type constructor
                                                                    resolvedImportsSoFar
                                                                        |> Result.map
                                                                            (\soFar ->
                                                                                soFar
                                                                                    |> addLocalName Type qualifiedModuleName typeName
                                                                                    |> addLocalName Constructor qualifiedModuleName typeName
                                                                            )

                                                                _ ->
                                                                    resolvedImportsSoFar |> Result.map (addLocalName Type qualifiedModuleName typeName)
                                                        )
                                        in
                                        case explicitExpose of
                                            Exposing.InfixExpose _ ->
                                                -- We ignore infix declarations
                                                resolvedImportsSoFar

                                            Exposing.FunctionExpose localName ->
                                                let
                                                    valueName : Name
                                                    valueName =
                                                        Name.fromString localName
                                                in
                                                if moduleSpec.values |> Dict.member valueName then
                                                    resolvedImportsSoFar |> Result.map (addLocalName Value qualifiedModuleName valueName)

                                                else
                                                    Err (ImportedLocalNameNotFound qualifiedModuleName valueName Value)

                                            Exposing.TypeOrAliasExpose localName ->
                                                let
                                                    typeName : Name
                                                    typeName =
                                                        Name.fromString localName
                                                in
                                                if moduleSpec.types |> Dict.member typeName then
                                                    addTypeOrConstructor typeName

                                                else
                                                    Err (ImportedLocalNameNotFound qualifiedModuleName typeName Type)

                                            Exposing.TypeExpose ctorExpose ->
                                                let
                                                    typeName : Name
                                                    typeName =
                                                        Name.fromString ctorExpose.name
                                                in
                                                case ctorExpose.open of
                                                    Just _ ->
                                                        moduleSpec.types
                                                            |> Dict.get typeName
                                                            |> Result.fromMaybe (ImportedLocalNameNotFound qualifiedModuleName typeName Type)
                                                            |> Result.andThen
                                                                (\documentedTypeSpec ->
                                                                    case documentedTypeSpec.value of
                                                                        Type.TypeAliasSpecification _ (Type.Record _ _) ->
                                                                            -- Record aliases define an implicit type constructor
                                                                            resolvedImportsSoFar
                                                                                |> Result.map
                                                                                    (\soFar ->
                                                                                        soFar |> addLocalName Constructor qualifiedModuleName typeName
                                                                                    )

                                                                        Type.CustomTypeSpecification _ ctors ->
                                                                            resolvedImportsSoFar
                                                                                |> Result.map
                                                                                    (\soFar ->
                                                                                        ctors
                                                                                            |> Dict.keys
                                                                                            |> List.foldl (addLocalName Constructor qualifiedModuleName)
                                                                                                (soFar |> addLocalName Type qualifiedModuleName typeName)
                                                                                    )

                                                                        _ ->
                                                                            Err (ImportingConstructorsOfNonCustomType qualifiedModuleName typeName)
                                                                )

                                                    Nothing ->
                                                        addTypeOrConstructor typeName
                                    )
                                    (Ok resolvedImports)

                Nothing ->
                    Ok resolvedImports
    in
    (defaultImports ++ imports)
        |> List.map mapImport
        |> List.foldl
            (\nextImport resolvedImportsSoFar ->
                nextImport.moduleName
                    |> Node.value
                    |> resolveModuleName repo
                    |> Result.andThen
                        (\(( packageName, moduleName ) as resolvedModuleName) ->
                            repo
                                |> Repo.lookupModuleSpecification packageName moduleName
                                |> Result.fromMaybe (ImportedModuleNotFound resolvedModuleName)
                                |> Result.andThen
                                    (\moduleSpec ->
                                        resolvedImportsSoFar
                                            |> Result.map (maybeAddAlias nextImport resolvedModuleName)
                                            |> Result.map (maybeAddModuleName nextImport resolvedModuleName)
                                            |> Result.map (addModuleSpec resolvedModuleName moduleSpec)
                                            |> Result.andThen (addLocalNames nextImport resolvedModuleName moduleSpec)
                                    )
                        )
            )
            (Ok (ResolvedImports Dict.empty Dict.empty Dict.empty Dict.empty Dict.empty))


{-| Finds out the Morphir package and module name from an Elm module name and a Repo.
-}
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


{-| Resolve each individual name using the data structure mentioned above. This is done for each type, constructor and
value name in the module.
-}
resolveLocalName : Repo -> ModuleName -> VisibleNames -> ResolvedImports -> List String -> KindOfName -> String -> Result Error FQName
resolveLocalName repo currentModuleName localNames resolvedImports elmModuleName kindOfName elmLocalName =
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
                let
                    moduleNamesByLocalName =
                        case kindOfName of
                            Type ->
                                resolvedImports.moduleNamesByLocalTypeName

                            Constructor ->
                                resolvedImports.moduleNamesByLocalConstructorName

                            Value ->
                                resolvedImports.moduleNamesByLocalValueName
                in
                -- If it's not a local name then we search through the imports
                moduleNamesByLocalName
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
                                        (\( matchingPackageName, matchingModuleName ) ->
                                            repo
                                                |> Repo.lookupModuleSpecification matchingPackageName matchingModuleName
                                                |> Maybe.map
                                                    (\moduleSpec ->
                                                        case kindOfName of
                                                            Type ->
                                                                moduleSpec.types |> Dict.member localName

                                                            Constructor ->
                                                                moduleSpec.types
                                                                    |> Dict.toList
                                                                    |> List.any
                                                                        (\( typeName, documentedTypeSpec ) ->
                                                                            case documentedTypeSpec.value of
                                                                                Type.TypeAliasSpecification _ (Type.Record _ _) ->
                                                                                    typeName == localName

                                                                                Type.CustomTypeSpecification _ ctors ->
                                                                                    ctors |> Dict.member localName

                                                                                _ ->
                                                                                    False
                                                                        )

                                                            Value ->
                                                                moduleSpec.values |> Dict.member localName
                                                    )
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
isNameVisible name kindOfName visibleNames =
    let
        setOfNames : Set Name
        setOfNames =
            case kindOfName of
                Type ->
                    visibleNames.types

                Constructor ->
                    visibleNames.constructors

                Value ->
                    visibleNames.values
    in
    setOfNames |> Set.member name


insertVisibleName : Name -> KindOfName -> VisibleNames -> VisibleNames
insertVisibleName name kindOfName visibleNames =
    case kindOfName of
        Type ->
            { visibleNames | types = visibleNames.types |> Set.insert name }

        Constructor ->
            { visibleNames | constructors = visibleNames.constructors |> Set.insert name }

        Value ->
            { visibleNames | values = visibleNames.values |> Set.insert name }


insertOrCreateVisibleNames : KindOfName -> Name -> Maybe VisibleNames -> Maybe VisibleNames
insertOrCreateVisibleNames kindOfName name maybeVisibleNames =
    case maybeVisibleNames of
        Just visibleNames ->
            insertVisibleName name kindOfName visibleNames |> Just

        Nothing ->
            { types = Set.empty, constructors = Set.empty, values = Set.empty } |> Just


{-| Utility to update a Set value in a dictionary.
-}
insertOrCreateSet : comparable -> Maybe (Set comparable) -> Maybe (Set comparable)
insertOrCreateSet item maybeSet =
    case maybeSet of
        Just set ->
            set |> Set.insert item |> Just

        Nothing ->
            Set.singleton item |> Just

module Morphir.TypeScript.Backend.TopLevelNamespace exposing (makeTopLevelNamespaceModule)

import Dict
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Type exposing (Type)
import Morphir.TypeScript.AST as TS
import Morphir.TypeScript.Backend.Imports exposing (getUniqueImportRefs, renderInternalImport)
import Morphir.TypeScript.Backend.Types exposing (mapPrivacy)


{-| Generate a TypeScript file for the package that includes each of its modules.
-}
makeTopLevelNamespaceModule : Package.PackageName -> Package.Definition ta (Type ()) -> TS.CompilationUnit
makeTopLevelNamespaceModule packagePath packageDef =
    let
        topLevelPackageName : String
        topLevelPackageName =
            case packagePath of
                firstName :: _ ->
                    (firstName |> Name.toTitleCase) ++ ".ts"

                _ ->
                    ".ts"

        typeDefs : List TS.TypeDef
        typeDefs =
            mapModuleNamespacesForTopLevelFile packagePath packageDef
    in
    { dirPath = []
    , fileName = topLevelPackageName
    , imports =
        typeDefs
            |> List.concatMap (getUniqueImportRefs [] [])
            |> List.map (renderInternalImport [])
    , typeDefs = typeDefs
    }


{-| Create an ImportAlias for each module inside the package.
-}
mapModuleNamespacesForTopLevelFile : Package.PackageName -> Package.Definition ta (Type ()) -> List TS.TypeDef
mapModuleNamespacesForTopLevelFile packagePath packageDef =
    let
        makeImportAlias : ( TS.Privacy, Module.ModuleName ) -> List TS.TypeDef
        makeImportAlias ( privacy, modulePath ) =
            case packagePath ++ modulePath |> List.reverse of
                [] ->
                    []

                lastName :: restOfPath ->
                    let
                        importAlias =
                            TS.ImportAlias
                                { name = lastName |> Name.toTitleCase
                                , privacy = privacy
                                , namespacePath = ( packagePath, modulePath )
                                }

                        step : Name -> TS.TypeDef -> TS.TypeDef
                        step name state =
                            TS.Namespace
                                { name = name |> Name.toTitleCase
                                , privacy = privacy
                                , content = List.singleton state
                                }
                    in
                    [ restOfPath |> List.foldl step importAlias ]
    in
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( modulePath, moduleImpl ) ->
                ( moduleImpl.access |> mapPrivacy
                , modulePath
                )
            )
        |> List.concatMap makeImportAlias
        |> mergeNamespaces


{-| Takes a list of TypeDefs, and returns an equivalent list where Namespaces
that have the same name are merged together.
-}
mergeNamespaces : List TS.TypeDef -> List TS.TypeDef
mergeNamespaces inputList =
    let
        {--Considers a TypeDef (needle) and a list of TypeDefs (haystack). Returns true
        if the needle is a Namespace, and the haystack contains another Namespace with
        the same name as the needle. Returns False otherwise --}
        hasMatch : TS.TypeDef -> List TS.TypeDef -> Bool
        hasMatch needle haystack =
            haystack
                |> List.any
                    (\candidate ->
                        case ( needle, candidate ) of
                            ( TS.Namespace ns1, TS.Namespace ns2 ) ->
                                ns1.name == ns2.name

                            _ ->
                                False
                    )

        {--Given two typedefs that are both NameSpaces, will merge them together if
        they have the same name. If they have different names or are not both namespaces,
        then the function simply outputs the second TypeDef
        --}
        conditionallyMergeTwoNamespaces : TS.TypeDef -> TS.TypeDef -> TS.TypeDef
        conditionallyMergeTwoNamespaces td1 td2 =
            case ( td1, td2 ) of
                ( TS.Namespace ns1, TS.Namespace ns2 ) ->
                    if ns1.name == ns2.name then
                        TS.Namespace
                            { name = ns2.name
                            , privacy =
                                if (ns1.privacy == TS.Public) || (ns2.privacy == TS.Public) then
                                    TS.Public

                                else
                                    TS.Private
                            , content = (ns2.content ++ ns1.content) |> mergeNamespaces
                            }

                    else
                        td2

                _ ->
                    td2

        {--Inserts a new typeDef into a list of TypeDefs
        If the new typeDef is a namespace, with the same name as an existing namespace
        that is in the list, then the two namespaces will be merged. Otherwise the new
        TypeDef is just appended to the list, --}
        insertNamespaceIntoList : TS.TypeDef -> List TS.TypeDef -> List TS.TypeDef
        insertNamespaceIntoList typeDef targetList =
            case ( typeDef, hasMatch typeDef targetList ) of
                ( TS.Namespace _, True ) ->
                    targetList |> List.map (conditionallyMergeTwoNamespaces typeDef)

                _ ->
                    targetList ++ [ typeDef ]
    in
    inputList |> List.foldl insertNamespaceIntoList []

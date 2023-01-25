module Morphir.Web.Graph.DependencyGraph exposing (..)

import Dict exposing (Dict)
import Element
    exposing
        ( Element
        , column
        , fill
        , height
        , html
        , scrollbars
        , width
        )
import Morphir.Dependency.DAG as DAG
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Web.Graph.Graph as Graph exposing (Graph)
import Set exposing (Set)


type alias SelectedModule =
    Maybe ( TreeLayout.NodePath ModuleName, ModuleName )


type alias Dependency =
    ( String, List String )


viewGraph : Graph -> Element msg
viewGraph graph =
    Graph.visGraph graph |> html


dependencyGraph : SelectedModule -> Repo -> Element msg
dependencyGraph selectedModule repo =
    let
        filterDepsBySelectedModule : DAG.DAG FQName -> Maybe ModuleName -> List Dependency
        filterDepsBySelectedModule deps moduleName =
            let
                createDependencyTuple : FQName -> Set FQName -> Dependency
                createDependencyTuple nodeName childNodeNames =
                    ( FQName.toString nodeName
                    , Set.map FQName.toString childNodeNames
                        |> Set.toList
                    )
            in
            case moduleName of
                Just justmn ->
                    deps
                        |> DAG.toList
                        |> List.filterMap
                            (\( ( _, mn, _ ) as fqName, fqNameSet ) ->
                                if justmn == mn then
                                    Just (createDependencyTuple fqName fqNameSet)

                                else
                                    Nothing
                            )

                Nothing ->
                    deps
                        |> DAG.toList
                        |> List.map
                            (\( fqName, fqNameSet ) ->
                                createDependencyTuple fqName fqNameSet
                            )

        filterTypeDeps : Maybe ModuleName -> List Dependency
        filterTypeDeps =
            filterDepsBySelectedModule (Repo.typeDependencies repo)

        filterValueDeps : Maybe ModuleName -> List Dependency
        filterValueDeps =
            filterDepsBySelectedModule (Repo.valueDependencies repo)

        createGraph : List Dependency -> Element msg
        createGraph =
            Graph.dagListAsGraph >> viewGraph

        mapModulesToGraph : ModuleName -> (Maybe ModuleName -> List Dependency) -> Element msg
        mapModulesToGraph parentModuleName mapping =
            let
                (Library _ _ packageDef) =
                    repo |> Repo.toDistribution

                leafModules : ModuleName -> List ModuleName
                leafModules moduleName =
                    packageDef.modules |> Dict.keys |> List.filter (\l -> List.concat l |> String.join "." |> String.startsWith (List.concat moduleName |> String.join "."))
            in
            leafModules parentModuleName
                |> List.map
                    (\mn ->
                        mapping <| Just mn
                    )
                |> List.foldr (++) []
                |> createGraph
    in
    column [ width fill, height fill, scrollbars ]
        (case selectedModule of
            Just ( _, moduelName ) ->
                [ mapModulesToGraph moduelName filterTypeDeps
                , mapModulesToGraph moduelName filterValueDeps
                ]

            Nothing ->
                [ filterTypeDeps Nothing |> createGraph, filterValueDeps Nothing |> createGraph ]
        )

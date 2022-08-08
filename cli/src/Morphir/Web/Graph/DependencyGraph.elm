module Morphir.Web.Graph.DependencyGraph exposing (..)

import Element
    exposing
        ( Element
        , column
        , fill
        , fillPortion
        , height
        , html
        , rgb
        , scrollbars
        , width
        )
import Element.Border as Border
import Morphir.Dependency.DAG as DAG
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Repo as Repo exposing (Repo)
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Web.Graph.Graph as Graph exposing (Edge, Graph, Node)
import Set exposing (Set)


type alias SelectedModule =
    Maybe ( TreeLayout.NodePath ModuleName, ModuleName )


viewGraph : Graph -> Element msg
viewGraph graph =
    Graph.visGraph graph |> html


dependencyGraph : SelectedModule -> Repo -> Element msg
dependencyGraph selectedModule repo =
    let
        gray =
            rgb 0.9 0.9 0.9

        filterDepsBySelectedModule : DAG.DAG FQName -> List ( String, List String )
        filterDepsBySelectedModule deps =
            deps
                |> DAG.toList
                |> List.filterMap
                    (\( ( _, moduleName, _ ) as fqName, fqNameSet ) ->
                        case selectedModule of
                            Just ( _, selectedModName ) ->
                                if selectedModName == moduleName then
                                    Just
                                        ( FQName.toString fqName
                                        , Set.map FQName.toString fqNameSet
                                            |> Set.toList
                                        )

                                else
                                    Nothing

                            Nothing ->
                                Just
                                    ( FQName.toString fqName
                                    , Set.map FQName.toString fqNameSet
                                        |> Set.toList
                                    )
                    )

        filterTypeDeps =
            filterDepsBySelectedModule (Repo.typeDependencies repo)

        filterValueDeps =
            filterDepsBySelectedModule (Repo.valueDependencies repo)
    in
    column [ width fill, height (fillPortion 3), Border.widthXY 0 8, Border.color gray, scrollbars ]
        [ viewGraph (Graph.dagListAsGraph filterTypeDeps)
        , viewGraph (Graph.dagListAsGraph filterValueDeps)
        ]

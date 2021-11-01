module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
import Dict
import Element exposing (Element, column, el, fill, layout, none, padding, paddingEach, px, row, shrink, spacing, table, text)
import Html.Styled.Attributes exposing (css)
import Html
import Html.Styled exposing (Html, div, fromUnstyled, map, toUnstyled)
import Css exposing (auto, px, width)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Tree as Tree
import TreeView as TreeView
import Mwc.Button
import Mwc.TextField

--main : Html Msg
--main =
--    -- minimalistic example
--    -- need an update function
--    --let
--    --    cara : Element Msg
--    --    cara =
--    --        text "Cara"
--    --in arrowHelper labels (Element.text "cara")
--    layout
--        []
--        <|
--
--        (el [ padding 10 ]
--
--            (column [ spacing 20 ]
--             -- column layout and spacing between layout
--                (examples
--                -- pipe to make it the last function
--                -- collection is always last argument
--                    |> List.indexedMap
--                    -- takes a list and returns another lsit --> in real world we would probably be okay with .map
--                        (\index example ->
--                            column [ spacing 10 ]
--                                [ text ("Example " ++ String.fromInt (index + 1))
--                                , column [ spacing 5 ] (viewNode 0 Nothing example)
--                                ]
--                        )
--                )
--            )
--        )

type alias NodeData = {
    uid : String
    , label : String }

nodeLabel : Tree.Node NodeData -> String
nodeLabel n =
    case n of
        Tree.Node node -> node.data.label

nodeUid : Tree.Node NodeData -> TreeView.NodeUid String
nodeUid n =
    case n of
        Tree.Node node -> TreeView.NodeUid node.data.uid

initialModel : () -> (Model, Cmd Msg)
initialModel () =
    let
        rootNodes =
            [ Tree.Node
                { children =
                    [ Tree.Node { children = [], data = NodeData "1.1" "yes"}
                    , Tree.Node { children = [], data = NodeData "1.2" "no"} ],
                    data = NodeData "1" "isFoo"
                }
            , Tree.Node
                { children =
                    [ Tree.Node
                    {
                    children = [ Tree.Node
                                { children = [], data = NodeData "2.1.1" "yesandyes" },
                                Tree.Node
                                { children = [], data = NodeData "2.1.2" "yesandno"} ]
                    ,
                    data = NodeData "2.1" "isBar"},
                     Tree.Node
                     {
                     children = [],
                     data = NodeData "2.2" "No" }
                     ]

                , data = NodeData "2" "isFoo" }
            ]
    in
        ( { rootNodes = rootNodes
        , treeModel = TreeView.initializeModel configuration rootNodes
        , selectedNode = Nothing
        }
        , Cmd.none
        )

type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String Never ()
    , selectedNode : Maybe NodeData
    }

configuration : TreeView.Configuration NodeData String
configuration =
    TreeView.Configuration nodeUid nodeLabel TreeView.defaultCssClasses

type Msg =
  TreeViewMsg (TreeView.Msg String)
  | ExpandAll
  | CollapseAll


update : Msg -> Model -> (Model, Cmd Msg)
update message model =
    let
        treeModel =
            case message of
                TreeViewMsg tvMsg ->
                    TreeView.update tvMsg model.treeModel
                ExpandAll ->
                    TreeView.expandAll model.treeModel
                CollapseAll ->
                    TreeView.collapseAll model.treeModel
    in
        ( { model
        | treeModel = treeModel
        , selectedNode = TreeView.getSelected treeModel |> Maybe.map .node |> Maybe.map Tree.dataOf
        }, Cmd.none )

expandAllCollapseAllButtons : Html Msg
expandAllCollapseAllButtons =
    div
      []
      [ Mwc.Button.view
          [ Mwc.Button.raised
          , Mwc.Button.onClick ExpandAll
          , Mwc.Button.label "Expand all"
          ]
      , Mwc.Button.view
          [ Mwc.Button.raised
          , Mwc.Button.onClick CollapseAll
          , Mwc.Button.label "Collapse all"
          ]
      ]

selectedNodeDetails : Model -> Html Msg
selectedNodeDetails model =
    let
        selectedDetails =
            Maybe.map (\nodeData -> nodeData.uid ++ ": " ++ nodeData.label) model.selectedNode
                |> Maybe.withDefault "(nothing selected)"
    in
        div
            [ css [ width (auto) ] ]
            [ Mwc.TextField.view
                [ Mwc.TextField.readonly True
                , Mwc.TextField.label selectedDetails
                ]
            ]

view : Model -> Html Msg
view model =
        div
            [ css [width (auto)]]
            [ expandAllCollapseAllButtons
            , selectedNodeDetails model
            , map TreeViewMsg (TreeView.view model.treeModel |> fromUnstyled)
            ]



subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)



main =
    Browser.element
        {
        init = initialModel,
        view = view >> toUnstyled,
        update = update,
        subscriptions = subscriptions
        }

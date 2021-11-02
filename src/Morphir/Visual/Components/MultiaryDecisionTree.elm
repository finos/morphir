module Morphir.Visual.Components.MultiaryDecisionTree exposing (..)



import Browser
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Html.Styled.Attributes exposing (css)

import Html.Styled exposing (Html, div, fromUnstyled, map, toUnstyled)
import Css exposing (auto, px, width)
import Morphir.Visual.ViewPattern as ViewPattern

import Morphir.IR.Value as Value
import Tree as Tree
import TreeView as TreeView
import Mwc.Button
import Mwc.TextField
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
---
import Element exposing (Element)
import List exposing (map)
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.IR.Value exposing (RawValue)
import Morphir.Visual.Components.DecisionTree exposing (BranchNode)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)

----
-- define data type for values we put into tree node
type alias NodeData = {
    uid : String
    , subject : String
    , pattern : Maybe (Pattern())
    }

--getPattern : ( a, b ) -> a
----- some method for getting pattern from list
--
--getNode : ( a, b ) -> b
----- some method for getting pattern from list


getLabel : Maybe (Pattern()) -> String
getLabel maybeLabel =
    case maybeLabel of
        Just label -> ViewPattern.patternAsText(label) ++ "  ->  "
        Nothing -> ""


-- ViewPattern.patternAsText(node.data.pattern) ++ "->" ++ node.data.subject
-- define a function to calculate the text representation of a node
nodeLabel : Tree.Node NodeData -> String
nodeLabel n =
    case n of
       Tree.Node node -> getLabel(node.data.pattern) ++ node.data.subject

-- define another function to calculate the uid of a node
nodeUid : Tree.Node NodeData -> TreeView.NodeUid String
nodeUid n =
    case n of
        Tree.Node node -> TreeView.NodeUid node.data.uid

-- initialize the TreeView model
type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String Never ()
    , selectedNode : Maybe NodeData
    }

--construct a configuration for your tree view
configuration : TreeView.Configuration NodeData String
configuration =
    TreeView.Configuration nodeUid nodeLabel TreeView.defaultCssClasses


-- otherwise interact with your tree view in the usual TEA manner
type Msg =
  TreeViewMsg (TreeView.Msg String)
  | ExpandAll
  | CollapseAll

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
            Maybe.map (\nodeData -> nodeData.uid ++ ": " ++ nodeData.subject) model.selectedNode
                |> Maybe.withDefault "(nothing selected)"
    in
        div
            [ css [ width (auto) ] ]
            [ Mwc.TextField.view
                [ Mwc.TextField.readonly True
                , Mwc.TextField.label selectedDetails
                ]
            ]





    --Browser.element
    --    {
    --    init = initialModel,
    --    view = view >> toUnstyled,
    --    update = update,
    --    subscriptions = subscriptions
    --    }



-- folding or reducing
-- fold left --> more efficient
-- value thus far and new element
--displayList : Config msg -> (Config msg -> VisualTypedValue -> Element msg) -> BranchNode -> List (Element msg)
--displayList config viewValue root =
    -- somehow iteratively call listHelp
    -- listHelp config viewValue root.branches[0]
   --- listHelp config viewValue root.branches


--listHelp : Config msg -> (Config msg -> VisualTypedValue -> Element msg) -> ( Pattern(), Node ) -> List(Element msg)
--listHelp config viewValue (pattern, node) =
    -- let , in :: to get these values
    -- get pattern as its own variable
    -- get node as its own variable

    -- case match to see if its a branch or a leaf
    -- case rootNode of
           -- Branch branch ->
           -- within branch we want to display the



--
--
---- ( List.map (\x -> layoutHelp config viewValue x) branch.branches )
--
--
--[
--(COND 1, NODE 1),
--(COND 2, NODE 2)
--]
--
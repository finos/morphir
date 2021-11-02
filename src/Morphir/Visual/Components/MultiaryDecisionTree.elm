module Morphir.Visual.Components.MultiaryDecisionTree exposing (..)



import Element exposing (Element)
import List exposing (map)
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.IR.Value exposing (RawValue)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
type Node
    = Branch BranchNode
    | Leaf VisualTypedValue

type alias BranchNode =
    { subject : VisualTypedValue
      , subjectEvaluationResult : Maybe RawValue
      , branches : List ( Pattern(), Node )
    }
-- Created
--layout : Config msg -> (VisualTypedValue -> Element msg) -> Node -> Element msg
--layout config viewValue rootNode =
--    layoutHelp config NotHighlighted viewValue rootNode


type HighlightState
    = Highlighted RawValue
    | NotHighlighted
--getPattern : ( a, b ) -> a
----- some method for getting pattern from list
--
--getNode : ( a, b ) -> b
----- some method for getting pattern from list


-- folding or reducing
-- fold left --> more efficient
-- value thus far and new element
--displayList : Config msg -> (Config msg -> VisualTypedValue -> Element msg) -> BranchNode -> Element msg
--displaylist config viewValue root =
--    -- somehow iteratively call listHelp
--    -- listHelp config viewValue root.branches[0]
--    listHelp config viewValue (root
--
--
--listHelp : Config msg -> (Config msg -> VisualTypedValue -> Element msg) -> ( Pattern(), Node ) -> Element msg
--listHelp config viewValue (pattern, node) =
--    -- let , in :: to get these values
--    -- get pattern as its own variable
--    -- get node as its own variable
--
--    -- case match to see if its a branch or a leaf
--    -- case rootNode of
--           -- Branch branch ->
--           -- within branch we want to display the
--
--
--
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
--

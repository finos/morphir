module Morphir.Visual.ViewMultiaryDecisionTree exposing (..)

--import Dict exposing (Dict)
--import Element exposing (Element)
--import Morphir.IR.Literal exposing (Literal(..))
--import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value, toRawValue)
--import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (Node)
--
--import Morphir.Visual.Config as Config exposing (Config)
--import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
--
--
import Browser
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Html.Styled.Attributes exposing (css)

import Html.Styled exposing (Html, div, fromUnstyled, map, toUnstyled)
import Css exposing (auto, px, width)
import Morphir.Visual.Components.DecisionTree exposing (Node(..))
import Morphir.Visual.ViewPattern as ViewPattern

import Morphir.IR.Value as Value
import Tree as Tree exposing (Node(..))
import TreeView as TreeView

import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.IR.Value exposing (RawValue)
import Mwc.Button
import Mwc.TextField
import Element exposing (Element)
import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (Model, Msg(..), NodeData, configuration, expandAllCollapseAllButtons, selectedNodeDetails)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)

-- For If then Else
-- Construct my own Tree that includes pattern matching and ifthenelse
-- Config -> ViewValue -> Value -> Element Msg
-- layoutHelp : Config msg -> (VisualTypedValue -> Element msg) -> Tree.Node {} -> Element msg
-- layoutHelp config viewValue rootNode =
--    let
--        depthOf : (BranchNode -> Node) -> Node -> Int
--        depthOf f node =
--            case node of

--layoutHelp : Config msg -> (VisualTypedValue -> Element msg) -> (VisualTypedValue -> Element msg) -> Node -> Element msg
--layoutHelp config highlightState viewValue rootNode =
--    let
--        depthOf : Tree.Node n  -> Int
--        depthOf n =
--            case n of
--                Tree.Node branch ->
--                     (branch) + 1
--                _ -> 1
--    in
--    case rootNode of
--        Tree.Node n ->

-- Config -> Bool -> VisualTypedValue -> MultiaryDecisionTree.Node


initialModel : () -> (Model, Cmd Msg)
initialModel () =
    let
        rootNodes =
            [ Tree.Node
                { children =
                    [ Tree.Node { children = [], data = NodeData "1.1" "Yes" (Just (Value.LiteralPattern () (BoolLiteral True)))}
                    , Tree.Node { children = [], data = NodeData "1.2" "No" (Just (Value.LiteralPattern () (BoolLiteral False)))} ],
                    data = NodeData "1" "isFoo" Nothing
                }
            , Tree.Node
                { children =
                    [ Tree.Node
                    {
                    children = [ Tree.Node
                                { children = [], data = NodeData "2.1.1" "YesAndYes"  (Just( Value.LiteralPattern () (BoolLiteral True))) },
                                Tree.Node
                                { children = [], data = NodeData "2.1.2" "YesAndNo"  (Just( Value.LiteralPattern () (BoolLiteral True)))} ]
                    ,
                    data = NodeData "2.1" "isBar"  (Just( Value.LiteralPattern () (BoolLiteral True)))},
                     Tree.Node
                     {
                     children = [],
                     data = NodeData "2.2" "No"  (Just ( Value.LiteralPattern () (BoolLiteral False)))}
                     ]

                , data = NodeData "2" "isFoo" Nothing
                }
              , Tree.Node
                { children = [
                Tree.Node {
                    children = [],
                    data = NodeData "3.1" "foo" (Just ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") []))
                    },
                Tree.Node {
                    children = [],
                    data = NodeData "3.2" "bar" (Just ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") []))
                    },
                Tree.Node {
                    children = [],
                    data = NodeData "3.3" "baz" (Just ( Value.WildcardPattern ()))
                    }
                ],
                data = NodeData "3" "enum" Nothing

                }
            ]
    in
        ( { rootNodes = rootNodes
        , treeModel = TreeView.initializeModel configuration rootNodes
        , selectedNode = Nothing
        }
        , Cmd.none
        )

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


-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)

-- avilitiy to view tree
view : Model -> Html Msg
view model =
        div
            [ css [width (auto)]]
            [ expandAllCollapseAllButtons
            ,selectedNodeDetails model
            , map TreeViewMsg (TreeView.view model.treeModel |> fromUnstyled)
            ]
dog =
    Element.layout

--
--display : config
--
--

main =
    Browser.element
        {
        init = initialModel,
        view = view >> toUnstyled,
        update = update,
        subscriptions = subscriptions
        }

--valueToTree : Config msg -> Bool -> VisualTypedValue -> MultiaryDecisionTree.Node
--valueToTree config doEval value =
--    case value of
--        Value.IfThenElse _ condition thenBranch elseBranch ->
--            let
--                result =
--                    if doEval then
--                        case config |> Config.evaluate (Value.toRawValue condition) of
--                            Ok(Value.Literal _ (BoolLiteral v)) ->
--                                Just v
--                            _ -> Nothing
--                    else
--                        Nothing
--            in
--                MultiaryDecisionTree.Branch
--                { subject = condition
--                , subjectEvaluationResult = result
--                , branches = valueToTree config (result == Just True) thenBranch
--                }
--        Value.LetDefinition _ defName defValue inValue ->
--            let
--                currentState =
--                    config.state
--                newState =
--                    { currentState
--                        | variables =
--                            config
--                                |> Config.evaluate
--                                    (defValue
--                                             |> Value.mapDefinitionAttributes identity (always ())
--                                             |> Value.definitionToValue
--                                         )
--                                |> Result.map
--                                     (\evaluatedDefValue ->
--                                         currentState.variables
--                                             |> Dict.insert defName evaluatedDefValue
--                                     )
--                                |> Result.withDefault currentState.variables
--
--                    }
--            in
--                valueToTree
--                    { config
--                        | state = newState
--                    }
--                    doEval
--                    inValue
--        _ ->  MultiaryDecisionTree.Leaf value}
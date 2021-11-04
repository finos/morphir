module Morphir.Visual.ViewMultiaryDecisionTree exposing (main)

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
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Html.Styled.Attributes exposing (css)

import Html.Styled exposing (Html, div, fromUnstyled, map, toUnstyled)
import Css exposing (auto, px, width)
import Morphir.Visual.ViewPattern as ViewPattern

import Morphir.IR.Value as Value
import Tree as Tree
import TreeView as TreeView

import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value)
import Morphir.IR.Value exposing (RawValue)
import Mwc.Button
import Mwc.TextField
import Element exposing (Element, rgb)
import Morphir.Visual.Components.MultiaryDecisionTree as MultiaryDecisionTree exposing (Model, Msg(..), NodeData, configuration, expandAllCollapseAllButtons, selectedNodeDetails)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
--view : Config msg -> (VisualTypedValue -> Element msg) -> VisualTypedValue -> Element msg
--view config viewValue value =
--     MultiaryDecisionTree.main


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

-- map messages from tree view
-- both element and html have map --> map would invoke constructor --> specify name html.map --> internally call constructor
-- in view
-- Element.html

-- avilitiy to view tree
view : Model -> Html Msg
view model =
        div
            [ css [width (auto)]]
            [ expandAllCollapseAllButtons
            ,selectedNodeDetails model
            , map TreeViewMsg (TreeView.view model.treeModel |> fromUnstyled)
            ]

---- BLOCKER : tree view returns HTML vs Element msg

--dog : Element msg
--dog =
--    Element.el
--        [ Background.color (rgb 0 0.5 0)
--        , Border.color (rgb 0 0.7 0)
--
--        ]
        --(Element.text)



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
-- eventually extend update function to functionpage/modulepage/etc
-- update function can be called by the other update functions
-- new code that handles treeview wrapper
-- call existing function passing in state of tree and the msg

-- multiple isntances of treeview in developapp --> state of tree should be tied to ir
--
--valueToTree : Config msg -> Bool -> VisualTypedValue -> MultiaryDecisionTree.Node
--valueToTree config doEval value =
--    case value of
--        Value.IfThenElse _ condition thenBranch elseBranch ->
--            let
--                result =
--                    if doEval then
--                        case config |> Config.evaluate (Value.toRawValue condition) of
--                            Ok (Value.Literal _ (BoolLiteral v)) ->
--                                Value.toRawValue v
--
--                            _ ->
--                                Nothing
--
--                    else
--                        Nothing
--                --mybranches : List (Node)
--                --mybranches =
--                --   [ valueToTree config (result == Just True) thenBranch ]
--                --thenBranch = valueToTree config (result == Just True) thenBranch
--                --elseBranch = valueToTree config (result == Just False) elseBranch
--                --
--            in
--            MultiaryDecisionTree.Branch
--                { subject = condition
--                , subjectEvaluationResult = result
--                , branches = valueToTree config (result == Just True) thenBranch
--                }
--
--        Value.LetDefinition _ defName defValue inValue ->
--            let
--                currentState =
--                    config.state
--
--                newState =
--                    { currentState
--                        | variables =
--                            config
--                                |> Config.evaluate
--                                    (defValue
--                                        |> Value.mapDefinitionAttributes identity (always ())
--                                        |> Value.definitionToValue
--                                    )
--                                |> Result.map
--                                    (\evaluatedDefValue ->
--                                        currentState.variables
--                                            |> Dict.insert defName evaluatedDefValue
--                                    )
--                                |> Result.withDefault currentState.variables
--                    }
--            in
--            valueToTree
--                { config
--                    | state = newState
--                }
--                doEval
--                inValue
--
--        _ ->
--            MultiaryDecisionTree.Leaf value

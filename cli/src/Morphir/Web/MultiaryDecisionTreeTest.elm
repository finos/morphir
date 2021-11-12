module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
import Dict exposing (Dict, values)
import Element exposing (Color, Element, rgb)
import Html exposing (Html, button, label, map, option, select)
import Html.Attributes as Html exposing (class, disabled, for, id, selected, value)
import Html.Events exposing (onClick, onInput)
import List exposing (drop, head, tail, take)
import Maybe exposing (withDefault)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Value as Value exposing (Pattern(..), RawValue, Value(..))
import Morphir.Value.Interpreter as Interpreter
import Morphir.Visual.ViewPattern as ViewPattern
import String exposing (fromInt, join, split)
import Tree as Tree
import TreeView as TreeView
import Tuple


t =
    Element.text



-- Data type to represent condition and pattern of each node.


type alias NodeData =
    { uid : String
    , subject : String
    , pattern : Maybe (Pattern ())
    , highlight : Bool
    }



-- Styling visual representation of a Pattern


getLabel : Maybe (Pattern ()) -> String
getLabel maybeLabel =
    case maybeLabel of
        Just label ->
            ViewPattern.patternAsText label ++ " - "

        Nothing ->
            ""



-- Evaluates node and pattern based on whether or not it is within variables which is passed from the dropdowns


evaluateHighlight : Dict Name (Value () ()) -> String -> Pattern () -> Bool
evaluateHighlight variables value pattern =
    let
        evaluation : Maybe.Maybe RawValue
        evaluation =
            variables |> Dict.get (Name.fromString value)
    in
    case evaluation of
        Just val ->
            case Interpreter.matchPattern pattern val of
                Ok _ ->
                    True

                Err _ ->
                    False

        Nothing ->
            False



-- Text representation of a node


nodeLabel : Tree.Node NodeData -> String
nodeLabel n =
    case n of
        Tree.Node node ->
            getLabel node.data.pattern ++ node.data.subject



-- Takes IR and creates a tree of nodes
-- call list to node every time we call the tree model


initialModel : () -> ( Model, Cmd Msg )
initialModel () =
    let
        originalIR =
            Value.patternMatch ()
                (Value.Variable () (Name.fromString "Classify By Position Type"))
                [ ( Value.LiteralPattern () (StringLiteral "Cash")
                  , Value.IfThenElse ()
                        (Value.Variable () (Name.fromString "Is Central Bank"))
                        (Value.IfThenElse ()
                            (Value.Variable () (Name.fromString "Is Segregated Cash"))
                            (Value.PatternMatch ()
                                (Value.Variable () (Name.fromString "Classify By Counter Party ID"))
                                [ ( Value.LiteralPattern () (StringLiteral "FRD"), Value.Variable () [ "1.A.4.1" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOE"), Value.Variable () [ "1.A.4.2" ] )
                                , ( Value.LiteralPattern () (StringLiteral "SNB"), Value.Variable () [ "1.A.4.3" ] )
                                , ( Value.LiteralPattern () (StringLiteral "ECB"), Value.Variable () [ "1.A.4.4" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOI"), Value.Variable () [ "1.A.4.5" ] )
                                , ( Value.LiteralPattern () (StringLiteral "RBA"), Value.Variable () [ "1.A.4.6" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOC"), Value.Variable () [ "1.A.4.7" ] )
                                , ( Value.LiteralPattern () (StringLiteral "Others"), Value.Variable () [ "1.A.4.8" ] )
                                ]
                            )
                            (Value.PatternMatch ()
                                (Value.Variable () (Name.fromString "Classify By Counter Party ID"))
                                [ ( Value.LiteralPattern () (StringLiteral "FRD"), Value.Variable () [ "1.A.3.1" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOE"), Value.Variable () [ "1.A.3.2" ] )
                                , ( Value.LiteralPattern () (StringLiteral "SNB"), Value.Variable () [ "1.A.3.3" ] )
                                , ( Value.LiteralPattern () (StringLiteral "ECB"), Value.Variable () [ "1.A.3.4" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOI"), Value.Variable () [ "1.A.3.5" ] )
                                , ( Value.LiteralPattern () (StringLiteral "RBA"), Value.Variable () [ "1.A.3.6" ] )
                                , ( Value.LiteralPattern () (StringLiteral "BOC"), Value.Variable () [ "1.A.3.7" ] )
                                , ( Value.LiteralPattern () (StringLiteral "Others"), Value.Variable () [ "1.A.3.8" ] )
                                ]
                            )
                        )
                        (Value.IfThenElse ()
                            (Value.Variable () (Name.fromString "Is On Shore"))
                            (Value.IfThenElse ()
                                (Value.Variable () (Name.fromString "Is NetUsd Amount Negative"))
                                (Value.Variable () (Name.fromString "O.W.9"))
                                (Value.IfThenElse ()
                                    (Value.Variable () (Name.fromString "Is Feed44 and CostCenter Not 5C55"))
                                    (Value.Variable () (Name.fromString "1.U.1"))
                                    (Value.Variable () (Name.fromString "1.U.4"))
                                )
                            )
                            (Value.IfThenElse ()
                                (Value.Variable () (Name.fromString "Is NetUsd Amount Negative"))
                                (Value.Variable () (Name.fromString "O.W.10"))
                                --
                                (Value.IfThenElse ()
                                    (Value.Variable () (Name.fromString "Is Feed44 and CostCenter Not 5C55"))
                                    (Value.Variable () (Name.fromString "1.U.2"))
                                    (Value.Variable () (Name.fromString "1.U.4"))
                                )
                             --
                            )
                        )
                  )
                , ( Value.LiteralPattern () (StringLiteral "Inventory"), Value.Unit () )
                , ( Value.LiteralPattern () (StringLiteral "Pending Trades"), Value.Unit () )
                ]
    in
    ( { rootNodes = listToNode [ originalIR ] Dict.empty
      , dict = Dict.empty
      , treeModel = TreeView.initializeModel2 configuration (listToNode [ originalIR ] Dict.empty)
      , selectedNode = Nothing
      , originalIR = originalIR
      }
    , Cmd.none
    )


type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String NodeDataMsg (Maybe NodeData)
    , selectedNode : Maybe NodeData
    , dict : Dict String String
    , originalIR : Value () ()
    }



-- Gets unique ID of Node.


nodeUidOf : Tree.Node NodeData -> TreeView.NodeUid String
nodeUidOf n =
    case n of
        Tree.Node node ->
            TreeView.NodeUid node.data.uid



--construct a configuration for your tree view


configuration : TreeView.Configuration2 NodeData String NodeDataMsg (Maybe NodeData)
configuration =
    TreeView.Configuration2 nodeUidOf viewNodeData TreeView.defaultCssClasses


type Msg
    = TreeViewMsg (TreeView.Msg2 String NodeDataMsg)
    | SetDictValueRoot String
    | SetDictValueBank String
    | SetDictValueSegCash String
    | SetDictValueCode String
    | SetDictValueShore String
    | SetDictValueNegative String
    | SetDictValueFeed String
    | RedoTree



-- Updates the tree as drop downs are selected


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        SetDictValueRoot s1 ->
            let
                newDict1 =
                    Dict.insert "classifyByPositionType" s1 Dict.empty
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueBank s1 ->
            --should unset everything except for classifyByPositionType
            let
                newDict1 =
                    Dict.insert "classifyByPositionType"
                        (withDefault
                            "isCentralBank/Cash"
                            (Dict.get "classifyByPositionType" model.dict)
                        )
                        Dict.empty
                        |> Dict.insert "isCentralBank" s1
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueSegCash s1 ->
            let
                newDict1 =
                    Dict.remove "classifyByCounterPartyID" model.dict
                        |> Dict.insert "isSegregatedCash" s1
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueCode s1 ->
            let
                newDict1 =
                    Dict.insert "classifyByCounterPartyID" s1 model.dict
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueShore s1 ->
            --needs to unset isNetUsdAmountNegative & isFeed44andCostCenterNot5C55
            let
                newDict1 =
                    Dict.remove "isNetUsdAmountNegative" model.dict
                        |> Dict.remove "isFeed44andCostCenterNot5C55"
                        |> Dict.insert "isOnShore" s1
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueNegative s1 ->
            --needs to unset isFeed44andCostCenterNot5C55
            let
                newDict1 =
                    Dict.remove "isFeed44andCostCenterNot5C55" model.dict
                        |> Dict.insert "isNetUsdAmountNegative" s1
            in
            ( { model
                | dict = newDict1
                , treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1)
              }
            , Cmd.none
            )

        SetDictValueFeed s1 ->
            let
                newDict1 =
                    Dict.insert "isFeed44andCostCenterNot5C55" s1 model.dict
            in
            ( { model | dict = newDict1, treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] newDict1) }, Cmd.none )

        RedoTree ->
            ( { model | treeModel = TreeView.initializeModel2 configuration (listToNode [ model.originalIR ] Dict.empty) }, Cmd.none )

        _ ->
            let
                treeModel =
                    case message of
                        TreeViewMsg tvMsg ->
                            TreeView.update2 tvMsg model.treeModel

                        _ ->
                            model.treeModel

                selectedNode =
                    TreeView.getSelected treeModel |> Maybe.map .node |> Maybe.map Tree.dataOf
            in
            ( { model
                | treeModel = treeModel
                , selectedNode = selectedNode
              }
            , Cmd.none
            )


white : Color
white =
    rgb 1 1 1


selectedNodeDetails : Model -> Html Msg
selectedNodeDetails model =
    let
        selectedDetails =
            Maybe.map (\nodeData -> nodeData.uid ++ ": " ++ nodeData.subject) model.selectedNode
                |> Maybe.withDefault "(nothing selected)"
    in
    Html.div
        []
        [ Html.text selectedDetails
        ]


view : Model -> Html.Html Msg
view model =
    Html.div
        [ class "center-screen" ]
        --[ Html.div
        --[ class "colored-background" ]
        [ dropdowns model
        , map TreeViewMsg (TreeView.view2 model.selectedNode model.treeModel)

        --]
        ]


main =
    Browser.element
        { init = initialModel
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


dropdowns : Model -> Html.Html Msg
dropdowns model =
    Html.div []
        [ Html.div [ id "all-dropdowns", Html.style "color" "white" ]
            [ label [ class "title-arboretum" ] [ Html.text "Arboretum" ]
            , label [ id "cash-select-label", for "cash-select" ] [ Html.text "Choose a Product: " ]
            , select [ id "cash-select", onInput SetDictValueRoot, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Product" ]
                , option [ value "Is Central Bank/Cash" ] [ Html.text "Cash" ]
                , option [ value "/Inventory" ] [ Html.text "Inventory" ]
                , option [ value "/Pending Trades" ] [ Html.text "Pending Trades" ]
                ]
            , label [ id "central-bank-select-label", for "central-bank-select", class "l-d" ] [ Html.text "Uses Central Bank?:" ]
            , select [ id "central-bank-select", onInput SetDictValueBank, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Uses Central Bank?" ]
                , option [ value "Is Segregated Cash/True" ] [ Html.text "Yes" ]
                , option [ value "Is On Shore/False" ] [ Html.text "No" ]
                ]
            , Html.div [ id "central-bank-yes-child" ]
                [ label [ id "seg-cash-select-label", for "seg-cash-select", class "l-d" ] [ Html.text "Is Segregated Cash?:" ]
                , select [ id "seg-cash-select", onInput SetDictValueSegCash, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is Segregated Cash?" ]
                    , option [ value "Classify By Counter Party ID/True" ] [ Html.text "Yes" ]
                    , option [ value "Classify By Counter Party ID/False" ] [ Html.text "No" ]
                    ]

                --will have to add another dropdown here for the other codes, based on answer of previous
                , label [ id "code-select-1-label", for "code-select-1", class "l-d" ] [ Html.text "Select Counterparty ID:" ]
                , select [ id "code-select-1", onInput SetDictValueCode, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Select Counterparty ID:" ]
                    , option [ value "1.A.4.1/FRD" ] [ Html.text "FRD" ]
                    , option [ value "1.A.4.2/BOE" ] [ Html.text "BOE" ]
                    , option [ value "1.A.4.3/SNB" ] [ Html.text "SNB" ]
                    , option [ value "1.A.4.4/ECB" ] [ Html.text "ECB" ]
                    , option [ value "1.A.4.5/BOI" ] [ Html.text "BOJ" ]
                    , option [ value "1.A.4.6/RBA" ] [ Html.text "RBA" ]
                    , option [ value "1.A.4.7/BOC" ] [ Html.text "BOC" ]
                    , option [ value "1.A.4.8/other" ] [ Html.text "other" ]
                    ]
                , label [ id "code-select-2-label", for "code-select-2", class "l-d" ] [ Html.text "Select Counterparty ID:" ]
                , select [ id "code-select-2", onInput SetDictValueCode, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Select Counterparty ID:" ]
                    , option [ value "1.A.3.1/FRD" ] [ Html.text "FRD" ]
                    , option [ value "1.A.3.2/BOE" ] [ Html.text "BOE" ]
                    , option [ value "1.A.3.3/SNB" ] [ Html.text "SNB" ]
                    , option [ value "1.A.3.4/ECB" ] [ Html.text "ECB" ]
                    , option [ value "1.A.3.5/BOI" ] [ Html.text "BOJ" ]
                    , option [ value "1.A.3.6/RBA" ] [ Html.text "RBA" ]
                    , option [ value "1.A.3.7/BOC" ] [ Html.text "BOC" ]
                    , option [ value "1.A.3.8/other" ] [ Html.text "other" ]
                    ]
                ]
            , Html.div [ id "central-bank-no-child" ]
                [ label [ id "on-shore-select-label", for "on-shore-select", class "l-d" ] [ Html.text "On or Off Shore?: " ]
                , select [ id "on-shore-select", onInput SetDictValueShore, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "On or Off Shore?" ]
                    , option [ value "Is NetUsd Amount Negative/True" ] [ Html.text "Yes" ]
                    , option [ value "Is NetUsd Amount Negative/False" ] [ Html.text "No" ]
                    ]

                --need another branch here
                , label [ id "negative-select-label", for "negative-select", class "l-d" ] [ Html.text "NetUSD Amount: " ]
                , select [ id "negative-select", onInput SetDictValueNegative, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "NetUSD Amount (Positive/Negative)" ]
                    , option [ value "O.W.9/True" ] [ Html.text "Positive" ]
                    , option [ value "Is Feed44 and CostCenter Not 5C55/False" ] [ Html.text "Negative" ]
                    ]
                , Html.div [ id "negative-no-child" ]
                    [ label [ id "negative-no-child-select-label", for "negative-no-child-select", class "l-d" ] [ Html.text "Is Feed44 and CostCenter Not 5C55: " ]
                    , select [ id "negative-no-child-select", onInput SetDictValueFeed, class "dropdown" ]
                        [ option [ value "", disabled True, selected True ] [ Html.text "Is Feed44 and CostCenter Not 5C55" ]
                        , option [ value "1.U.1/True" ] [ Html.text "Yes" ]
                        , option [ value "1.U.4/False" ] [ Html.text "No" ]
                        ]
                    ]
                , label [ id "negative-select-2-label", for "negative-select-2", class "l-d" ] [ Html.text "Is NetUsd Amount Negative: " ]
                , select [ id "negative-select-2", onInput SetDictValueNegative, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is NetUsd Amount Negative" ]
                    , option [ value "O.W.10/True" ] [ Html.text "Yes" ]
                    , option [ value "Is Feed44 and CostCenter Not 5C55/False" ] [ Html.text "No" ]
                    ]
                , Html.div [ id "negative-no-child-2" ]
                    [ label [ id "negative-no-child-select-2-label", for "negative-no-child-select-2", class "l-d" ] [ Html.text "Is Feed44 and CostCenter Not 5C55: " ]
                    , select [ id "negative-no-child-select-2", onInput SetDictValueFeed, class "dropdown" ]
                        [ option [ value "", disabled True, selected True ] [ Html.text "Is Feed44 and CostCenter Not 5C55" ]
                        , option [ value "1.U.2/True" ] [ Html.text "Yes" ]
                        , option [ value "1.U.4/False" ] [ Html.text "No" ]
                        ]
                    ]
                ]
            , button [ id "show-button" ] [ Html.text "Show me all inputs" ]
            ]
        ]



--construct a configuration for your tree view
-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions2 model.treeModel)


toMaybeList : List ( Pattern (), Value () () ) -> List ( Maybe (Pattern ()), Value () () )
toMaybeList list =
    let
        patterns =
            List.map Tuple.first list

        maybePatterns =
            List.map Just patterns

        values =
            List.map Tuple.second list
    in
    List.map2 Tuple.pair maybePatterns values


listToNode : List (Value () ()) -> Dict String String -> List (Tree.Node NodeData)
listToNode values dict =
    let
        uids =
            List.range 1 (List.length values)
    in
    List.map2 (\value uid -> toTranslate value uid dict) values uids


toTranslate : Value () () -> Int -> Dict String String -> Tree.Node NodeData
toTranslate value uid dict =
    let
        newDict =
            convertToDict
                (Dict.fromList
                    (List.append
                        [ ( "Classify By Position Type", "" ) ]
                        (List.map helper (List.map (split "/") (Dict.values dict)))
                    )
                )
    in
    translation ( Nothing, value ) (fromInt uid) False newDict


getCurrentHighlightState : Bool -> Dict Name (Value () ()) -> Maybe (Pattern ()) -> Value () () -> String -> Bool
getCurrentHighlightState previous dict pattern subject uid =
    if Dict.size dict > 1 then
        if String.length uid == 1 then
            True

        else if previous then
            evaluateHighlight dict (Value.toString subject) (withDefault (WildcardPattern ()) pattern)

        else
            False

    else
        False


translation : ( Maybe (Pattern ()), Value () () ) -> String -> Bool -> Dict Name (Value () ()) -> Tree.Node NodeData
translation ( pattern, value ) uid previousHighlightState dict =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                currentHighlightState : Bool
                currentHighlightState =
                    getCurrentHighlightState previousHighlightState dict pattern condition uid

                data =
                    NodeData uid (Value.toString condition) pattern currentHighlightState

                uids =
                    createUIDS 2 uid

                list =
                    [ ( Just (Value.LiteralPattern () (BoolLiteral True)), thenBranch ), ( Just (Value.LiteralPattern () (BoolLiteral False)), elseBranch ) ]

                children : List (Tree.Node NodeData)
                children =
                    List.map2 (\myList myUID -> translation myList myUID currentHighlightState dict) list uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        Value.PatternMatch tpe param patterns ->
            let
                currentHighlightState : Bool
                currentHighlightState =
                    getCurrentHighlightState previousHighlightState dict pattern param uid

                data =
                    NodeData uid (Value.toString param) pattern currentHighlightState

                maybePatterns =
                    toMaybeList patterns

                uids =
                    createUIDS (List.length maybePatterns) uid

                children : List (Tree.Node NodeData)
                children =
                    List.map2 (\myList myUID -> translation myList myUID currentHighlightState dict) maybePatterns uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        _ ->
            let
                currentHighlightState : Bool
                currentHighlightState =
                    getCurrentHighlightState previousHighlightState dict pattern value uid
            in
            Tree.Node { data = NodeData uid (Value.toString value) pattern currentHighlightState, children = [] }


createUIDS : Int -> String -> List String
createUIDS range currentUID =
    let
        intRange =
            List.range 1 range

        stringRange =
            List.map fromInt intRange

        appender int =
            String.append (currentUID ++ ".") int
    in
    List.map appender stringRange


type NodeDataMsg
    = EditContent String String -- uid content


convertToDict : Dict String String -> Dict Name (Value ta ())
convertToDict dict =
    let
        dictList =
            Dict.toList dict
    in
    Dict.fromList (List.map convertToDictHelper dictList)


convertToDictHelper : ( String, String ) -> ( Name, Value ta () )
convertToDictHelper ( k, v ) =
    case v of
        "True" ->
            ( Name.fromString k, Value.Literal () (BoolLiteral True) )

        "False" ->
            ( Name.fromString k, Value.Literal () (BoolLiteral False) )

        _ ->
            ( Name.fromString k, Value.Literal () (StringLiteral v) )


viewNodeData : Maybe NodeData -> Tree.Node NodeData -> Html.Html NodeDataMsg
viewNodeData selectedNode node =
    let
        nodeData =
            Tree.dataOf node
    in
    if nodeData.highlight then
        Html.div
            [ class "highlighted-node"
            ]
            [ Html.text (nodeLabel node)
            ]

    else
        Html.text (nodeLabel node)


helper : List String -> ( String, String )
helper l =
    case l of
        [ s1, s2 ] ->
            ( s1, s2 )

        _ ->
            ( "oh", "no" )

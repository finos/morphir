module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
import Dict exposing (Dict, values)
import Element exposing (Color, Element, rgb)
import Html exposing (Html, button, label, map, option, select)
import Html.Attributes exposing (class, disabled, for, id, selected, value)
import Html.Events exposing (onClick, onInput)
import List exposing (drop, head, tail, take)
import Maybe exposing (withDefault)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Value as Value exposing (Pattern(..), RawValue, Value(..))
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


evaluateHighlight : Dict Name RawValue -> String -> Pattern () -> Bool
evaluateHighlight variables value pattern =
    let
        evaluation : Maybe.Maybe RawValue
        evaluation =
            variables |> Dict.get (Name.fromString value)
    in
    case evaluation of
        Just val ->
            True

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
        rootNodes =
            listToNode
                [ Value.patternMatch ()
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
                ]
    in
    ( { rootNodes = rootNodes
      , dict = Dict.empty
      , treeModel = TreeView.initializeModel2 configuration rootNodes
      , selectedNode = Nothing
      }
    , Cmd.none
    )



-- dont need to call evaluate highlight if value isnt highlighted
-- pass argument from previous level --> from parent level
-- would be the best if in node data we could keep it in
-- evaluate highlight shouldnt be called in the view function
-- elm renders the browswer call back that potentially can be called 7829329 times a second
-- in view function shouldnt have any heavy opperations --> should all be done in update functioon
-- do all calculations in update function
-- have highlight flag in node data--> calculating the
-- intially all set to false --> then when you update --> it updates
-- Initialize the TreeView model


type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String NodeDataMsg (Maybe NodeData)
    , selectedNode : Maybe NodeData
    , dict : Dict String String
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
    | SetDictValue String
    | SetDictValueErase String
    | SetRoot String
    | SetBank String
    | SetSegCash String
    | SetCode String
    | SetShore String
    | SetNegative String
    | SetFeed String
    | RedoTree



-- Updates the tree as drop downs are selected


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        SetDictValueErase s1 ->
            let
                --Debug.log ("TESTSTUFF: " ++ join ":" (split "/" s1))
                newList =
                    split "/" s1

                newKey =
                    join "" (take 1 newList)

                newValue =
                    join "" (drop 1 newList)

                newDict1 =
                    Dict.insert newKey newValue Dict.empty
            in
            ( { model | dict = newDict1 }, Cmd.none )

        SetDictValue s1 ->
            let
                --Debug.log ("TESTSTUFF: " ++ join ":" (split "/" s1))
                newList =
                    split "/" s1

                newKey =
                    join "" (take 1 newList)

                newValue =
                    join "" (drop 1 newList)

                newDict1 =
                    Dict.insert newKey newValue model.dict
            in
            ( { model | dict = newDict1 }, Cmd.none )

        SetBank s1 ->
            let
                newDict1 =
                    Dict.insert "Is Central Bank" s1 model.dict

                newDict2 =
                    Dict.remove "Is Segregated Cash" newDict1

                newDict3 =
                    Dict.remove "Classify By Counter Party ID" newDict2

                newDict4 =
                    Dict.remove "Is On Shore" newDict3

                newDict5 =
                    Dict.remove "Is NetUsd Amount Negative" newDict4

                newDict6 =
                    Dict.remove "Is Feed44 and CostCenter Not 5C55" newDict5
            in
            ( { model | dict = newDict6 }, Cmd.none )

        SetSegCash s1 ->
            ( { model | dict = Dict.insert "Is Segregated Cash" s1 model.dict }, Cmd.none )

        SetCode s1 ->
            --do the same with classify by counter party ID.
            --find a way to send the key as well as the value
            ( { model | dict = Dict.insert "Classify By Counter Party ID" s1 model.dict }, Cmd.none )

        SetShore s1 ->
            ( { model | dict = Dict.insert "Is On Shore" s1 model.dict }, Cmd.none )

        SetNegative s1 ->
            let
                newDict =
                    Dict.insert "Is NetUsd Amount Negative" s1 model.dict

                newDict1 =
                    Dict.remove "Is Feed44 and CostCenter Not 5C55" newDict
            in
            ( { model | dict = newDict1 }, Cmd.none )

        SetFeed s1 ->
            ( { model | dict = Dict.insert "Is Feed44 and CostCenter Not 5C55" s1 model.dict }, Cmd.none )

        RedoTree ->
            ( { model | treeModel = TreeView.initializeModel2 (configuration2 model) model.rootNodes }, Cmd.none )

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



-- avilitiy to view tree
--key is branches, value is string for case or True/False for if else


view : Model -> Html.Html Msg
view model =
    Html.div
        [ id "top-level" ]
        [ dropdowns model
        , selectedNodeDetails model
        , map TreeViewMsg (TreeView.view2 model.selectedNode model.treeModel)
        ]



-- when changing highlight state --> changing root nodes
-- when assigning tree model --> thats the point where we could invoke highlight state
-- we can pass in
-- invoke a function that calculates the root nodes
-- store org ir
-- in pudate we want to have root nodes that are changing
-- store original ir in the model


main =
    Browser.element
        { init = initialModel
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



--idea is to make values equal to the key/value for dict and split on /


dropdowns : Model -> Html.Html Msg
dropdowns model =
    Html.div []
        [ Html.text (join "--------------" (List.map2 (\x y -> x ++ ":" ++ y) (Dict.keys model.dict) (Dict.values model.dict)))
        , Html.div [ id "all-dropdowns" ]
            [ label [ for "cash-select" ] [ Html.text "Choose a type: " ]
            , select [ id "cash-select", onInput SetDictValueErase, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Type" ]
                , option [ value "Is Central Bank/Cash" ] [ Html.text "Cash" ]
                , option [ value "/Inventory" ] [ Html.text "Inventory" ]
                , option [ value "/Pending Trades" ] [ Html.text "Pending Trades" ]
                ]
            , label [ for "central-bank-select" ] [ Html.text "Choose a bank: " ]
            , select [ id "central-bank-select", onInput SetDictValue, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Is Central Bank" ]
                , option [ value "Is Segregated Cash/True" ] [ Html.text "Yes" ]
                , option [ value "Is On Shore/False" ] [ Html.text "No" ]
                ]
            , Html.div [ id "central-bank-yes-child" ]
                [ label [ for "seg-cash-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "seg-cash-select", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is Segregated Cash" ]
                    , option [ value "Classify By Counter Party ID/True" ] [ Html.text "Yes" ]
                    , option [ value "Classify By Counter Party ID/False" ] [ Html.text "No" ]
                    ]

                --will have to add another dropdown here for the other codes, based on answer of previous
                , label [ for "code-select-1" ] [ Html.text "Choose a code " ]
                , select [ id "code-select-1", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Classify By Counter Party ID" ]
                    , option [ value "1.A.4.1/FRD" ] [ Html.text "FRD" ]
                    , option [ value "1.A.4.2/BOE" ] [ Html.text "BOE" ]
                    , option [ value "1.A.4.3/SNB" ] [ Html.text "SNB" ]
                    , option [ value "1.A.4.4/ECB" ] [ Html.text "ECB" ]
                    , option [ value "1.A.4.5/BOJ" ] [ Html.text "BOJ" ]
                    , option [ value "1.A.4.6/RBA" ] [ Html.text "RBA" ]
                    , option [ value "1.A.4.7/BOC" ] [ Html.text "BOC" ]
                    , option [ value "1.A.4.8/other" ] [ Html.text "other" ]
                    ]
                , label [ for "code-select-2" ] [ Html.text "Choose a code " ]
                , select [ id "code-select-2", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Classify By Counter Party ID" ]
                    , option [ value "1.A.3.1/FRD" ] [ Html.text "FRD" ]
                    , option [ value "1.A.3.2/BOE" ] [ Html.text "BOE" ]
                    , option [ value "1.A.3.3/SNB" ] [ Html.text "SNB" ]
                    , option [ value "1.A.3.4/ECB" ] [ Html.text "ECB" ]
                    , option [ value "1.A.3.5/BOJ" ] [ Html.text "BOJ" ]
                    , option [ value "1.A.3.6/RBA" ] [ Html.text "RBA" ]
                    , option [ value "1.A.3.7/BOC" ] [ Html.text "BOC" ]
                    , option [ value "1.A.3.8/other" ] [ Html.text "other" ]
                    ]
                ]
            , Html.div [ id "central-bank-no-child" ]
                [ label [ for "on-shore-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "on-shore-select", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is On Shore" ]
                    , option [ value "Is NetUsd Amount Negative/True" ] [ Html.text "Yes" ]
                    , option [ value "Is NetUsd Amount Negative/False" ] [ Html.text "No" ]
                    ]

                --need another branch here
                , label [ for "negative-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "negative-select", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is NetUsd Amount Negative" ]
                    , option [ value "O.W.9/True" ] [ Html.text "Yes" ]
                    , option [ value "Is Feed44 and CostCenter Not 5C55/False" ] [ Html.text "No" ]
                    ]
                , Html.div [ id "negative-no-child" ]
                    [ label [ for "negative-no-child-select" ] [ Html.text "Choose T/F: " ]
                    , select [ id "negative-no-child-select", onInput SetDictValue, class "dropdown" ]
                        [ option [ value "", disabled True, selected True ] [ Html.text "Is Feed44 and CostCenter Not 5C55" ]
                        , option [ value "1.U.1/True" ] [ Html.text "Yes" ]
                        , option [ value "1.U.4/False" ] [ Html.text "No" ]
                        ]
                    ]
                , label [ for "negative-select-2" ] [ Html.text "Choose T/F: " ]
                , select [ id "negative-select-2", onInput SetDictValue, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is NetUsd Amount Negative" ]
                    , option [ value "O.W.10/True" ] [ Html.text "Yes" ]
                    , option [ value "Is Feed44 and CostCenter Not 5C55/False" ] [ Html.text "No" ]
                    ]
                , Html.div [ id "negative-no-child-2" ]
                    [ label [ for "negative-no-child-select-2" ] [ Html.text "Choose T/F: " ]
                    , select [ id "negative-no-child-select-2", onInput SetDictValue, class "dropdown" ]
                        [ option [ value "", disabled True, selected True ] [ Html.text "Is Feed44 and CostCenter Not 5C55" ]
                        , option [ value "1.U.2/True" ] [ Html.text "Yes" ]
                        , option [ value "1.U.4/False" ] [ Html.text "No" ]
                        ]
                    ]
                ]
            ]
        , button [ id "hide-button" ] [ Html.text "Hide Selections " ]
        , button [ id "tree-button", onClick RedoTree ] [ Html.text "Show me da monay" ]
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


listToNode : List (Value () ()) -> List (Tree.Node NodeData)
listToNode values =
    let
        uids =
            List.range 1 (List.length values)
    in
    List.map2 toTranslate values uids


toTranslate : Value () () -> Int -> Tree.Node NodeData
toTranslate value uid =
    translation ( Nothing, value ) (fromInt uid)


translation : ( Maybe (Pattern ()), Value () () ) -> String -> Tree.Node NodeData
translation ( pattern, value ) uid =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                data =
                    -- if new flag is false,
                    -- if its true, run evaluate highlihgt --> pass down value of that
                    -- add in evaluatehighlight
                    -- highlight flag
                    -- stop calling evaluate highlight when flag is false
                    NodeData uid (Value.toString condition) pattern

                uids =
                    createUIDS 2 uid

                list =
                    [ ( Just (Value.LiteralPattern () (BoolLiteral True)), thenBranch ), ( Just (Value.LiteralPattern () (BoolLiteral False)), elseBranch ) ]

                children : List (Tree.Node NodeData)
                children =
                    List.map2 translation list uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        Value.PatternMatch tpe param patterns ->
            let
                data =
                    NodeData uid (Value.toString param) pattern

                maybePatterns =
                    toMaybeList patterns

                uids =
                    createUIDS (List.length maybePatterns) uid

                children : List (Tree.Node NodeData)
                children =
                    List.map2 translation maybePatterns uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        _ ->
            Tree.Node { data = NodeData uid (Value.toString value) pattern, children = [] }


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



-- evaluate condition
-- variable dictionary --> interpreter looks up to get corresponding value
-- all it will do is dictionary look up
-- in real world those will be functions --> business logic
-- type as a variable -->
-- type and currenctly selected drop down


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

        dict2 =
            convertToDict
                (Dict.fromList
                    []
                )

        highlight =
            evaluateHighlight dict2
                nodeData.subject
                (withDefault (WildcardPattern ()) nodeData.pattern)
                |> Debug.log ("pattern: " ++ getLabel nodeData.pattern ++ " subject: " ++ nodeData.subject)
    in
    if highlight then
        Html.div
            [ class "highlighted-node"
            ]
            [ Html.text (nodeLabel node)
            ]

    else
        Html.text (nodeLabel node)


viewNodeData2 : Model -> Maybe NodeData -> Tree.Node NodeData -> Html.Html NodeDataMsg
viewNodeData2 model selectedNode node =
    let
        nodeData =
            Tree.dataOf node

        dict2 =
            --pass in my dict, changes it to tuples i guess
            convertToDict
                (Dict.fromList
                    (List.append
                        [ ( "Classify By Position Type", "_" ) ]
                        (List.map2 Tuple.pair (Dict.keys model.dict) (Dict.values model.dict))
                    )
                )

        highlight =
            evaluateHighlight dict2
                nodeData.subject
                (withDefault (WildcardPattern ()) nodeData.pattern)
                |> Debug.log ("pattern: " ++ getLabel nodeData.pattern ++ " subject: " ++ nodeData.subject)
    in
    if highlight then
        Html.div
            [ class "highlighted-node"
            ]
            [ Html.text (nodeLabel node)
            ]

    else
        Html.text (nodeLabel node)


configuration2 : Model -> TreeView.Configuration2 NodeData String NodeDataMsg (Maybe NodeData)
configuration2 model =
    TreeView.Configuration2 nodeUidOf (viewNodeData2 model) TreeView.defaultCssClasses

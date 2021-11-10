module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

--import Bootstrap.Alert exposing (h1)
--import Bootstrap.Badge as Badge

import Bootstrap.Alert exposing (h1)
import Bootstrap.Badge as Badge
import Browser
import Dict exposing (Dict, values)
import Element exposing (Color, Element, column, el, fill, html, layout, mouseOver, none, padding, paddingEach, paddingXY, px, rgb, row, shrink, spacing, table, text)
import Html exposing (Html, a, button, label, map, option, select)
import Html.Attributes as Html exposing (class, disabled, for, id, selected, style, value)
import Html.Events exposing (onClick, onInput)
import Maybe exposing (withDefault)
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Value as Value exposing (Pattern(..), RawValue, Value(..), ifThenElse, patternMatch, toString, unit, variable)
import Morphir.SDK.Bool exposing (false, true)
import Morphir.Value.Interpreter as Interpreter exposing (matchPattern)
import Morphir.Visual.ViewPattern as ViewPattern
import String exposing (fromInt, length)
import Tree as Tree
import TreeView as TreeView
import Tuple exposing (first)


t =
    Element.text



--text = Html.Styled.text
--load ir and figure out what to show
-- reading an ir and selecting the function in it to visualize
-- scratch view value integration
-- use example data structures to feed
-- replace piece with hand written ir and function that turns it into ha
-- still hard coded examples
-- hard coding if then els eand pattern match
-- translate back into ir version of that
-- we have these examples
-- piece that turns ir into data strcutre
-- Value.IfThenElse () (var "isFoo") (var "Yes") (var "No")
-- Value.PatternMatch () (var "isFoo") List
-- define data type for values we put into tree node


type alias NodeData =
    { uid : String
    , subject : String
    , pattern : Maybe (Pattern ())
    , highlight : Bool
    }


getLabel : Maybe (Pattern ()) -> String
getLabel maybeLabel =
    case maybeLabel of
        Just label ->
            ViewPattern.patternAsText label ++ " - "

        Nothing ->
            ""


evaluateHighlight : Dict Name RawValue -> String -> Pattern () -> Bool
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



-- ViewPattern.patternAsText(node.data.pattern) ++ "->" ++ node.data.subject
-- define a function to calculate the text representation of a node


nodeLabel : Tree.Node NodeData -> String
nodeLabel n =
    case n of
        Tree.Node node ->
            getLabel node.data.pattern ++ node.data.subject



-- define another function to calculate the uid of a node
-- define another function to calculate the uid of a node
--nodeUid : Tree.Node NodeData -> TreeView.NodeUid String
--nodeUid n =
--    case n of
--        Tree.Node node -> TreeView.NodeUid node.data.uid
-- walk through wire frame
-- confused why top level doesnt have anything corresponding


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
                                    (Value.Variable () [ "Is NetUsd Amount Negative" ])
                                    (Value.Variable () [ "O.W.9" ])
                                    (Value.IfThenElse ()
                                        (Value.Variable () [ "Is Feed44 and CostCenter Not 5C55" ])
                                        (Value.Variable () [ "1.U.1" ])
                                        (Value.Variable () [ "1.U.4" ])
                                    )
                                )
                                (Value.IfThenElse ()
                                    (Value.Variable () [ "Is NetUsd Amount Negative" ])
                                    (Value.Variable () [ "O.W.10" ])
                                    --
                                    (Value.IfThenElse ()
                                        (Value.Variable () [ "Is Feed44 and CostCenter Not 5C55" ])
                                        (Value.Variable () [ "1.U.2" ])
                                        (Value.Variable () [ "1.U.4" ])
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



-- initialize the TreeView model


type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String NodeDataMsg (Maybe NodeData)
    , selectedNode : Maybe NodeData
    , dict : Dict String String
    }


nodeUidOf : Tree.Node NodeData -> TreeView.NodeUid String
nodeUidOf n =
    case n of
        Tree.Node node ->
            TreeView.NodeUid node.data.uid



--construct a configuration for your tree view


configuration : TreeView.Configuration2 NodeData String NodeDataMsg (Maybe NodeData)
configuration =
    TreeView.Configuration2 nodeUidOf viewNodeData TreeView.defaultCssClasses



-- otherwise interact with your tree view in the usual TEA manner


type Msg
    = TreeViewMsg (TreeView.Msg2 String NodeDataMsg)
    | SetRoot String
    | SetBank String
    | SetSegCash String
    | SetCode String
    | SetShore String
    | SetNegative String
    | SetFeed String
    | RedoTree


setNodeContent : String -> String -> TreeView.Model NodeData String NodeDataMsg (Maybe NodeData) -> TreeView.Model NodeData String NodeDataMsg (Maybe NodeData)
setNodeContent nodeUid subject treeModel =
    TreeView.updateNodeData
        (\nodeData -> nodeData.uid == nodeUid)
        (\nodeData -> { nodeData | subject = subject })
        treeModel


setNodeHighlight : String -> Bool -> TreeView.Model NodeData String NodeDataMsg (Maybe NodeData) -> TreeView.Model NodeData String NodeDataMsg (Maybe NodeData)
setNodeHighlight nodeUid highlight treeModel =
    TreeView.updateNodeData
        (\nodeData -> nodeData.uid == nodeUid)
        (\nodeData -> { nodeData | highlight = highlight })
        treeModel


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        SetRoot s1 ->
            ( { model | dict = Dict.insert "Classify By Position Type" s1 model.dict }, Cmd.none )

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
            Debug.log "Im Highlighting"
                ( model, Cmd.none )

        _ ->
            let
                treeModel =
                    case message of
                        TreeViewMsg (TreeView.CustomMsg nodeDataMsg) ->
                            case nodeDataMsg of
                                EditContent nodeUid content ->
                                    setNodeHighlight nodeUid True model.treeModel

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


overColor : Color
overColor =
    rgb 0.9 0.9 0.1


white : Color
white =
    rgb 1 1 1


selectedNodeDetails : Model -> Html Msg
selectedNodeDetails model =
    let
        selectedDetails =
            Maybe.map (\nodeData -> nodeData.uid ++ ": " ++ nodeData.subject) model.selectedNode
                |> Maybe.withDefault "(nothing selected)"

        --selectedHighlight = Maybe.map (\nodeData -> nodeData.highlight) model.selectedNode
    in
    Html.div
        []
        [ Html.text selectedDetails
        ]



-- avilitiy to view tree
--key is branches, value is string for case or True/False for if else


view : Model -> Html.Html Msg
view model =
    --layout [] dropdown
    Html.div
        [ id "top-level" ]
        [ h1 [ style "color" "#1c5d94" ] [ Html.text "Arboretum " ]
        , dropdowns model
        , selectedNodeDetails model
        , map TreeViewMsg (TreeView.view2 model.selectedNode model.treeModel)
        ]



--


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
        [ Html.text (Maybe.withDefault "unknown" (Dict.get "Classify By Position Type" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Is Central Bank" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Is Segregated Cash" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Classify By Counter Party ID" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Is On Shore" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Is NetUsd Amount Negative" model.dict))
        , Html.text (Maybe.withDefault "unknown" (Dict.get "Is Feed44 and CostCenter Not 5C55" model.dict))
        , Html.div [ id "all-dropdowns", Html.style "color" "white" ]
            [ label [ for "cash-select" ] [ Html.text "Choose a type: " ]
            , select [ id "cash-select", onInput SetRoot, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Type" ]
                , option [ value "Cash" ] [ Html.text "Cash" ]
                , option [ value "Inventory" ] [ Html.text "Inventory" ]
                , option [ value "Pending Trades" ] [ Html.text "Pending Trades" ]
                ]

            --, Html.div [ id "cash-child" ] [
            , label [ for "central-bank-select" ] [ Html.text "Choose a bank: " ]
            , select [ id "central-bank-select", onInput SetBank, class "dropdown" ]
                [ option [ value "", disabled True, selected True ] [ Html.text "Is Central Bank" ]
                , option [ value "True" ] [ Html.text "Yes" ]
                , option [ value "False" ] [ Html.text "No" ]
                ]
            , Html.div [ id "central-bank-yes-child" ]
                [ label [ for "seg-cash-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "seg-cash-select", onInput SetSegCash, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is Segregated Cash" ]
                    , option [ value "True" ] [ Html.text "Yes" ]
                    , option [ value "False" ] [ Html.text "No" ]
                    ]
                , label [ for "code-select" ] [ Html.text "Choose a code " ]
                , select [ id "code-select", onInput SetCode, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Classify By Counter Party ID" ]
                    , option [ value "FRD" ] [ Html.text "FRD" ]
                    , option [ value "BOE" ] [ Html.text "BOE" ]
                    , option [ value "SNB" ] [ Html.text "SNB" ]
                    , option [ value "ECB" ] [ Html.text "ECB" ]
                    , option [ value "BOJ" ] [ Html.text "BOJ" ]
                    , option [ value "RBA" ] [ Html.text "RBA" ]
                    , option [ value "BOC" ] [ Html.text "BOC" ]
                    , option [ value "other" ] [ Html.text "other" ]
                    ]
                ]
            , Html.div [ id "central-bank-no-child" ]
                [ label [ for "on-shore-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "on-shore-select", onInput SetShore, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is On Shore" ]
                    , option [ value "True" ] [ Html.text "Yes" ]
                    , option [ value "False" ] [ Html.text "No" ]
                    ]
                , label [ for "negative-select" ] [ Html.text "Choose T/F: " ]
                , select [ id "negative-select", onInput SetNegative, class "dropdown" ]
                    [ option [ value "", disabled True, selected True ] [ Html.text "Is NetUsd Amount Negative" ]
                    , option [ value "True" ] [ Html.text "Yes" ]
                    , option [ value "False" ] [ Html.text "No" ]
                    ]
                , Html.div [ id "negative-no-child" ]
                    [ label [ for "negative-no-child-select" ] [ Html.text "Choose T/F: " ]
                    , select [ id "negative-no-child-select", onInput SetFeed, class "dropdown" ]
                        [ option [ value "", disabled True, selected True ] [ Html.text "Is Feed44 and CostCenter Not 5C55" ]
                        , option [ value "True" ] [ Html.text "Yes" ]
                        , option [ value "False" ] [ Html.text "No" ]
                        ]
                    ]
                ]

            --]
            ]
        , button [ id "hide-button" ] [ Html.text "Hide Selections " ]
        , button [ id "tree-button", onClick RedoTree ] [ Html.text "Show me da monay" ]
        ]



--construct a configuration for your tree view
-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions2 model.treeModel)


mylist : List (Value () ())
mylist =
    [ Value.Literal () (BoolLiteral True)
    , Value.Literal () (StringLiteral "Cash")
    , Value.Literal () (BoolLiteral True)
    , Value.Literal () (BoolLiteral False)
    , Value.Literal () (StringLiteral "SNB")
    ]


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



-- pass in a bunch of variables
-- call the enterpreteur to do any business logic


listToNode : List (Value () ()) -> List (Tree.Node NodeData)
listToNode values =
    let
        uids =
            List.range 1 (List.length values)
    in
    List.map2 toTranslate values uids


toTranslate : Value () () -> Int -> Tree.Node NodeData
toTranslate value uid =
    translation2 ( Nothing, value ) (fromInt uid)



-- Tree.Node NodeData


translation2 : ( Maybe (Pattern ()), Value () () ) -> String -> Tree.Node NodeData
translation2 ( pattern, value ) uid =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                data =
                    NodeData uid (Value.toString condition) pattern false

                uids =
                    createUIDS 2 uid

                list =
                    [ ( Just (Value.LiteralPattern () (BoolLiteral True)), thenBranch ), ( Just (Value.LiteralPattern () (BoolLiteral False)), elseBranch ) ]

                children : List (Tree.Node NodeData)
                children =
                    List.map2 translation2 list uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        Value.PatternMatch tpe param patterns ->
            let
                data =
                    NodeData uid (Value.toString param) pattern false

                maybePatterns =
                    toMaybeList patterns

                uids =
                    createUIDS (List.length maybePatterns) uid

                children : List (Tree.Node NodeData)
                children =
                    List.map2 translation2 maybePatterns uids
            in
            Tree.Node
                { data = data
                , children = children
                }

        _ ->
            --Value.toString value ++ (fromInt uid) ++ " ------ "
            Tree.Node { data = NodeData uid (Value.toString value) pattern false, children = [] }


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

        --dict =
        --    Dict.fromList
        --        [ ( Name.fromString "Classify By Position Type", Value.Literal () (StringLiteral "Cash") )
        --        , ( Name.fromString "Is Central Bank", Value.Literal () (BoolLiteral True) )
        --        , ( Name.fromString "Is Segregated Cash", Value.Literal () (BoolLiteral True) )
        --        , ( Name.fromString "Classify By Counter Party ID", Value.Literal () (StringLiteral "FRD") )
        --        ]
        dict2 =
            convertToDict
                (Dict.fromList
                    [ ( "Classify By Position Type", "sakdnajdbaj" )
                    , ( "Is Central Bank", "Cash" )
                    , ( "Is Segregated Cash", "True" )
                    , ( "Classify By Counter Party ID", "True" )
                    , ( "1.A.4.1", "FRD" )
                    ]
                )

        --[]
        selected =
            selectedNode
                |> Maybe.map (\sN -> nodeData.uid == sN.uid)
                |> Maybe.withDefault False

        highlight =
            evaluateHighlight dict2
                nodeData.subject
                --correctPath
                (withDefault (WildcardPattern ()) nodeData.pattern)
                |> Debug.log ("Stuff: " ++ nodeData.subject)

        --|> Debug.log ("logging " ++ getLabel nodeData.pattern ++ " subbie " ++ nodeData.subject)
    in
    if highlight then
        Html.text (getLabel nodeData.pattern ++ nodeData.subject ++ "  Highlight!!")
        --|> Debug.log dict

    else
        Html.text (getLabel nodeData.pattern ++ nodeData.subject)

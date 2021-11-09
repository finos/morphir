module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Array exposing (fromList, get)
import Browser
import Css exposing (auto, bold, fontSize, px, width, xxSmall)
import Dict exposing (Dict, values)
import Element exposing (Element, column, el, fill, html, layout, none, padding, paddingEach, px, row, shrink, spacing, table)
import Html exposing (a)
import Html.Styled exposing (Html, div, fromUnstyled, input, map, option, select, text, toUnstyled)
import Html.Styled.Attributes exposing (class, css, id, placeholder, type_, value)
import Html.Styled.Events exposing (onInput)
import Maybe exposing (withDefault)
import Morphir.Graph.Grapher exposing (Node(..))
import Morphir.IR as IR
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern(..), RawValue, Value(..), ifThenElse, patternMatch, toString, unit, variable)
import Morphir.SDK.Bool exposing (false, true)
import Morphir.Value.Error as Error
import Morphir.Value.Interpreter as Interpreter exposing (matchPattern)
import Morphir.Visual.Components.DecisionTable exposing (Match(..))
import Morphir.Visual.Components.MultiaryDecisionTree
import Morphir.Visual.Config exposing (Config, HighlightState(..))
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Mwc.Button
import Mwc.TextField
import Parser exposing (number)
import String exposing (fromInt, length)
import Svg.Attributes exposing (style)
import Tree as Tree
import TreeView as TreeView
import Tuple exposing (first)



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
    | ExpandAll
    | CollapseAll


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
    let
        treeModel =
            case message of
                TreeViewMsg (TreeView.CustomMsg nodeDataMsg) ->
                    case nodeDataMsg of
                        EditContent nodeUid content ->
                            setNodeHighlight nodeUid True model.treeModel

                TreeViewMsg tvMsg ->
                    TreeView.update2 tvMsg model.treeModel

                ExpandAll ->
                    TreeView.expandAll model.treeModel

                CollapseAll ->
                    TreeView.collapseAll model.treeModel

        selectedNode =
            TreeView.getSelected treeModel |> Maybe.map .node |> Maybe.map Tree.dataOf
    in
    ( { model
        | treeModel = treeModel
        , selectedNode = selectedNode
      }
    , Cmd.none
    )


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

        --selectedHighlight = Maybe.map (\nodeData -> nodeData.highlight) model.selectedNode
    in
    div
        [ css [ width auto ] ]
        [ Mwc.TextField.view
            [ Mwc.TextField.readonly True
            , Mwc.TextField.label selectedDetails
            ]
        ]



-- avilitiy to view tree


view : Model -> Html Msg
view model =
    div
        [ css [ width auto ] ]
        [ select [ id "first" ] [ option [ value "0" ] [ text "Cash" ], option [ value "1" ] [ text "Inventory" ], option [ value "2" ] [ text "Pending Trades" ] ]
        , select [ id "bank-type", class "sub-selector" ] [ option [ value "0" ] [ text "Central Bank" ], option [ value "1" ] [ text "Onshore" ] ]
        , select [ id "cash-type", class "sub-selector" ] [ option [ value "0" ] [ text "Segregated Cash" ], option [ value "1" ] [ text "Not" ] ]
        , select [ id "negative-type", class "hidden-on-start sub-selector" ] [ option [ value "0" ] [ text "NetUSD is Negative" ], option [ value "1" ] [ text "NetUSD is Positive" ] ]

        --, select [id "classify-type"] [option [] [text "Classify by Counter-Party ID"], option [] [text "Don't"]]
        --, select [id "bottom-level"] [option [] [text "FRD"], option [] [text "BOE"], option [] [text "SNB"]
        --    , option [] [text "ECB"], option [] [text "BOJ"], option [] [text "RBA"]
        --    , option [] [text "BOC"], option [] [text "Others"]]
        , expandAllCollapseAllButtons
        , selectedNodeDetails model
        , map TreeViewMsg (TreeView.view2 model.selectedNode model.treeModel |> fromUnstyled)
        ]



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


main =
    Browser.element
        { init = initialModel
        , view = view >> toUnstyled
        , update = update
        , subscriptions = subscriptions
        }


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
                    [ ( "Classify By Position Type", "Cash" )
                    , ( "Is Central Bank", "True" )
                    , ( "Is Segregated Cash", "True" )
                    , ( "Classify By Counter Party ID", "FRD" )
                    ]
                )

        --[]
        selected =
            selectedNode
                |> Maybe.map (\sN -> nodeData.uid == sN.uid)
                |> Maybe.withDefault False

        --updatedNode =
        --    setNodeHighlight nodeData.uid
        --        (evaluateHighlight dict
        --            (Value.Variable () [ "Type" ])
        --           (withDefault (WildcardPattern ()) nodeData.pattern)
        --        )
        --correctPathNumber =
        --    length nodeData.uid // 2 |> Debug.log ("homie" ++ nodeData.uid)
        --
        --correctPath =
        --    withDefault (Value.Literal () (BoolLiteral True)) (Array.get correctPathNumber (Array.fromList mylist)) |> Debug.log ("the correct path" ++ fromInt correctPathNumber)
        highlight =
            evaluateHighlight dict2
                nodeData.subject
                --correctPath
                (withDefault (WildcardPattern ()) nodeData.pattern)

        --|> Debug.log ("logging " ++ getLabel nodeData.pattern ++ " subbie " ++ nodeData.subject)
    in
    if highlight then
        text (getLabel nodeData.pattern ++ nodeData.subject ++ "  Highlight")
            |> toUnstyled
        --|> Debug.log dict

    else
        text (getLabel nodeData.pattern ++ nodeData.subject)
            |> toUnstyled

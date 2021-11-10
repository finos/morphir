module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

--import Html.Styled.Events as Events
--import Html.Styled.Attributes exposing (class, css, id, placeholder, value)
--import Html.Styled exposing (Html, button, div, fromUnstyled, map, option, select, text, toUnstyled)

import Browser
import Css exposing (auto, px, width)
import Dict exposing (Dict)
import Element exposing (Color, Element, column, el, fill, html, layout, mouseOver, none, padding, paddingEach, paddingXY, px, rgb, row, shrink, spacing, table, text)
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Html exposing (Html, button, label, map, option, select)
import Html.Attributes exposing (class, disabled, for, id, selected, value)
import Html.Events exposing (onClick, onInput)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value(..), ifThenElse, patternMatch, toString, unit, variable)
import Morphir.Visual.Components.MultiaryDecisionTree
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Mwc.Button
import Mwc.TextField
import Parser exposing (number)
import String exposing (fromInt)
import Tree as Tree
import TreeView as TreeView


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
    }


getLabel : Maybe (Pattern ()) -> String
getLabel maybeLabel =
    case maybeLabel of
        Just label ->
            ViewPattern.patternAsText label ++ " - "

        Nothing ->
            ""



-- ViewPattern.patternAsText(node.data.pattern) ++ "->" ++ node.data.subject
-- define a function to calculate the text representation of a node


nodeLabel : Tree.Node NodeData -> String
nodeLabel n =
    case n of
        Tree.Node node ->
            getLabel node.data.pattern ++ node.data.subject



-- define another function to calculate the uid of a node


nodeUid : Tree.Node NodeData -> TreeView.NodeUid String
nodeUid n =
    case n of
        Tree.Node node ->
            TreeView.NodeUid node.data.uid



-- walk through wire frame
-- confused why top level doesnt have anything corresponding


initialModel : () -> ( Model, Cmd Msg )
initialModel () =
    let
        rootNodes =
            listToNode
                [ Value.patternMatch ()
                    --key "Type"
                    (Value.Variable () [ "Type" ])
                    [ ( Value.LiteralPattern () (StringLiteral "1")
                      , Value.IfThenElse ()
                            (Value.Variable () [ "Cash" ])
                            (Value.IfThenElse ()
                                (Value.Variable () [ "Is Central Bank" ])
                                (Value.IfThenElse ()
                                    (Value.Variable () [ "Is Segregated Cash" ])
                                    (Value.PatternMatch ()
                                        (Value.Variable () [ "Classify By Counter Party ID" ])
                                        [ ( Value.LiteralPattern () (StringLiteral "FRD"), Value.Variable () [ "1.A.4.1" ] )
                                        , ( Value.LiteralPattern () (StringLiteral "BOE"), Value.Variable () [ "1.A.4.2" ] )
                                        ]
                                    )
                                    (Value.PatternMatch ()
                                        (Value.Variable () [ "Classify By Counter Party ID" ])
                                        [ ( Value.LiteralPattern () (StringLiteral "FRD"), Value.Variable () [ "1.A.4.1" ] )
                                        , ( Value.LiteralPattern () (StringLiteral "BOE"), Value.Variable () [ "1.A.4.2" ] )
                                        ]
                                    )
                                )
                                (Value.Variable () [ "Is Segregated Cash" ])
                            )
                            --,
                            (Value.IfThenElse ()
                                (Value.Variable () [ "Is On Shore" ])
                                (Value.IfThenElse ()
                                    (Value.Variable () [ "Is NetUsd Amount Negative" ])
                                    (Value.Variable () [ "O.W.9" ])
                                    (Value.PatternMatch ()
                                        (Value.Variable () [ "Is Feed44 and CostCenter Not 5C55" ])
                                        [ ( Value.LiteralPattern () (StringLiteral "Yes"), Value.Variable () [ "1.U.1" ] )
                                        , ( Value.LiteralPattern () (StringLiteral "Yes"), Value.Variable () [ "1.U.4" ] )
                                        ]
                                    )
                                )
                                (Value.IfThenElse ()
                                    (Value.Variable () [ "Is NetUsd Amount Negative" ])
                                    (Value.Variable () [ "O.W.10" ])
                                    (Value.PatternMatch ()
                                        (Value.Variable () [ "Is Feed44 and CostCenter Not 5C55" ])
                                        [ ( Value.LiteralPattern () (StringLiteral "Yes"), Value.Variable () [ "1.U.2" ] )
                                        , ( Value.LiteralPattern () (StringLiteral "Yes"), Value.Variable () [ "1.U.4" ] )
                                        ]
                                    )
                                )
                            )
                      )

                    --whole thing is value
                    , ( Value.LiteralPattern () (StringLiteral "2"), Value.Variable () [ "Inventory" ] )
                    , ( Value.LiteralPattern () (StringLiteral "3"), Value.Variable () [ "Pending Trades" ] )
                    ]
                ]
    in
    ( { rootNodes = rootNodes
      , treeModel = TreeView.initializeModel configuration rootNodes
      , selectedNode = Nothing
      , favouriteRoot = Normal Nothing
      , selectedRoot = "Unselected"
      , favouriteBank = Normal Nothing
      , selectedBank = "Unselected"
      , favouriteCash = Normal Nothing
      , selectedCash = "Unselected"
      , favouriteClassify = Normal Nothing
      , selectedClassify = "Unselected"
      , favouriteFed = Normal Nothing
      , selectedFed = "Unselected"
      , favouriteExample = Normal Nothing
      , dict = Dict.empty
      }
    , Cmd.none
    )



-- initialize the TreeView model


type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String Never ()
    , selectedNode : Maybe NodeData
    , favouriteRoot : Dropdown Choice
    , selectedRoot : String
    , favouriteBank : Dropdown Choice
    , selectedBank : String
    , favouriteCash : Dropdown Choice
    , selectedCash : String
    , favouriteClassify : Dropdown Choice
    , selectedClassify : String
    , favouriteFed : Dropdown Choice
    , selectedFed : String
    , favouriteExample : Dropdown Example
    , dict : Dict String String
    }



-- otherwise interact with your tree view in the usual TEA manner


type Msg
    = TreeViewMsg (TreeView.Msg String)
    | ExpandAll
    | CollapseAll
    | RootDropdown (DropdownAction Choice)
    | BankDropdown (DropdownAction Choice)
    | CashDropdown (DropdownAction Choice)
    | ClassifyDropdown (DropdownAction Choice)
    | FedDropdown (DropdownAction Choice)
    | ExampleDropdown (DropdownAction Example)
    | SetRoot String
    | SetBank String
    | SetSegCash String
    | SetCode String
    | SetShore String
    | SetNegative String
    | SetFeed String
    | RedoTree


update : Msg -> Model -> ( Model, Cmd Msg )
update message model =
    case message of
        RootDropdown action ->
            case action of
                OpenList ->
                    ( { model | favouriteRoot = Select rootList }, Cmd.none )

                ClickedOption root ->
                    --({model | favouriteRoot = Normal (Just root)}, Cmd.none)
                    ( { model | selectedRoot = root.name }, Cmd.none )

        BankDropdown action ->
            case action of
                OpenList ->
                    ( { model | favouriteBank = Select bankList }, Cmd.none )

                ClickedOption bank ->
                    --({model | favouriteRoot = Normal (Just root)}, Cmd.none)
                    ( { model | selectedBank = bank.name }, Cmd.none )

        CashDropdown action ->
            case action of
                OpenList ->
                    ( { model | favouriteCash = Select cashList }, Cmd.none )

                ClickedOption cash ->
                    --({model | favouriteRoot = Normal (Just root)}, Cmd.none)
                    ( { model | selectedCash = cash.name }, Cmd.none )

        ClassifyDropdown action ->
            case action of
                OpenList ->
                    ( { model | favouriteClassify = Select classifyList }, Cmd.none )

                ClickedOption classify ->
                    --({model | favouriteRoot = Normal (Just root)}, Cmd.none)
                    ( { model | selectedClassify = classify.name }, Cmd.none )

        FedDropdown action ->
            case action of
                OpenList ->
                    ( { model | favouriteFed = Select fedList }, Cmd.none )

                ClickedOption fed ->
                    --({model | favouriteRoot = Normal (Just root)}, Cmd.none)
                    ( { model | selectedFed = fed.name }, Cmd.none )

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
                        TreeViewMsg tvMsg ->
                            TreeView.update tvMsg model.treeModel

                        ExpandAll ->
                            TreeView.expandAll model.treeModel

                        CollapseAll ->
                            TreeView.collapseAll model.treeModel

                        --   V this should never be hit V
                        _ ->
                            TreeView.expandAll model.treeModel
            in
            ( { model
                | treeModel = treeModel
                , selectedNode = TreeView.getSelected treeModel |> Maybe.map .node |> Maybe.map Tree.dataOf
              }
            , Cmd.none
            )


type Dropdown a
    = Normal (Maybe a)
    | Select (List a)


type DropdownAction a
    = OpenList
    | ClickedOption a


type alias Choice =
    { name : String }


type alias Example =
    { name : String }


bankList : List Choice
bankList =
    [ Choice "Central Bank"
    , Choice "On Shore"
    ]


cashList : List Choice
cashList =
    [ Choice "Segregated"
    , Choice "Not Segregated"
    ]


classifyList : List Choice
classifyList =
    [ Choice "By Counter Party ID"
    , Choice "No Counter Party ID"
    ]


fedList : List Choice
fedList =
    [ Choice "FRD"
    , Choice "BOE"
    , Choice "SNB"
    , Choice "ECB"
    , Choice "BOJ"
    , Choice "RBA"
    , Choice "BOC"
    , Choice "Others"
    ]


rootList : List Choice
rootList =
    [ Choice "Cash"
    , Choice "Inventory"
    , Choice "Pending Trades"
    ]


exampleList : List Example
exampleList =
    [ Example "option 1"
    , Example "option 2"
    , Example "option 3"
    ]


overColor : Color
overColor =
    rgb 0.9 0.9 0.1


white : Color
white =
    rgb 1 1 1


dropdownView : Dropdown a -> (a -> String) -> (DropdownAction a -> Msg) -> Element Msg
dropdownView dropdownState toString toMsg =
    let
        selectedName =
            case dropdownState of
                Normal (Just someA) ->
                    toString someA

                _ ->
                    "Click to select"

        menu : Element Msg
        menu =
            case dropdownState of
                Select options ->
                    let
                        mouseOverColor : Color
                        mouseOverColor =
                            rgb 0.9 0.9 0.1

                        backgroundColor : Color
                        backgroundColor =
                            rgb 1 1 1

                        viewOption : a -> Element Msg
                        viewOption option =
                            el
                                [ Element.width Element.fill
                                , Element.mouseOver [ Background.color overColor ]
                                , Background.color white
                                , Events.onClick (toMsg (ClickedOption option))
                                ]
                                (t <| toString option)

                        viewOptionList : List a -> Element Msg
                        viewOptionList inputOptions =
                            column [] <|
                                List.map viewOption inputOptions
                    in
                    el
                        [ Border.width 1
                        , Border.dashed
                        , padding 3
                        , Element.below (viewOptionList options)
                        ]
                        (t selectedName)

                _ ->
                    el
                        [ Border.width 1
                        , Border.dashed
                        , padding 3
                        , Events.onClick (toMsg OpenList)
                        ]
                        (t selectedName)
    in
    menu



-- avilitiy to view tree
--key is branches, value is string for case or True/False for if else


view : Model -> Html.Html Msg
view model =
    --layout [] dropdown
    Html.div
        [ id "top-level" ]
        [ dropdowns model
        , map TreeViewMsg (TreeView.view model.treeModel)
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
        , Html.div [ id "all-dropdowns" ]
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


configuration : TreeView.Configuration NodeData String
configuration =
    TreeView.Configuration nodeUid nodeLabel TreeView.defaultCssClasses



-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)


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
                    NodeData uid (Value.toString condition) pattern

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
                    NodeData uid (Value.toString param) pattern

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

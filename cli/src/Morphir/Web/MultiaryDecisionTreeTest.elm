module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
--import Html.Styled.Events as Events
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value(..), toString, unit, variable)

import Dict
import Element exposing (Color, Element, column, el, fill, html, layout, mouseOver, none, padding, paddingEach, px, rgb, row, shrink, spacing, table, text)
--import Html.Styled.Attributes exposing (class, css, id, placeholder, value)
import Html exposing (Html, map)


--import Html.Styled exposing (Html, button, div, fromUnstyled, map, option, select, text, toUnstyled)

import Css exposing (auto, px, width)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (ifThenElse, patternMatch)
import Morphir.Visual.Components.MultiaryDecisionTree
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)
import Parser exposing (number)
import String exposing (fromInt)
import Tree as Tree
import TreeView as TreeView
import Mwc.Button
import Mwc.TextField

t = Element.text
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
type alias NodeData = {
    uid : String
    , subject : String
    , pattern : Maybe (Pattern())
    }

getLabel : Maybe (Pattern()) -> String
getLabel maybeLabel =
    case maybeLabel of
        Just label -> ViewPattern.patternAsText(label) ++ " - "
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

-- walk through wire frame
-- confused why top level doesnt have anything corresponding

initialModel : () -> (Model, Cmd Msg)
initialModel () =
    let
        rootNodes =

            listToNode [
                (Value.patternMatch () (Value.Variable () ["Type"])
                [
                (( Value.LiteralPattern () (StringLiteral "1")), ( Value.IfThenElse () (Value.Variable () ["Cash"])
                        (Value.IfThenElse () (Value.Variable () ["Is Central Bank"])
                            ( Value.IfThenElse () (Value.Variable () ["Is Segregated Cash"])
                                (Value.PatternMatch () (Value.Variable () ["Classify By Counter Party ID"]) [
                                    ( Value.LiteralPattern () (StringLiteral "FRD"), (Value.Variable () ["1.A.4.1"]))
                                  , ( Value.LiteralPattern () (StringLiteral "BOE"), (Value.Variable () ["1.A.4.2"]))
                                  ])
                                (Value.PatternMatch () (Value.Variable () ["Classify By Counter Party ID"]) [
                                  ( Value.LiteralPattern () (StringLiteral "FRD"), (Value.Variable () ["1.A.4.1"]))
                                , ( Value.LiteralPattern () (StringLiteral "BOE"), (Value.Variable () ["1.A.4.2"]))
                                ])
                            ) (Value.Variable () ["Is Segregated Cash"]) ) --,
                        ( Value.IfThenElse () (Value.Variable () ["Is On Shore"])
                            ( Value.IfThenElse () (Value.Variable () ["Is NetUsd Amount Negative"])
                                (Value.Variable () ["O.W.9"])
                                (Value.PatternMatch () (Value.Variable () ["Is Feed44 and CostCenter Not 5C55"]) [
                                  ( Value.LiteralPattern () (StringLiteral "Yes"), (Value.Variable () ["1.U.1"]))
                                , ( Value.LiteralPattern () (StringLiteral "Yes"), (Value.Variable () ["1.U.4"]))
                                ])
                            )
                            ( Value.IfThenElse () (Value.Variable () ["Is NetUsd Amount Negative"])
                                (Value.Variable () ["O.W.10"])
                                (Value.PatternMatch () (Value.Variable () ["Is Feed44 and CostCenter Not 5C55"]) [
                                  ( Value.LiteralPattern () (StringLiteral "Yes"), (Value.Variable () ["1.U.2"]))
                                , ( Value.LiteralPattern () (StringLiteral "Yes"), (Value.Variable () ["1.U.4"]))
                                ])
                            )

                         )
                    ) ),
                (( Value.LiteralPattern () (StringLiteral "2")), (Value.Variable () ["Inventory"] ))
                , (( Value.LiteralPattern () (StringLiteral "3")), (Value.Variable () ["Pending Trades"]))
                ] )
               ]
    in
        ( { rootNodes = rootNodes
        , treeModel = TreeView.initializeModel configuration rootNodes
        , selectedNode = Nothing
        , favouriteFood = Normal Nothing
        , favouriteExample = Normal Nothing
        }
        , Cmd.none
        )

-- initialize the TreeView model
type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String Never ()
    , selectedNode : Maybe NodeData
    , favouriteFood: Dropdown Food
    , favouriteExample : Dropdown Example
    }

-- otherwise interact with your tree view in the usual TEA manner
type Msg =
  TreeViewMsg (TreeView.Msg String)
  | ExpandAll
  | CollapseAll
  | FoodDropdown (DropdownAction Food)
  | ExampleDropdown (DropdownAction Example)


update : Msg -> Model -> (Model, Cmd Msg)
update message model =
    case message of
        FoodDropdown action ->
            case action of
                OpenList ->
                    ({model | favouriteFood  = Select foodList}, Cmd.none)
                ClickedOption food ->
                    ({model | favouriteFood = Normal (Just food)}, Cmd.none)
        ExampleDropdown action ->
            case action of
                OpenList ->
                    ({ model | favouriteExample = Select exampleList}, Cmd.none)
                ClickedOption example ->
                    ({model | favouriteExample = Normal (Just example)}, Cmd.none)
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
                }, Cmd.none )

type Dropdown a
    = Normal (Maybe a)
    | Select (List a)

type DropdownAction a
    = OpenList
    | ClickedOption a

type alias Food =
    { name : String}

type alias Example =
    {name : String}

foodList : List Food
foodList =
    [ Food "Cash"
    , Food "Inventory"
    , Food "Pending Trades"
    ]

exampleList : List Example
exampleList =
    [ Example "option 1"
    , Example "option 2"
    , Example "option 3"
    ]


overColor : Color
overColor = rgb 0.9 0.9 0.1

white : Color
white = rgb 1 1 1

dropdownView : Dropdown a -> (a -> String) -> (DropdownAction a -> Msg) -> Element Msg
dropdownView dropdownState toString toMsg =
    let
        selectedName =
            case dropdownState of
                Normal (Just someA) -> toString someA
                _ -> "Click to select"
        menu : Element Msg
        menu =
            case dropdownState of
                Select options ->
                    let
                        mouseOverColor : Color
                        mouseOverColor = rgb 0.9 0.9 0.1

                        backgroundColor : Color
                        backgroundColor = rgb 1 1 1

                        viewOption : a -> Element Msg
                        viewOption option =
                            el
                                [ Element.width Element.fill
                                , Element.mouseOver [Background.color overColor]
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
view : Model -> Html.Html Msg
view model =

        --layout [] dropdown
        Html.div
            [ ]
            [ layout [] (dropdownView model.favouriteFood .name FoodDropdown)
            , layout [] (dropdownView model.favouriteExample .name ExampleDropdown)
            , map TreeViewMsg (TreeView.view model.treeModel)
            ]





--
main =
    Browser.element
        {
        init = initialModel,
        view = view,
        update = update,
        subscriptions = subscriptions
        }

--construct a configuration for your tree view
configuration : TreeView.Configuration NodeData String
configuration =
    TreeView.Configuration nodeUid nodeLabel TreeView.defaultCssClasses

-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)

toMaybeList : List(Pattern(), Value () () ) -> List(Maybe(Pattern()), Value () () )
toMaybeList list =
    let
        patterns = List.map Tuple.first list
        maybePatterns = List.map Just patterns
        values = List.map Tuple.second list
    in
        List.map2 Tuple.pair maybePatterns values


-- pass in a bunch of variables
-- call the enterpreteur to do any business logic

listToNode : List (Value () () ) -> List (Tree.Node NodeData)
listToNode values =
    let
        uids = List.range 1 (List.length values)
    in
        List.map2 toTranslate values uids

toTranslate : Value () () -> Int -> Tree.Node NodeData
toTranslate value uid =
    translation2 (Nothing, value) (fromInt uid)

-- Tree.Node NodeData
translation2 : (Maybe (Pattern()), Value () ())-> String -> Tree.Node NodeData
translation2 (pattern, value) uid  =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let

                data = NodeData (uid) (Value.toString condition) pattern
                uids = createUIDS 2 uid
                list = [(Just( Value.LiteralPattern () (BoolLiteral True)), thenBranch), (Just( Value.LiteralPattern () (BoolLiteral False)), elseBranch) ]
                children : List ( Tree.Node NodeData )
                children = List.map2 translation2 list uids

            in
                Tree.Node {
                 data = data, children = children
                }

        Value.PatternMatch tpe param patterns ->
            let
                data = NodeData uid (Value.toString param) pattern
                maybePatterns = (toMaybeList patterns)
                uids = createUIDS (List.length maybePatterns) uid
                children : List ( Tree.Node NodeData )
                children = List.map2 translation2 maybePatterns uids
            in
                Tree.Node {
                 data = data, children = children
                }
        _ ->
            --Value.toString value ++ (fromInt uid) ++ " ------ "
            Tree.Node { data = NodeData uid (Value.toString value) pattern, children = [] }

createUIDS : Int -> String -> List ( String )
createUIDS range currentUID =
    let
        intRange = List.range 1 range
        stringRange = List.map fromInt intRange
        appender int = String.append (currentUID ++ ".") int

    in
        List.map appender stringRange

module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
import Maybe exposing (withDefault)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Value as Value exposing (Pattern(..), RawValue, Value(..), toString, unit, variable)
import Morphir.ListOfResults as ListOfResults
import Dict exposing (Dict)
import Element exposing (Element, column, el, fill, html, layout, none, padding, paddingEach, px, row, shrink, spacing, table)
import Html.Styled.Attributes exposing (class, css, id, placeholder, value)
import Html exposing (a)
import Morphir.SDK.Bool exposing (false, true)
import Morphir.Value.Error as Error exposing (Error, PatternMismatch)
import Morphir.Value.Interpreter as Interpreter
import Html.Styled exposing (Html, div, fromUnstyled, map, option, select, text, toUnstyled)

import Css exposing (auto, px, width)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal as Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (ifThenElse, patternMatch)
import Morphir.Value.Native as Native
import Morphir.Visual.Components.DecisionTable exposing (Match(..))
import Morphir.Visual.Components.MultiaryDecisionTree
import Morphir.Visual.Config as Config exposing (Config, HighlightState(..))
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
type alias NodeData = {
    uid : String
    , subject : String
    , pattern : Maybe (Pattern())
    , highlight : Bool
    }

type alias Variables =
    Dict Name RawValue

--Pass in values from the dropdowns
--This will give us back a value we use to highlight
evaluateHighlight : Dict Name RawValue -> RawValue -> Pattern () -> Bool
evaluateHighlight variable value pattern =
   let
       evaluation =
        Interpreter.evaluateValue (Dict.empty) IR.empty variable [] value
   in
   case evaluation of
        Ok val ->
            if ((Interpreter.matchPattern pattern val) ==
                    Err (Error.PatternMismatch pattern value)) then
                false
            else
                true
        Err e -> false


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
        }
        , Cmd.none
        )

-- initialize the TreeView model
type alias Model =
    { rootNodes : List (Tree.Node NodeData)
    , treeModel : TreeView.Model NodeData String Never ()
    ,  selectedNode : Maybe NodeData
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

--highlightText : Html msg
--highlightText = evaluateHighlight

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

-- avilitiy to view tree
view : Model -> Html Msg
view model =
        div
            [ css [width (auto)]]
            [
            select [id "first"] [option [value "0"] [text "Cash"], option [value "1"] [text "Inventory"], option [value "2"] [text "Pending Trades"]]
            , select [id "bank-type", class "sub-selector"] [option [value "0"] [text "Central Bank"], option [value "1"] [text "Onshore"]]
            , select [id "cash-type", class "sub-selector"] [option [value "0"] [text "Segregated Cash"], option [value "1"] [text "Not"]]
            , select [id "negative-type", class "hidden-on-start sub-selector"] [option [value "0"] [text "NetUSD is Negative"], option [value "1"] [text "NetUSD is Positive"]]
            --, select [id "classify-type"] [option [] [text "Classify by Counter-Party ID"], option [] [text "Don't"]]
            --, select [id "bottom-level"] [option [] [text "FRD"], option [] [text "BOE"], option [] [text "SNB"]
            --    , option [] [text "ECB"], option [] [text "BOJ"], option [] [text "RBA"]
            --    , option [] [text "BOC"], option [] [text "Others"]]
            , selectedNodeDetails model
            , map TreeViewMsg (TreeView.view model.treeModel |> fromUnstyled)

            ]


-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)


--
main =
    Browser.element
        {
        init = initialModel,
        view = view >> toUnstyled,
        update = update,
        subscriptions = subscriptions
        }
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
                dict : Dict (List String) (Value () ())
                dict =
                   Dict.fromList[(["Cash"], (Value.Variable () ["Cash"]))]
                data = NodeData (uid) (Value.toString condition) pattern false
                --(evaluateHighlight dict value (withDefault Value.LiteralPattern() (pattern)))
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
                dict : Dict String (Value () ())
                dict =
                   Dict.fromList[("Cash", (Value.Variable () ["Cash"]))]
                data = NodeData uid (Value.toString param) pattern false
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
            Tree.Node { data = NodeData uid (Value.toString value) pattern false, children = []}

createUIDS : Int -> String -> List ( String )
createUIDS range currentUID =
    let
        intRange = List.range 1 range
        stringRange = List.map fromInt intRange
        appender int = String.append (currentUID ++ ".") int

    in
        List.map appender stringRange

--getLabel: Maybe (Pattern ()) -> String
--
--getLabel pattern =
--    Element.table []
--            { data = pattern
--            , columns =
--                [ { header = none
--                  , width = px 150
--                  , view =
--                        \myLabel ->
--                            ViewPattern.patternAsText(pattern)
--                  }
--                , { header = none
--                  , width = px 150
--                  , view =
--                        \myLabel ->
--                            "  ->  "
--                  }
--                ]
--            }
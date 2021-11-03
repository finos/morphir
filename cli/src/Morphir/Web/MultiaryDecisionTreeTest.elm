module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Browser
import Morphir.IR.Value as Value exposing (Pattern, RawValue, Value(..), toString, unit, variable)

import Dict
import Element exposing (Element, column, el, fill, layout, none, padding, paddingEach, px, row, shrink, spacing, table, text)
import Html.Styled.Attributes exposing (css)
import Html exposing (a)

import Html.Styled exposing (Html, div, fromUnstyled, map, toUnstyled, var)
import Css exposing (auto, px, width)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
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
        Just label -> ViewPattern.patternAsText(label) ++ "  ->  "
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


initialModel : () -> (Model, Cmd Msg)
initialModel () =
    let
        rootNodes =
            [translation2
                (Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes"]) (Value.IfThenElse () (Value.Variable () ["isBar"]) (Value.Variable () ["Yes"]) (Value.Variable () ["No"]))) 1 Nothing
            ]
            --[ Tree.Node
            --    { children =
            --        [ Tree.Node { children = [], data = NodeData "1.1" "Yes" (Just (Value.LiteralPattern () (BoolLiteral True)))}
            --        , Tree.Node { children = [], data = NodeData "1.2" "No" (Just (Value.LiteralPattern () (BoolLiteral False)))} ],
            --        data = NodeData "1" "isFoo" Nothing
            --    }
            --, Tree.Node
            --    { children =
            --        [ Tree.Node
            --        {
            --        children = [ Tree.Node
            --                    { children = [], data = NodeData "2.1.1" "YesAndYes"  (Just( Value.LiteralPattern () (BoolLiteral True))) },
            --                    Tree.Node
            --                    { children = [], data = NodeData "2.1.2" "YesAndNo"  (Just( Value.LiteralPattern () (BoolLiteral True)))} ]
            --        ,
            --        data = NodeData "2.1" "isBar"  (Just( Value.LiteralPattern () (BoolLiteral True)))},
            --         Tree.Node
            --         {
            --         children = [],
            --         data = NodeData "2.2" "No"  (Just ( Value.LiteralPattern () (BoolLiteral False)))}
            --         ]
            --
            --    , data = NodeData "2" "isFoo" Nothing
            --    }
            ----- Value.patternMatch () (Variable.Value () "enum")
            ----  List (
            --  , Tree.Node
            --    { children = [
            --    Tree.Node {
            --        children = [],
            --        data = NodeData "3.1" "foo" (Just ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") []))
            --        },
            --    Tree.Node {
            --        children = [],
            --        data = NodeData "3.2" "bar" (Just ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") []))
            --        },
            --    Tree.Node {
            --        children = [],
            --        data = NodeData "3.3" "baz" (Just ( Value.WildcardPattern ()))
            --        }
            --    ],
            --    data = NodeData "3" "enum" Nothing
            --
            --    }
            --]
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
    , selectedNode : Maybe NodeData
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
            [ expandAllCollapseAllButtons
            , selectedNodeDetails model
            , map TreeViewMsg (TreeView.view model.treeModel |> fromUnstyled)

            ]


-- if (or when) you want the tree view to navigate up/down between visible nodes and expand/collapse nodes on arrow key presse
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map TreeViewMsg (TreeView.subscriptions model.treeModel)



main =
    Browser.element
        {
        init = initialModel,
        view = view >> toUnstyled,
        update = update,
        subscriptions = subscriptions
        }


-- translation should take in a value and its parameters and a unid
-- Tree.Node NodeData
translation : Value () ()-> Int -> String
translation value uid =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let
                data = NodeData (fromInt uid) (Value.toString condition) Nothing

                children : List ( Tree.Node data )
                children = []

                newid = uid + 1
            in
                --Tree.Node {
                -- data = data, children = children
                --}
                --

                toString condition ++ " -- CONDISH -- " ++ (fromInt uid) ++ "< -- uid" ++ (fromInt newid) ++ "< -- newid" ++ translation thenBranch newid ++ translation elseBranch newid

        --Value.PatternMatch tpe param patterns ->
        _ ->
            Value.toString value ++ (fromInt uid) ++ " ------ "
            --Tree.Node { data = NodeData "cara" "is" Nothing, children = [] }

-- Tree.Node NodeData
translation2 : Value () ()-> Int -> Maybe (Pattern()) -> Tree.Node NodeData
translation2 value uid pattern =
    case value of
        Value.IfThenElse _ condition thenBranch elseBranch ->
            let

                data = NodeData (fromInt uid) (Value.toString condition) pattern
                newid = uid + 1
                children : List ( Tree.Node NodeData )
                children = [translation2 thenBranch newid (Just( Value.LiteralPattern () (BoolLiteral True))),
                            translation2 elseBranch newid (Just( Value.LiteralPattern () (BoolLiteral False)))
                    ]
            in
                Tree.Node {
                 data = data, children = children
                }



        --Value.PatternMatch tpe param patterns ->
        _ ->
            --Value.toString value ++ (fromInt uid) ++ " ------ "
            Tree.Node { data = NodeData (fromInt uid) (Value.toString value) pattern, children = [] }


--main =
--    layout
--            []
--            <|
--            (el [ padding 10 ]
--
--                --(Element.text (Value.toString (Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes"])
--                --(Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes"]) (Value.Variable () ["No"]))
--                --
--                -- (Element.text
--                --    (translation
--                --        (Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes"])(Value.Variable () ["No"])) "1"
--                --    )
--                -- )
--                --(Element.text
--                --    (translation
--                --        (Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes1"]) (Value.IfThenElse () (Value.Variable () ["isBar"]) (Value.Variable () ["Yes2"]) (Value.Variable () ["No"]))) 1
--                --    )
--                --)
--                --(Element.text
--                --    (translation2
--                --        (Value.IfThenElse () (Value.Variable () ["isFoo"]) (Value.Variable () ["Yes1"]) (Value.IfThenElse () (Value.Variable () ["isBar"]) (Value.Variable () ["Yes2"]) (Value.Variable () ["No"]))) 1
--                --    )
--                --)
--
--
--            )



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
module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Array exposing (Array)
import Browser
import Dict
import Element exposing (Element, column, el, layout, none, padding, paddingEach, row, spacing, text)
import Element.Events exposing (onClick)
import Html exposing (Html)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.Components.TreeLayout as TreeLayout
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Set exposing (Set)


main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


type alias NodePath =
    List Int


type alias Model =
    { treeModels : Array TreeModel
    }


type alias TreeModel =
    { collapsedPaths : Set NodePath
    , selectedPath : Maybe NodePath
    }


initTreeModel : TreeModel
initTreeModel =
    { collapsedPaths = Set.empty
    , selectedPath = Nothing
    }


init : Model
init =
    { treeModels =
        trees
            |> List.map (always initTreeModel)
            |> Array.fromList
    }


update : Msg -> Model -> Model
update msg model =
    let
        updateTreeModel : Int -> (TreeModel -> TreeModel) -> Model
        updateTreeModel treeID f =
            { model
                | treeModels =
                    model.treeModels
                        |> Array.set treeID
                            (model.treeModels
                                |> Array.get treeID
                                |> Maybe.map f
                                |> Maybe.withDefault initTreeModel
                            )
            }
    in
    case msg of
        Collapse treeID nodePath ->
            updateTreeModel treeID
                (\treeModel ->
                    { treeModel
                        | collapsedPaths =
                            treeModel.collapsedPaths
                                |> Set.insert nodePath
                    }
                )

        Expand treeID nodePath ->
            updateTreeModel treeID
                (\treeModel ->
                    { treeModel
                        | collapsedPaths =
                            treeModel.collapsedPaths
                                |> Set.remove nodePath
                    }
                )

        Select treeID nodePath ->
            updateTreeModel treeID
                (\treeModel ->
                    { treeModel
                        | selectedPath =
                            Just nodePath
                    }
                )

        NoMsg ->
            model


view : Model -> Html Msg
view model =
    layout
        []
        (el [ padding 10 ]
            (column [ spacing 20 ]
                (trees
                    |> List.indexedMap
                        (\treeID node ->
                            column [ spacing 10 ]
                                [ text ("Example " ++ String.fromInt (treeID + 1))
                                , TreeLayout.view TreeLayout.defaultTheme
                                    { onCollapse = Collapse treeID
                                    , onExpand = Expand treeID
                                    , collapsedPaths =
                                        model.treeModels
                                            |> Array.get treeID
                                            |> Maybe.map .collapsedPaths
                                            |> Maybe.withDefault Set.empty
                                    , selectedPaths =
                                        model.treeModels
                                            |> Array.get treeID
                                            |> Maybe.andThen .selectedPath
                                            |> Maybe.map Set.singleton
                                            |> Maybe.withDefault Set.empty
                                    }
                                    (viewNode (Select treeID) node)
                                ]
                        )
                )
            )
        )


viewNode : (NodePath -> Msg) -> Node -> TreeLayout.Node Msg
viewNode handleClick node =
    case node of
        Branch branch ->
            TreeLayout.Node
                (\nodePath ->
                    el [ onClick (handleClick nodePath) ]
                        (ViewValue.viewValue dummyConfig branch.subject)
                )
                Array.empty
                (branch.branches |> List.map (\( pattern, childNode ) -> viewNode handleClick childNode))

        Leaf visualTypedValue ->
            TreeLayout.Node
                (\nodePath ->
                    el [ onClick (handleClick nodePath) ]
                        (ViewValue.viewValue dummyConfig visualTypedValue)
                )
                Array.empty
                []


type Msg
    = Collapse Int NodePath
    | Expand Int NodePath
    | Select Int NodePath
    | NoMsg


trees : List Node
trees =
    let
        dummyAnnotation i =
            ( i, Type.Unit () )

        var i name =
            Value.Variable (dummyAnnotation i) (Name.fromString name)
    in
    [ Branch
        { subject = var 0 "isFoo"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var 1 "yes") )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var 2 "no") )
            ]
        }
    , Branch
        { subject = var 0 "isFoo"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True)
              , Branch
                    { subject = var 1 "isBar"
                    , subjectEvaluationResult = Nothing
                    , branches =
                        [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var 2 "yesAndYes") )
                        , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var 3 "yesAndNo") )
                        ]
                    }
              )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var 4 "no") )
            ]
        }
    , Branch
        { subject = var 0 "enum"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") [], Leaf (var 1 "foo") )
            , ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") [], Leaf (var 2 "bar") )
            , ( Value.WildcardPattern (), Leaf (var 3 "baz") )
            ]
        }
    ]


dummyConfig : Config Msg
dummyConfig =
    { irContext =
        { distribution = Library [] Dict.empty Package.emptyDefinition
        , nativeFunctions = Dict.empty
        }
    , state =
        { expandedFunctions = Dict.empty
        , variables = Dict.empty
        , popupVariables =
            { variableIndex = -1
            , variableValue = Nothing
            }
        , theme = Theme.fromConfig Nothing
        , highlightState = Nothing
        }
    , handlers =
        { onReferenceClicked = \_ _ -> NoMsg
        , onHoverOver = \_ _ -> NoMsg
        , onHoverLeave = \_ -> NoMsg
        }
    }

module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Ant.Icon exposing (fill, height, width)
import Ant.Icons as Icons
import Dict
import Element exposing (Attribute, Element, column, el, layout, none, padding, paddingEach, paddingXY, row, spacing, spacingXY, text)
import Element.Background as Background
import Elm.Processing exposing (init)
import Html exposing (Html)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (BranchNode, Node(..))
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue
import Element.Input as Input
import Element.Border as Border

import Browser
-- for icons run the following elm install lemol/ant-design-icons-elm-ui


main = Browser.sandbox { init = init, update = update, view = view }
    --layout
    --    []
    --    (el [ padding 10 ]
    --        (column [ spacing 20 ]
    --            (examples
    --                |> List.indexedMap
    --                    (\index example ->
    --                        column [ spacing 10 ]
    --                            [ text ("Example " ++ String.fromInt (index + 1))
    --                            , column [ spacing 5 ] (viewNode 0 Nothing example)
    --                            ]
    --                    )
    --            )
    --        )
    --    )
view model =
    layout
        []
        (el [ padding 10 ]
            (column [ Element.spacing 20 ]
                (examples
                    |> List.indexedMap
                        (\index example ->
                            column [ Element.spacing 10 ]
                                [ text ("Example " ++ String.fromInt (index + 1))
                                , column [ Element.spacing 5 ] (viewNode 0 Nothing example)
                                ]
                        )
                )
            )
        )

type Msg
    = NoMsg
    | Show
    | Hide

blue =
    Element.rgb255 82 107 190

purple =
    Element.rgb255 121 62 145

buttonStyling =
    [Background.color blue,
    paddingXY 10 5,
    Border.rounded 25]

noneTest : Element msg
noneTest =
    Element.none

--give buttons id's
update : Msg  ->  (a -> a)
update msg =
    case msg of
        Show ->
            Debug.log("Showing")
            --{branch | display = True}
            --branch
        Hide ->
            Debug.log("Hiding")
            --{branch | display = False}
        _ ->
            Debug.log("Nothing")

doSomething branch =
    {branch | display = False}





viewNode : Int -> Maybe (Element Msg) -> Node -> List (Element Msg)
viewNode depth maybeLabel node =
    let
        indentRight by =
            paddingEach
                { left = by * 30
                , right = 0
                , top = 0
                , bottom = 0
                }

        label =
            case maybeLabel of
                Just l ->
                    row [] [ l, text " - " ]
                    --row [] [ l,  Icons.homeOutlined []]

                Nothing ->
                    none
    in
    case node of
        Branch branch ->
            case branch.display of
                True ->
                    List.concat
                        [ [ row [ indentRight depth ] [ Input.button buttonStyling  {onPress = Just Hide, label = text "-"}, label, ViewValue.viewValue dummyConfig branch.subject ] ]
                        , branch.branches
                            |> List.concatMap
                                (\( casePattern, caseBody ) ->
                                    viewNode (depth + 1) (Just (text (ViewPattern.patternAsText casePattern))) caseBody
                                )
                        ]
                False ->
                    List.concat
                        [ [ row [ indentRight depth ] [ Input.button buttonStyling  {onPress = Just Show, label = text "+"}, label, ViewValue.viewValue dummyConfig branch.subject ] ]

                        ]

        Leaf visualTypedValue ->
                    [ row [ indentRight depth] [ Icons.caretRightOutlined [width 28], label, ViewValue.viewValue dummyConfig visualTypedValue ] ]


examples =
    let
        dummyAnnotation =
            ( 0, Type.Unit () )

        var name =
            Value.Variable dummyAnnotation (Name.fromString name)
    in
    [ Branch
        { subject = var "isFoo"
        , subjectEvaluationResult = Nothing
        , display = True
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yes") )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "no") )
            ]
        }
    , Branch
        { subject = var "isFoo"
        , subjectEvaluationResult = Nothing
        , display = True
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True)
              , Branch
                    { subject = var "isBar"
                    , subjectEvaluationResult = Nothing
                    , display = False
                    , branches =
                        [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yesAndYes") )
                        , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "yesAndNo") )
                        ]
                    }
              )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "no") )
            ]
        }
    , Branch
        { subject = var "enum"
        , subjectEvaluationResult = Nothing
        , display = True
        , branches =
            [ ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") [], Leaf (var "foo") )
            , ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") [], Leaf (var "bar") )
            , ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue3" ":") [],
             Branch
                {subject = var "is foo"
                , subjectEvaluationResult = Nothing
                , display = True
                , branches =
                    [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yesAndYes") )
                    , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "yesAndNo") )
                    ]
                }
             )
            , ( Value.WildcardPattern (), Leaf (var "baz") )
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

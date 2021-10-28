module Morphir.Web.MultiaryDecisionTreeTest exposing (..)

import Dict
import Element exposing (Element, column, el, layout, none, padding, paddingEach, row, spacing, text)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Visual.Components.MultiaryDecisionTree exposing (Node(..))
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewPattern as ViewPattern
import Morphir.Visual.ViewValue as ViewValue


main =
    layout
        []
        (el [ padding 10 ]
            (column [ spacing 20 ]
                (examples
                    |> List.indexedMap
                        (\index example ->
                            column [ spacing 10 ]
                                [ text ("Example " ++ String.fromInt (index + 1))
                                , column [ spacing 5 ] (viewNode 0 Nothing example)
                                ]
                        )
                )
            )
        )


type Msg
    = NoMsg


viewNode : Int -> Maybe (Element Msg) -> Node -> List (Element Msg)
viewNode depth maybeLabel node =
    let
        indentRight by =
            paddingEach
                { left = by * 20
                , right = 0
                , top = 0
                , bottom = 0
                }

        label =
            case maybeLabel of
                Just l ->
                    row [] [ l, text " -> " ]

                Nothing ->
                    none
    in
    case node of
        Branch branch ->
            List.concat
                [ [ row [ indentRight depth ] [ text " - ", label, ViewValue.viewValue dummyConfig branch.subject ] ]
                , branch.branches
                    |> List.concatMap
                        (\( casePattern, caseBody ) ->
                            viewNode (depth + 1) (Just (text (ViewPattern.patternAsText casePattern))) caseBody
                        )
                ]

        Leaf visualTypedValue ->
            [ row [ indentRight depth ] [ text " - ", label, ViewValue.viewValue dummyConfig visualTypedValue ] ]


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
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True), Leaf (var "yes") )
            , ( Value.LiteralPattern () (BoolLiteral False), Leaf (var "no") )
            ]
        }
    , Branch
        { subject = var "isFoo"
        , subjectEvaluationResult = Nothing
        , branches =
            [ ( Value.LiteralPattern () (BoolLiteral True)
              , Branch
                    { subject = var "isBar"
                    , subjectEvaluationResult = Nothing
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
        , branches =
            [ ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue1" ":") [], Leaf (var "foo") )
            , ( Value.ConstructorPattern () (FQName.fromString "My:Sample:EnumValue2" ":") [], Leaf (var "bar") )
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

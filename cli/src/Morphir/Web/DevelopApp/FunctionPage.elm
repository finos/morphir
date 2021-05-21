module Morphir.Web.DevelopApp.FunctionPage exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, alignRight, alignTop, centerX, centerY, column, el, explain, fill, height, none, padding, paddingXY, px, rgb, rgb255, row, scrollbarX, scrollbars, shrink, spacing, table, text, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (center)
import Element.Input as Input
import Element.Keyed as Keyed
import Element.Lazy as Lazy
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.SDK as SDK
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Type.Infer as Infer
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)
import Morphir.Web.DevelopApp.Common exposing (scaled)
import Morphir.Web.Theme.Light exposing (black, blue, green, orange, red, white)
import Url.Parser as UrlParser exposing ((</>))


type alias Model =
    { functionName : FQName
    , testCaseStates : Dict Int TestCaseState
    }


type alias TestCaseState =
    { testCase : TestCase
    , expandedValues : Dict FQName (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    , argState : Dict Name ValueEditor.EditorState
    , editMode : Bool
    }


type alias Handlers msg =
    { expandReference : Int -> FQName -> Bool -> msg
    , expandVariable : Int -> Int -> Maybe RawValue -> msg
    , shrinkVariable : Int -> Int -> msg
    , argValueUpdated : Int -> Name -> ValueEditor.EditorState -> msg
    , invalidArgValue : Int -> Name -> String -> msg
    , addTestCase : Int -> msg
    , editTestCase : Int -> msg
    , saveTestCase : Int -> msg
    , deleteTestCase : Int -> msg
    , saveTestSuite : Model -> msg
    }


routeParser : UrlParser.Parser (FQName -> a) a
routeParser =
    UrlParser.s "function"
        </> (UrlParser.string
                |> UrlParser.map
                    (\string ->
                        FQName.fromString string ":"
                    )
            )


viewHeader : String -> Element msg
viewHeader heading =
    el [ Font.bold, Font.size (scaled 2), spacing 5, padding 5 ] (text heading)


viewTitle : FQName -> String
viewTitle functionName =
    "Morphir - " ++ (functionName |> FQName.toString |> String.replace ":" " / ")


viewPage : Handlers msg -> Distribution -> Model -> Element msg
viewPage handlers distribution model =
    let
        testCasesNumber =
            Dict.size model.testCaseStates
    in
    Element.column [ width fill, padding 10, spacing 10 ]
        [ el [ Font.bold ] (text (viewTitle model.functionName))
        , saveTestSuiteButton handlers.saveTestSuite model "Save Changes"
        , el [ Font.bold ] (text ("Total Test Cases : " ++ String.fromInt testCasesNumber))
        , if testCasesNumber > 0 then
            column [ width fill, spacing 5 ]
                [ el [ Font.bold, Font.size (scaled 4) ] (text "Scenarios")
                , viewSectionWise handlers distribution model
                ]

          else
            el [ Font.bold ] (text "No test cases found")
        ]


viewSectionWise : Handlers msg -> Distribution -> Model -> Element msg
viewSectionWise handlers distribution model =
    let
        argValues : List ( Name, Type () )
        argValues =
            Distribution.lookupValueSpecification (FQName.getPackagePath model.functionName) (FQName.getModulePath model.functionName) (FQName.getLocalName model.functionName) distribution
                |> Maybe.map
                    (\valueSpec ->
                        valueSpec.inputs
                    )
                |> Maybe.withDefault []

        config : Int -> Config msg
        config index =
            { irContext =
                { distribution = distribution
                , nativeFunctions = SDK.nativeFunctions
                }
            , state =
                { expandedFunctions =
                    Dict.get index model.testCaseStates
                        |> Maybe.map .expandedValues
                        |> Maybe.withDefault Dict.empty
                , variables =
                    Dict.get index model.testCaseStates
                        |> Maybe.map .argState
                        |> Maybe.map
                            (\argStates ->
                                argStates
                                    |> Dict.map
                                        (\_ editorState ->
                                            editorState.lastValidValue
                                                |> Maybe.withDefault (Value.Unit ())
                                        )
                            )
                        |> Maybe.withDefault Dict.empty
                , popupVariables =
                    Dict.get index model.testCaseStates
                        |> Maybe.map .popupVariables
                        |> Maybe.withDefault
                            { variableIndex = 0
                            , variableValue = Nothing
                            }
                , theme = Theme.fromConfig Nothing
                }
            , handlers =
                { onReferenceClicked = handlers.expandReference index
                , onHoverOver = handlers.expandVariable index
                , onHoverLeave = handlers.shrinkVariable index
                }
            }

        references : IR
        references =
            IR.fromDistribution distribution
    in
    Dict.toList model.testCaseStates
        |> List.map
            (\( index, testCaseState ) ->
                let
                    testcase =
                        testCaseState.testCase

                    updatedTestcase =
                        if Dict.isEmpty testCaseState.argState then
                            testcase

                        else
                            { testcase
                                | inputs =
                                    List.map2 Tuple.pair argValues testcase.inputs
                                        |> List.map
                                            (\( ( name, tpe ), rawValue ) ->
                                                case Dict.get name testCaseState.argState of
                                                    Just value ->
                                                        value.lastValidValue
                                                            |> Maybe.withDefault (Value.Unit ())

                                                    Nothing ->
                                                        rawValue
                                            )
                            }
                in
                column [ width fill, padding 10, Background.color (rgb 0.9 0.9 0.9) ]
                    [ row
                        [ width fill
                        , spacing 10
                        ]
                        [ el
                            [ width fill
                            , Font.bold
                            , Font.size (scaled 3)
                            ]
                            (text ("Scenario " ++ String.fromInt (index + 1)))
                        , button handlers.addTestCase index "Clone"
                        , button handlers.deleteTestCase index "Delete"
                        ]
                    , column [ width fill, spacing 5 ]
                        [ viewDescription testCaseState.testCase.description
                        , wrappedRow
                            [ width fill
                            , padding 5
                            , spacing 20
                            , Background.color white
                            ]
                            [ viewInput handlers config index references testCaseState model argValues updatedTestcase

                            --, viewExpectedOutput (config index) references updatedTestcase.expectedOutput
                            , viewExpectedVsActualOutput (config index) references updatedTestcase model.functionName
                            ]
                        , Element.column
                            [ width fill
                            , height fill
                            , spacing 5
                            , padding 5
                            , Background.color (rgb 0.9 0.9 0.9)
                            ]
                            [ viewHeader "EXPLANATION"
                            , el
                                [ width fill
                                , centerY
                                , centerX
                                , spacing 5
                                , padding 5
                                , scrollbarX
                                , Background.color white
                                ]
                                (newFunctionView (config index) distribution updatedTestcase model)
                            ]
                        ]
                    ]
            )
        |> column [ spacing 30, padding 5, width fill ]


newFunctionView : Config msg -> Distribution -> TestCase -> Model -> Element msg
newFunctionView config distribution testcase model =
    let
        state =
            config.state
    in
    Distribution.lookupValueDefinition (QName (FQName.getModulePath model.functionName) (FQName.getLocalName model.functionName)) distribution
        |> Maybe.map
            (\valueDef ->
                ViewValue.viewDefinition
                    { config
                        | state =
                            { state
                                | variables =
                                    if Dict.isEmpty state.variables then
                                        List.map2
                                            (\( name, _, tpe ) rawValue ->
                                                ( name, rawValue )
                                            )
                                            valueDef.inputTypes
                                            testcase.inputs
                                            |> Dict.fromList

                                    else
                                        state.variables
                            }
                    }
                    model.functionName
                    valueDef
            )
        |> Maybe.withDefault
            (text
                (String.join " "
                    [ "Module"
                    , [ FQName.getModulePath model.functionName
                            |> Path.toString Name.toTitleCase "."
                      ]
                        |> String.join "."
                    , "not found"
                    ]
                )
            )


viewDescription : String -> Element msg
viewDescription description =
    column [ paddingXY 0 5 ]
        [ el [ spacing 5, padding 5 ] (text description)
        ]


viewInput : Handlers msg -> (Int -> Config msg) -> Int -> IR -> TestCaseState -> Model -> List ( Name, Type () ) -> TestCase -> Element msg
viewInput handlers config index ir testCaseStateRecord model argValues updatedTestcase =
    column
        [ alignTop
        , spacing 5
        , padding 5
        , Background.color (rgb 0.8 0.85 0.9)
        ]
        [ row [ width fill ]
            [ viewHeader "INPUTS"
            , el [ alignRight ]
                (if testCaseStateRecord.editMode == False then
                    button handlers.editTestCase index "Edit"

                 else
                    button handlers.saveTestCase index "Save"
                )
            ]
        , el
            [ padding 5
            , Background.color (rgb 1 1 1)
            , Border.rounded 5
            ]
            (if testCaseStateRecord.editMode == False then
                List.map2 Tuple.pair argValues updatedTestcase.inputs
                    |> List.map
                        (\( ( name, tpe ), rawValue ) ->
                            ( name
                            , el [ paddingXY 10 5 ] (viewTestCase (config index) ir rawValue)
                            )
                        )
                    |> FieldList.view

             else
                viewArgumentEditors ir handlers model index argValues
            )
        ]


viewExpectedOutput : Config msg -> IR -> RawValue -> Element msg
viewExpectedOutput config references rawValue =
    column
        [ alignTop
        , spacing 5
        , padding 5
        , Background.color (rgb 0.8 0.85 0.9)
        ]
        [ viewHeader "EXPECTED OUTPUT"
        , el
            [ width fill
            , height fill
            , spacing 5
            , padding 5
            , Background.color (rgb 1 1 1)
            , Border.rounded 5
            ]
            (viewTestCase config references rawValue)
        ]


viewExpectedVsActualOutput : Config msg -> IR -> TestCase -> FQName -> Element msg
viewExpectedVsActualOutput config ir testCase fQName =
    let
        evaluateResult =
            evaluateFunctionValue SDK.nativeFunctions ir fQName testCase.inputs
    in
    column
        [ alignTop
        , width shrink
        , height shrink
        , spacing 5
        , padding 5
        , Background.color
            (case evaluateResult of
                Ok rawValue ->
                    if rawValue == testCase.expectedOutput then
                        rgb 0.7 1 0.7

                    else
                        rgb 1 0.7 0.7

                Err _ ->
                    rgb 0.7 0.7 0.7
            )
        ]
        [ viewHeader "EXPECTED / ACTUAL OUTPUT"
        , el
            [ width fill
            , height fill
            , spacing 5
            , padding 5
            , Background.color white
            , Border.rounded 5
            ]
            (case evaluateResult of
                Ok rawValue ->
                    if rawValue == testCase.expectedOutput then
                        el [ center, width fill ] (viewTestCase config ir rawValue)

                    else
                        row [ width fill, height fill, spacing 10 ]
                            [ viewTestCase config ir testCase.expectedOutput
                            , el [ Font.bold ] (text "=/=")
                            , viewTestCase config ir rawValue
                            ]

                Err error ->
                    text (Debug.toString error)
            )
        ]


viewTestCase : Config msg -> IR -> RawValue -> Element msg
viewTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ centerX, centerY, width fill, height fill ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY, width fill, height fill ] (text (Infer.typeErrorToMessage error))


viewArgumentEditors : IR -> Handlers msg -> Model -> Int -> List ( Name, Type () ) -> Element msg
viewArgumentEditors ir handlers model index inputTypes =
    inputTypes
        |> List.map
            (\( argName, argType ) ->
                ( argName
                , ValueEditor.view ir
                    argType
                    (handlers.argValueUpdated index argName)
                    (model.testCaseStates
                        |> Dict.get index
                        |> Maybe.andThen (\record -> Dict.get argName record.argState)
                        |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing)
                    )
                )
            )
        |> FieldList.view


saveTestSuiteButton : (model -> msg) -> model -> String -> Element msg
saveTestSuiteButton handlers model label =
    Element.el
        [ Font.bold
        , Border.solid
        , Border.rounded 3
        , spacing 7
        , padding 7
        , Background.color black
        , Font.color white
        , onClick (handlers model)
        ]
        (Element.text label)


button : (Int -> msg) -> Int -> String -> Element msg
button handlers index label =
    Input.button
        [ Font.bold
        , Border.solid
        , Border.rounded 3
        , spacing 7
        , padding 7
        , Background.color black
        , Font.color white
        ]
        { onPress = Just (handlers index)
        , label = text label
        }


testCaseSeparator : String -> Element msg
testCaseSeparator separatorText =
    let
        horizontalLine : Element msg
        horizontalLine =
            Element.column [ width fill ]
                [ Element.el
                    [ Border.widthEach
                        { top = 0
                        , left = 0
                        , right = 0
                        , bottom = 1
                        }
                    , width fill
                    ]
                    none
                , Element.el [ width fill ] none
                ]
    in
    Element.row [ centerX, width fill, Font.color orange ]
        [ horizontalLine
        , Element.el [ padding 5, Font.bold ] (text separatorText)
        , horizontalLine
        ]

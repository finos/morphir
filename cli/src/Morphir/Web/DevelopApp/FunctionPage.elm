module Morphir.Web.DevelopApp.FunctionPage exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, centerX, centerY, column, el, fill, height, htmlAttribute, none, padding, paddingXY, rgb, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font
import Html.Attributes exposing (style)
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
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Edit as Edit
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)
import Morphir.Web.DevelopApp.Common exposing (scaled)
import Morphir.Web.Theme.Light exposing (black, blue, gray, green, orange, red, white)
import Url.Parser as UrlParser exposing ((</>))


type alias Model =
    { functionName : FQName
    , testCaseStates : Dict Int TestCaseState
    }


type alias TestCaseState =
    { testCase : TestCase
    , expandedValues : Dict FQName (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    , argState : Dict Name RawValue
    , editMode : Bool
    }


type alias Handlers msg =
    { expandReference : Int -> FQName -> Bool -> msg
    , expandVariable : Int -> Int -> Maybe RawValue -> msg
    , shrinkVariable : Int -> Int -> msg
    , argValueUpdated : Int -> Name -> RawValue -> msg
    , invalidArgValue : Int -> Name -> String -> msg
    , addTestCase : Int -> msg
    , editTestCase : Int -> msg
    , saveTestCase : Int -> msg
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
    el [ Font.bold, Font.size (scaled 2), spacing 5, padding 5 ] (text (heading ++ " : "))


viewTitle : FQName -> String
viewTitle functionName =
    "Morphir - " ++ (functionName |> FQName.toString |> String.replace ":" " / ")


viewPage : Handlers msg -> Distribution -> Model -> Element msg
viewPage handlers distribution model =
    Element.column [ padding 10, spacing 10 ]
        [ el [ Font.bold ] (text (viewTitle model.functionName))
        , el [ Font.bold ] (text ("Total Test Cases : " ++ String.fromInt (Dict.size model.testCaseStates)))
        , el [ Font.bold, Font.size (scaled 4) ] (text "TestCases :")
        , viewSectionWise handlers distribution model
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
                                                        value

                                                    Nothing ->
                                                        rawValue
                                            )
                            }
                in
                column [ spacing 5, padding 5 ]
                    [ el [ Font.bold, Font.size (scaled 3), Font.color blue ] (text ("TestCase " ++ String.fromInt index ++ " :"))
                    , addOrEditOrSaveButton handlers.addTestCase index "Add Testcase"
                    , viewDescription testCaseState.testCase.description
                    , viewInput handlers config index references testCaseState model argValues updatedTestcase
                    , viewExpectedOutput (config index) references updatedTestcase.expectedOutput
                    , viewActualOutput (config index) references updatedTestcase model.functionName
                    , Element.column [ spacing 5, padding 5 ]
                        [ viewHeader "FUNCTION"
                        , el [ centerY, centerX, spacing 5, padding 5 ] (newFunctionView (config index) distribution updatedTestcase model)
                        ]
                    ]
            )
        |> List.intersperse (testCaseSeparator "TEST CASE END")
        |> column [ spacing 5, padding 5, width fill ]


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
        [ viewHeader "DESCRIPTION"
        , el [ spacing 5, padding 5 ] (text description)
        ]


viewInput : Handlers msg -> (Int -> Config msg) -> Int -> IR -> TestCaseState -> Model -> List ( Name, Type () ) -> TestCase -> Element msg
viewInput handlers config index references testCaseStateRecord model argValues updatedTestcase =
    column [ spacing 5, padding 5 ]
        [ viewHeader "INPUTS"
        , if testCaseStateRecord.editMode == False then
            column [ spacing 5 ]
                [ addOrEditOrSaveButton handlers.editTestCase index "Edit Inputs"
                , List.map2 Tuple.pair argValues updatedTestcase.inputs
                    |> List.map
                        (\( ( name, tpe ), rawValue ) ->
                            column
                                [ spacing 5, padding 5, width fill, height fill ]
                                [ el [ Font.bold ]
                                    (text
                                        (String.append
                                            (Name.toHumanWords name
                                                |> String.join ""
                                            )
                                            " : "
                                        )
                                    )
                                , viewTestCase (config index) references rawValue
                                ]
                        )
                    |> column [ spacing 5, padding 5 ]
                ]

          else
            column [ spacing 5 ]
                [ addOrEditOrSaveButton handlers.saveTestCase index "Save Inputs"
                , viewArgumentEditors handlers model index argValues
                ]
        ]


viewExpectedOutput : Config msg -> IR -> RawValue -> Element msg
viewExpectedOutput config references rawValue =
    column [ spacing 5, padding 5 ]
        [ viewHeader "EXPECTED OUTPUT"
        , el [ spacing 5, padding 5 ] (viewTestCase config references rawValue)
        ]


viewActualOutput : Config msg -> IR -> TestCase -> FQName -> Element msg
viewActualOutput config references testCase fQName =
    column [ spacing 5, padding 5 ]
        [ viewHeader "ACTUAL OUTPUT"
        , el [ spacing 5, padding 5 ] (evaluateOutput config references testCase fQName)
        ]


viewTestCase : Config msg -> IR -> RawValue -> Element msg
viewTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ centerX, centerY ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))


evaluateOutput : Config msg -> IR -> TestCase -> FQName -> Element msg
evaluateOutput config ir testCase fQName =
    case evaluateFunctionValue SDK.nativeFunctions ir fQName testCase.inputs of
        Ok rawValue ->
            if rawValue == testCase.expectedOutput then
                el [ Font.heavy, Font.color green ] (viewTestCase config ir rawValue)

            else
                el [ Font.heavy, Font.color red ] (viewTestCase config ir rawValue)

        Err error ->
            text (Debug.toString error)


viewArgumentEditors : Handlers msg -> Model -> Int -> List ( Name, Type () ) -> Element msg
viewArgumentEditors handlers model index inputTypes =
    inputTypes
        |> List.map
            (\( argName, argType ) ->
                column
                    [ Background.color (rgb 1 1 1)
                    , Border.rounded 5
                    , spacing 5
                    ]
                    [ el [ padding 5, Font.bold ]
                        (text (argName |> Name.toHumanWords |> String.join " "))
                    , el [ padding 5 ]
                        (Edit.editValue
                            argType
                            (model.testCaseStates
                                |> Dict.get index
                                |> Maybe.andThen (\record -> Dict.get argName record.argState)
                            )
                            (handlers.argValueUpdated index argName)
                            (handlers.invalidArgValue index argName)
                        )
                    ]
            )
        |> column [ spacing 5 ]


addOrEditOrSaveButton : (Int -> msg) -> Int -> String -> Element msg
addOrEditOrSaveButton handlers index label =
    Element.el
        [ Font.bold
        , Border.solid
        , Border.rounded 3
        , spacing 7
        , padding 7
        , Background.color black
        , Font.color white
        , onClick (handlers index)
        ]
        (Element.text label)


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

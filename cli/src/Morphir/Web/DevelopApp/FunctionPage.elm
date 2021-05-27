module Morphir.Web.DevelopApp.FunctionPage exposing (..)

import Array exposing (Array)
import Dict exposing (Dict)
import Element exposing (Element, centerX, centerY, column, el, fill, height, none, padding, paddingXY, rgb, scrollbars, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (center)
import Element.Input as Input exposing (placeholder)
import Element.Keyed as Keyed
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.SDK as SDK
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Type.Infer as Infer
import Morphir.Value.Interpreter exposing (evaluateFunctionValue)
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)
import Url.Parser as UrlParser exposing ((</>))


type alias Model =
    { functionName : FQName
    , testCaseStates : Array TestCaseState
    , savedTestCases : TestCases
    }


type alias TestCaseState =
    { expandedValues : Dict FQName (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    , inputStates : Dict Name ValueEditor.EditorState
    , expectedOutputState : ValueEditor.EditorState
    , descriptionState : String
    , editMode : Bool
    }


type alias Handlers msg =
    { expandReference : Int -> FQName -> Bool -> msg
    , expandVariable : Int -> Int -> Maybe RawValue -> msg
    , shrinkVariable : Int -> Int -> msg
    , inputsUpdated : Int -> Name -> ValueEditor.EditorState -> msg
    , expectedOutputUpdated : Int -> ValueEditor.EditorState -> msg
    , descriptionUpdated : Int -> String -> msg
    , addTestCase : msg
    , cloneTestCase : Int -> msg
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


viewHeader : Theme -> String -> Element msg
viewHeader theme heading =
    el [ Font.bold, Font.size (theme |> Theme.scaled 2), spacing 5, padding 5 ] (text (heading ++ " : "))


viewTitle : FQName -> String
viewTitle functionName =
    "Morphir - " ++ (functionName |> FQName.toString |> String.replace ":" " / ")


viewPage : Theme -> Handlers msg -> Distribution -> Model -> Element msg
viewPage theme handlers distribution model =
    let
        testCasesNumber =
            Array.length model.testCaseStates
    in
    Element.column [ width fill, padding 10, spacing 10 ]
        [ el [ Font.bold ] (text (viewTitle model.functionName))
        , if List.length model.savedTestCases > 0 || Array.length model.testCaseStates > 0 then
            Theme.button theme (handlers.saveTestSuite model) "Save Changes" theme.colors.secondaryHighlight

          else
            el [] none
        , el [ Font.bold ] (text ("Total scenarios: " ++ String.fromInt testCasesNumber))
        , if testCasesNumber > 0 then
            column [ width fill, spacing 5 ]
                [ el [ Font.bold, Font.size (theme |> Theme.scaled 4) ] (text "Scenarios")
                , viewScenarios theme handlers distribution model
                ]

          else
            el [ Font.bold ] (text "No test cases found")
        , Theme.button theme handlers.addTestCase "Add new scenario" theme.colors.primaryHighlight
        ]


viewScenarios : Theme -> Handlers msg -> Distribution -> Model -> Element msg
viewScenarios theme handlers distribution model =
    let
        ( packagePath, modulePath, localName ) =
            model.functionName

        ( inputArgValues, outputValue ) =
            Distribution.lookupValueSpecification packagePath modulePath localName distribution
                |> Maybe.map
                    (\valueSpec ->
                        ( valueSpec.inputs, valueSpec.output )
                    )
                |> Maybe.withDefault ( [], Type.Unit () )

        config : Int -> Config msg
        config index =
            { irContext =
                { distribution = distribution
                , nativeFunctions = SDK.nativeFunctions
                }
            , state =
                { expandedFunctions =
                    Array.get index model.testCaseStates
                        |> Maybe.map .expandedValues
                        |> Maybe.withDefault Dict.empty
                , variables =
                    Array.get index model.testCaseStates
                        |> Maybe.map .inputStates
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
                    Array.get index model.testCaseStates
                        |> Maybe.map .popupVariables
                        |> Maybe.withDefault (PopupScreenRecord 0 Nothing)
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
    Array.toList model.testCaseStates
        |> List.indexedMap
            (\index testCaseState ->
                let
                    testCase =
                        { inputs =
                            List.map
                                (\( name, _ ) ->
                                    Dict.get name testCaseState.inputStates
                                        |> Maybe.andThen .lastValidValue
                                        |> Maybe.withDefault (Value.Unit ())
                                )
                                inputArgValues
                        , expectedOutput =
                            testCaseState.expectedOutputState.lastValidValue
                                |> Maybe.withDefault (Value.Unit ())
                        , description = testCaseState.descriptionState
                        }
                in
                column [ width fill, spacing 5, padding 5 ]
                    [ Theme.header theme
                        { left =
                            [ el [ Font.bold, Font.size (theme |> Theme.scaled 3), Font.color theme.colors.primaryHighlight ] (text ("Scenario " ++ String.fromInt index))
                            ]
                        , middle =
                            []
                        , right =
                            [ if testCaseState.editMode then
                                Theme.button theme (handlers.saveTestCase index) "Save" theme.colors.secondaryHighlight

                              else
                                Theme.button theme (handlers.editTestCase index) "Edit" theme.colors.secondaryHighlight
                            , Theme.button theme (handlers.cloneTestCase index) "Clone" theme.colors.primaryHighlight
                            , Theme.button theme (handlers.deleteTestCase index) "Delete" theme.colors.primaryHighlight
                            ]
                        }
                    , if testCaseState.editMode == False then
                        column []
                            [ viewDescription theme testCase.description
                            , viewInputs theme (config index) references inputArgValues testCase.inputs
                            , viewExpectedOutput theme (config index) references testCase.expectedOutput
                            ]

                      else
                        column []
                            [ viewArgumentEditors theme references handlers model index inputArgValues outputValue testCase.description
                            ]
                    , viewActualOutput theme (config index) references testCase model.functionName
                    , Element.column [ width fill, spacing 5, padding 5 ]
                        [ viewHeader theme "FUNCTION"
                        , el [ centerY, centerX, spacing 5, padding 5, scrollbars ] (newFunctionView (config index) distribution model)
                        ]
                    ]
            )
        |> column [ spacing 5, padding 5, width fill ]


newFunctionView : Config msg -> Distribution -> Model -> Element msg
newFunctionView config distribution model =
    let
        ( _, modulePath, localName ) =
            model.functionName
    in
    Distribution.lookupValueDefinition (QName modulePath localName) distribution
        |> Maybe.map
            (\valueDef ->
                ViewValue.viewDefinition
                    config
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


viewDescription : Theme -> String -> Element msg
viewDescription theme description =
    column [ paddingXY 0 5 ]
        [ viewHeader theme "DESCRIPTION"
        , el [ spacing 5, padding 5 ] (text description)
        ]


viewInputs : Theme -> Config msg -> IR -> List ( Name, Type () ) -> List RawValue -> Element msg
viewInputs theme config ir argValues inputs =
    column [ spacing 5 ]
        [ viewHeader theme "INPUTS"
        , inputs
            |> List.map2
                (\( name, tpe ) rawValue ->
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
                        , viewTestCase config ir rawValue
                        ]
                )
                argValues
            |> column [ spacing 5, padding 5 ]
        ]


viewExpectedOutput : Theme -> Config msg -> IR -> RawValue -> Element msg
viewExpectedOutput theme config references expectedOutput =
    column [ spacing 5 ]
        [ viewHeader theme "EXPECTED OUTPUT"
        , viewTestCase config references expectedOutput
        ]


viewActualOutput : Theme -> Config msg -> IR -> TestCase -> FQName -> Element msg
viewActualOutput theme config references testCase fQName =
    column [ spacing 5, paddingXY 0 5 ]
        [ viewHeader theme "ACTUAL OUTPUT"
        , evaluateOutput theme config references testCase fQName
        ]


viewTestCase : Config msg -> IR -> RawValue -> Element msg
viewTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ spacing 5, padding 5 ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))


evaluateOutput : Theme -> Config msg -> IR -> TestCase -> FQName -> Element msg
evaluateOutput theme config ir testCase fQName =
    case evaluateFunctionValue SDK.nativeFunctions ir fQName testCase.inputs of
        Ok rawValue ->
            if rawValue == testCase.expectedOutput then
                el [ Font.heavy, Font.color theme.colors.positive ] (viewTestCase config ir rawValue)

            else
                el [ Font.heavy, Font.color theme.colors.negative ] (viewTestCase config ir rawValue)

        Err error ->
            text (Debug.toString error)


viewArgumentEditors : Theme -> IR -> Handlers msg -> Model -> Int -> List ( Name, Type () ) -> Type () -> String -> Element msg
viewArgumentEditors theme ir handlers model index inputTypes outputType description =
    column [ spacing 5 ]
        [ viewHeader theme "DESCRIPTION"
        , Input.text
            [ width fill
            , height fill
            , paddingXY 10 3
            ]
            { onChange =
                \updatedText -> handlers.descriptionUpdated index updatedText
            , text = description
            , placeholder =
                Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
            , label = Input.labelHidden ""
            }
        , viewHeader theme "INPUTS"
        , inputTypes
            |> List.map
                (\( argName, argType ) ->
                    Keyed.column
                        [ Background.color (rgb 1 1 1)
                        , Border.rounded 5
                        , spacing 5
                        ]
                        [ ( String.join "_" [ "editor", "label", String.fromInt index, Name.toCamelCase argName ]
                          , el [ padding 5, Font.bold ]
                                (text (argName |> Name.toHumanWords |> String.join " "))
                          )
                        , ( String.join "_" [ "editor", String.fromInt index, Name.toCamelCase argName ]
                          , el [ padding 5 ]
                                (ValueEditor.view ir
                                    argType
                                    (handlers.inputsUpdated index argName)
                                    (model.testCaseStates
                                        |> Array.get index
                                        |> Maybe.andThen (\record -> Dict.get argName record.inputStates)
                                        |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing)
                                    )
                                )
                          )
                        ]
                )
            |> column [ spacing 5 ]
        , viewHeader theme "EXPECTED OUTPUT"
        , el [ padding 5 ]
            (ValueEditor.view ir
                outputType
                (handlers.expectedOutputUpdated index)
                (model.testCaseStates
                    |> Array.get index
                    |> Maybe.map (\record -> record.expectedOutputState)
                    |> Maybe.withDefault (ValueEditor.initEditorState ir outputType Nothing)
                )
            )
        ]


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
    Element.row [ centerX, width fill ]
        [ horizontalLine
        , Element.el [ padding 5, Font.bold ] (text separatorText)
        , horizontalLine
        ]


compareState : TestCases -> TestCases -> Bool
compareState testCaseList1 testCaseList2 =
    if List.length testCaseList1 == List.length testCaseList2 then
        testCaseList2
            |> List.map2
                (\testCase1 testCase2 ->
                    compareTestCase testCase1 testCase2
                )
                testCaseList1
            |> List.foldl (\val1 val2 -> val1 && val2) True

    else
        False


compareTestCase : TestCase -> TestCase -> Bool
compareTestCase testCase1 testCase2 =
    testCase2.inputs
        |> List.map2
            (\input1 input2 ->
                if input1 == input2 then
                    True

                else
                    False
            )
            testCase1.inputs
        |> List.foldl (\val1 val2 -> val1 && val2) True

module Morphir.Web.DevelopApp.FunctionPage exposing (..)

import Array exposing (Array)
import Dict exposing (Dict)
import Element exposing (Element, alignTop, centerX, centerY, column, el, explain, fill, height, none, padding, paddingXY, paragraph, px, rgb, row, scrollbarX, scrollbars, shrink, spacing, text, width)
import Element.Background as Background
import Element.Font as Font exposing (center)
import Element.Input as Input exposing (placeholder)
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
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
import Morphir.Visual.Theme as Theme exposing (Theme)
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)
import Morphir.Web.DevelopApp.Common exposing (viewAsCard)
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
    el [ Font.bold, Font.size (theme |> Theme.scaled 2), spacing 5, padding 5 ] (text heading)


viewTitle : FQName -> String
viewTitle ( _, moduleName, functionName ) =
    String.join " / "
        (List.concat
            [ moduleName |> List.map nameToText
            , [ nameToText functionName ]
            ]
        )


viewPage : Theme -> Handlers msg -> Distribution -> Model -> Element msg
viewPage theme handlers distribution model =
    let
        testCasesNumber =
            Array.length model.testCaseStates
    in
    Element.column [ width fill, padding 10, spacing 10 ]
        [ el [ Font.bold ] (text (viewTitle model.functionName))
        , if testCasesNumber > 0 then
            column [ width fill, spacing 5 ]
                [ Theme.header theme
                    { left =
                        [ el [ Font.bold, Font.size (theme |> Theme.scaled 4) ] (text "Scenarios")
                        , el [ Font.bold ] (text ("Total: " ++ String.fromInt testCasesNumber))
                        ]
                    , middle =
                        []
                    , right =
                        [ if List.length model.savedTestCases > 0 || Array.length model.testCaseStates > 0 then
                            Theme.button theme (handlers.saveTestSuite model) "Save Changes" theme.colors.secondaryHighlight

                          else
                            el [] none
                        ]
                    }
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

        ( inputTypes, outputType ) =
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

        ir : IR
        ir =
            IR.fromDistribution distribution
    in
    Array.toList model.testCaseStates
        |> List.indexedMap
            (\testCaseIndex testCaseState ->
                let
                    testCase =
                        { inputs =
                            List.map
                                (\( name, _ ) ->
                                    Dict.get name testCaseState.inputStates
                                        |> Maybe.andThen .lastValidValue
                                        |> Maybe.withDefault (Value.Unit ())
                                )
                                inputTypes
                        , expectedOutput =
                            testCaseState.expectedOutputState.lastValidValue
                                |> Maybe.withDefault (Value.Unit ())
                        , description = testCaseState.descriptionState
                        }
                in
                column
                    [ width fill
                    , padding (theme |> Theme.scaled 2)
                    , Background.color (rgb 0.9 0.95 1)
                    ]
                    [ Theme.header theme
                        { left =
                            [ el [ Font.bold, Font.size (theme |> Theme.scaled 3), Font.color theme.colors.primaryHighlight ] (text ("Scenario " ++ String.fromInt (testCaseIndex + 1)))
                            ]
                        , middle =
                            []
                        , right =
                            [ if testCaseState.editMode then
                                Theme.button theme (handlers.saveTestCase testCaseIndex) "Save" theme.colors.secondaryHighlight

                              else
                                Theme.button theme (handlers.editTestCase testCaseIndex) "Edit" theme.colors.secondaryHighlight
                            , Theme.button theme (handlers.cloneTestCase testCaseIndex) "Clone" theme.colors.primaryHighlight
                            , Theme.button theme (handlers.deleteTestCase testCaseIndex) "Delete" theme.colors.primaryHighlight
                            ]
                        }
                    , column [ width fill, spacing 5, padding 5 ]
                        [ viewDescription theme testCase.description testCaseState.editMode (handlers.descriptionUpdated testCaseIndex)
                        , row [ spacing (theme |> Theme.scaled 4) ]
                            [ el [ alignTop ]
                                (viewInputs theme (config testCaseIndex) ir inputTypes testCase.inputs testCaseState.editMode (handlers.inputsUpdated testCaseIndex) testCaseState)
                            , el [ alignTop ]
                                (viewExpectedOutput theme (config testCaseIndex) ir testCase.expectedOutput testCaseState.editMode (handlers.expectedOutputUpdated testCaseIndex) outputType testCaseState)
                            , el [ alignTop ]
                                (viewActualOutput theme (config testCaseIndex) ir testCase model.functionName)
                            ]
                        , column [ width fill, height fill, spacing 5, padding 5 ]
                            [ viewHeader theme "Explanation"
                            , el [ width fill, height (px 300), scrollbars, padding (theme |> Theme.scaled 2), Background.color theme.colors.lightest ]
                                (viewExplanation (config testCaseIndex) distribution model)
                            ]
                        ]
                    ]
            )
        |> column [ spacing 30, padding 5, width fill ]


viewExplanation : Config msg -> Distribution -> Model -> Element msg
viewExplanation config distribution model =
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


viewDescription : Theme -> String -> Bool -> (String -> msg) -> Element msg
viewDescription theme description editMode onUpdate =
    let
        commonStyle =
            [ width fill
            , height fill
            , paddingXY (theme |> Theme.scaled 1) (theme |> Theme.scaled 1)
            ]
    in
    column [ width fill, paddingXY 0 5 ]
        [ if editMode then
            Input.multiline commonStyle
                { onChange =
                    \updatedText -> onUpdate updatedText
                , text = description
                , placeholder =
                    Just (placeholder [ center, paddingXY 0 1 ] (text "not set"))
                , label = Input.labelHidden ""
                , spellcheck = False
                }

          else
            el commonStyle
                (text description)
        ]


viewInputs : Theme -> Config msg -> IR -> List ( Name, Type () ) -> List RawValue -> Bool -> (Name -> ValueEditor.EditorState -> msg) -> TestCaseState -> Element msg
viewInputs theme config ir argValues inputs editMode onUpdate testCaseState =
    viewAsCard theme
        (viewHeader theme "INPUTS")
        (if editMode then
            argValues
                |> List.map
                    (\( argName, argType ) ->
                        ( argName
                        , el []
                            (ValueEditor.view ir
                                argType
                                (onUpdate argName)
                                (testCaseState.inputStates
                                    |> Dict.get argName
                                    |> Maybe.withDefault (ValueEditor.initEditorState ir argType Nothing)
                                )
                            )
                        )
                    )
                |> FieldList.view

         else
            FieldList.view
                (List.map2
                    (\( name, _ ) rawValue ->
                        ( name, viewRawValue config ir rawValue )
                    )
                    argValues
                    inputs
                )
        )


viewExpectedOutput : Theme -> Config msg -> IR -> RawValue -> Bool -> (ValueEditor.EditorState -> msg) -> Type () -> TestCaseState -> Element msg
viewExpectedOutput theme config ir expectedOutput editMode onUpdate outputType testCaseState =
    viewAsCard theme
        (viewHeader theme "EXPECTED OUTPUT")
        (if editMode then
            el [ padding 5 ]
                (ValueEditor.view ir
                    outputType
                    onUpdate
                    testCaseState.expectedOutputState
                )

         else
            viewRawValue config ir expectedOutput
        )


viewActualOutput : Theme -> Config msg -> IR -> TestCase -> FQName -> Element msg
viewActualOutput theme config references testCase fQName =
    viewAsCard theme
        (viewHeader theme "ACTUAL OUTPUT")
        (evaluateOutput theme config references testCase fQName)


viewRawValue : Config msg -> IR -> RawValue -> Element msg
viewRawValue config ir rawValue =
    case rawToVisualTypedValue ir rawValue of
        Ok typedValue ->
            el [ spacing 5, padding 5 ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))


evaluateOutput : Theme -> Config msg -> IR -> TestCase -> FQName -> Element msg
evaluateOutput theme config ir testCase fQName =
    case evaluateFunctionValue SDK.nativeFunctions ir fQName testCase.inputs of
        Ok rawValue ->
            if rawValue == testCase.expectedOutput then
                el [ Font.heavy, Font.color theme.colors.positive ] (viewRawValue config ir rawValue)

            else
                el [ Font.heavy, Font.color theme.colors.negative ] (viewRawValue config ir rawValue)

        Err error ->
            text (Debug.toString error)


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

module Morphir.Web.DevelopApp.FunctionPage exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, centerX, centerY, column, el, fill, height, padding, spacing, text, width)
import Element.Font as Font
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
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)
import Morphir.Web.DevelopApp.Common exposing (scaled)
import Url.Parser as UrlParser exposing ((</>))


type alias Model =
    { functionName : FQName
    , testCaseStates : Dict Int TestCaseState
    }


type alias TestCaseState =
    { expandedValues : Dict FQName (Value.Definition () (Type ()))
    , popupVariables : PopupScreenRecord
    }


type alias Handlers msg =
    { expandReference : Int -> FQName -> Bool -> msg
    , expandVariable : Int -> Int -> Maybe RawValue -> msg
    , shrinkVariable : Int -> Int -> msg
    }


routeParser : UrlParser.Parser (Model -> a) a
routeParser =
    UrlParser.map
        (\fQName ->
            { functionName = fQName
            , testCaseStates = Dict.empty
            }
        )
        (UrlParser.s "function"
            </> (UrlParser.string
                    |> UrlParser.map
                        (\string ->
                            FQName.fromString string ":"
                        )
                )
        )


viewTitle : Model -> String
viewTitle model =
    "Morphir - " ++ (model.functionName |> FQName.toString |> String.replace ":" " / ")


viewPage : Handlers msg -> TestCases -> Distribution -> Model -> Element msg
viewPage handlers testCases distribution model =
    Element.column [ padding 10, spacing 10 ]
        [ el [ Font.bold ] (text (viewTitle model))
        , el [ Font.bold, Font.size (scaled 4) ] (text "TestCases :")
        , viewSectionWise handlers distribution testCases model
        ]


viewSectionWise : Handlers msg -> Distribution -> TestCases -> Model -> Element msg
viewSectionWise handlers distribution testCases model =
    let
        inputTypesName : List Name
        inputTypesName =
            Distribution.lookupValueSpecification (FQName.getPackagePath model.functionName) (FQName.getModulePath model.functionName) (FQName.getLocalName model.functionName) distribution
                |> Maybe.map
                    (\valueSpec ->
                        valueSpec.inputs
                            |> List.map (\( name, tpe ) -> name)
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
                , variables = Dict.empty
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
    testCases
        |> List.indexedMap
            (\index testcase ->
                column [ spacing 5, padding 5 ]
                    [ el [ Font.bold, Font.size (scaled 3) ] (text ("TestCase " ++ String.fromInt index ++ " :"))
                    , el [ Font.bold, Font.size (scaled 2), spacing 5, padding 5 ] (text "Input :")
                    , List.map2 Tuple.pair inputTypesName testcase.inputs
                        |> List.map
                            (\( name, rawValue ) ->
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
                    , column [ spacing 5, padding 5 ]
                        [ el [ Font.bold, Font.size (scaled 2) ] (text "Expected Output :")
                        , el [ spacing 5, padding 5 ] (viewTestCase (config index) references testcase.expectedOutput)
                        ]
                    , column [ spacing 5, padding 5 ]
                        [ el [ Font.bold, Font.size (scaled 2) ] (text "Actual Output :")
                        , el [ spacing 5, padding 5 ] (evaluateOutput (config index) references testcase distribution model.functionName)
                        ]
                    , column [ spacing 5, padding 5 ]
                        [ el [ Font.bold, Font.size (scaled 2) ] (text "Description :")
                        , el [ spacing 5, padding 5 ] (text testcase.description)
                        ]
                    , Element.column [ spacing 10, padding 10 ]
                        [ el [ Font.bold, Font.size (scaled 4) ] (text "Function :")
                        , el [ centerY, centerX ] (newFunctionView (config index) distribution testcase model)
                        ]
                    ]
            )
        |> column [ spacing 5, padding 5 ]


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
                                    List.map2
                                        (\( name, _, tpe ) rawValue ->
                                            ( name, rawValue )
                                        )
                                        valueDef.inputTypes
                                        testcase.inputs
                                        |> Dict.fromList
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


viewTestCase : Config msg -> IR -> RawValue -> Element msg
viewTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ centerX, centerY ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))


evaluateOutput : Config msg -> IR -> TestCase -> Distribution -> FQName -> Element msg
evaluateOutput config ir testCase distribution fQName =
    case evaluateFunctionValue SDK.nativeFunctions ir fQName testCase.inputs of
        Ok rawValue ->
            if rawValue == testCase.expectedOutput then
                el [ Font.heavy, Font.color (Element.rgb255 100 180 100) ] (viewTestCase config ir rawValue)

            else
                el [ Font.heavy, Font.color (Element.rgb255 180 100 100) ] (viewTestCase config ir rawValue)

        Err error ->
            text (Debug.toString error)

module Morphir.Visual.ViewFunction exposing (Model)

import Element exposing (Element, centerX, centerY, el, fill, height, padding, row, spacing, text, width)
import Element.Border as Border
import Element.Font as Font
import Morphir.Correctness.Test exposing (TestCase, TestCases, TestSuite)
import Morphir.IR exposing (IR)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Value exposing (RawValue, TypedValue, Value)
import Morphir.Type.Infer as Infer
import Morphir.Visual.Config exposing (Config, PopupScreenRecord, VisualState)
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.VisualTypedValue exposing (rawToVisualTypedValue)


type alias Model =
    { fQName : FQName
    , testSuite : TestSuite
    }


viewTable : Config msg -> IR -> TestCases -> Element msg
viewTable config references testCases =
    Element.table [ centerY, centerX, width fill, height fill ]
        { data = testCases
        , columns =
            [ { header =
                    Element.column [ width fill, height fill ]
                        [ el
                            [ Border.widthEach { bottom = 2, top = 0, right = 0, left = 0 }
                            , Font.bold
                            , width fill
                            , height fill
                            ]
                            (el
                                [ centerY
                                , centerX
                                , padding 5
                                ]
                                (text "Inputs")
                            )
                        ]
                        |> el
                            [ Border.width 2
                            , Font.bold
                            ]
              , width = fill
              , view =
                    \testcase ->
                        el [ padding 5, Border.widthEach { bottom = 2, top = 0, right = 2, left = 2 }, width fill, height fill ]
                            (List.map
                                (\singleInput ->
                                    viewTestCase config
                                        references
                                        singleInput
                                )
                                testcase.inputs
                                |> row [ spacing 5, padding 5, centerX, centerY ]
                            )
              }
            , { header =
                    el
                        [ Border.widthEach { bottom = 2, top = 2, right = 2, left = 0 }
                        , padding 5
                        , Font.bold
                        , width fill
                        , height fill
                        ]
                        (el [ centerY, centerX ] (text "Outputs"))
              , width = fill
              , view =
                    \testcase ->
                        el [ Border.widthEach { bottom = 2, top = 0, right = 2, left = 0 }, width fill, height fill ]
                            (viewTestCase config references testcase.expectedOutput)
              }
            , { header =
                    el
                        [ Border.widthEach { bottom = 2, top = 2, right = 2, left = 0 }
                        , padding 5
                        , Font.bold
                        , width fill
                        , height fill
                        ]
                        (el [ centerY, centerX ] (text "Description"))
              , width = fill
              , view =
                    \testcase ->
                        el [ Border.widthEach { bottom = 2, top = 0, right = 2, left = 0 }, width fill, height fill ]
                            (el [ centerY, centerX ] (text testcase.description))
              }
            ]
        }


viewTestCase : Config msg -> IR -> RawValue -> Element msg
viewTestCase config references rawValue =
    case rawToVisualTypedValue references rawValue of
        Ok typedValue ->
            el [ centerX, centerY ] (ViewValue.viewValue config typedValue)

        Err error ->
            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

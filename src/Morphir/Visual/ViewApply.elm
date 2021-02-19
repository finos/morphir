module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, centerX, column, fill, moveRight, padding, row, spacing, text, width)
import Element.Border as Border
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumPadding, smallSpacing)


view : Config msg -> (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> List (Value ta (Type ta)) -> Element msg
view config viewValue functionValue argValues =
    case ( functionValue, argValues ) of
        ( Value.Reference _ ( _, _, ("is" :: _) as localName ), [ argValue ] ) ->
            row
                [ width fill
                , smallSpacing config.state.theme |> spacing
                ]
                [ viewValue argValue
                , text (nameToText localName)
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "negate" ] ), [ argValue ] ) ->
            row [ smallSpacing config.state.theme |> spacing ]
                [ text "- ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "abs" ] ), [ argValue ] ) ->
            row [ smallSpacing config.state.theme |> spacing ]
                [ text "abs ("
                , viewValue argValue
                , text ")"
                ]

        -- possibly binary operator
        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ), [ argValue1, argValue2 ] ) ->
            let
                functionName : String
                functionName =
                    String.join "."
                        [ moduleName |> Path.toString Name.toTitleCase "."
                        , localName |> Name.toCamelCase
                        ]
            in
                case Maybe.withDefault "" (Dict.get functionName inlineBinaryOperators) of
                    "/" -> column
                               [ width fill
                               , smallSpacing config.state.theme |> spacing
                               ]
                               [
                                   row [centerX
                                        , width Element.fill
                                        , Border.solid
                                        , Border.widthEach { bottom = 1, left = 0, right = 0, top = 0 }
                                        , padding 5] [

                                      viewValue argValue1
                                   ],
                                   row [centerX
                                        , width Element.fill, padding 5]
                                   [
                                      viewValue argValue2
                                   ]
                               ]
                    _ -> Maybe.map
                            (\functionText ->
                                row
                                    [ width fill
                                    , smallSpacing config.state.theme |> spacing
                                    ]
                                    [ viewValue argValue1
                                    , text functionText
                                    , viewValue argValue2
                                    ]
                            ) (Dict.get functionName inlineBinaryOperators)
                        |> Maybe.withDefault
                            (column
                                [ smallSpacing config.state.theme |> spacing ]
                                [ viewValue functionValue
                                , column
                                    [ mediumPadding config.state.theme |> padding
                                    , smallSpacing config.state.theme |> spacing
                                    ]
                                    (argValues
                                        |> List.map viewValue
                                    )
                                ]
                            )

        _ ->
            column
                [ smallSpacing config.state.theme |> spacing ]
                [ viewValue functionValue
                , column
                    [ moveRight 10
                    , smallSpacing config.state.theme |> spacing
                    ]
                    (argValues
                        |> List.map viewValue
                    )
                ]


inlineBinaryOperators : Dict String String
inlineBinaryOperators =
    Dict.fromList
        [ ( "Basics.equal", "=" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.lessThanOrEqual", "<=" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.greaterThanOrEqual", ">=" )
        , ( "Basics.add", "+" )
        , ( "Basics.subtract", "-" )
        , ( "Basics.multiply", "*" )
        , ( "Basics.divide", "/" )
        , ( "List.append", "+" )
        ]

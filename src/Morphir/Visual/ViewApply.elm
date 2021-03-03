module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, centerX, column, fill, moveRight, moveUp, padding, row, spacing, text, width)
import Element.Border as Border
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (VisualTypedValue, nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumPadding, smallPadding, smallSpacing)


view : Config msg -> (VisualTypedValue -> Element msg) -> VisualTypedValue -> List VisualTypedValue -> Element msg
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
        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ), [ argValues1, argValues2 ] ) ->
            let
                functionName : String
                functionName =
                    String.join "."
                        [ moduleName |> Path.toString Name.toTitleCase "."
                        , localName |> Name.toCamelCase
                        ]
            in
            if Maybe.withDefault "" (Dict.get functionName inlineBinaryOperators) == "/" then
                row [ centerX, width fill, spacing 5 ]
                    [ column [ centerX, width fill ]
                        [ row [ centerX, width fill ]
                            [ row
                                [ smallSpacing config.state.theme |> spacing
                                , smallPadding config.state.theme |> padding
                                , Border.widthEach { bottom = 1, left = 0, right = 0, top = 0 }
                                , centerX
                                ]
                                [ viewValue argValues1
                                ]
                            ]
                        , row
                            [ centerX
                            , Border.solid
                            , Border.widthEach { bottom = 0, left = 0, right = 0, top = 1 }
                            , moveUp 1
                            , smallPadding config.state.theme |> padding
                            ]
                            [ viewValue argValues2
                            ]
                        ]
                    ]

            else if Dict.member functionName inlineBinaryOperators then
                row
                    [ smallSpacing config.state.theme |> spacing ]
                    [ viewValue argValues1
                    , text (Maybe.withDefault "" (Dict.get functionName inlineBinaryOperators))
                    , viewValue argValues2
                    ]

            else
                Element.none

        _ ->
            row []
                (argValues
                    |> List.map viewValue
                )


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

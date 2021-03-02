module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, column, fill, moveRight, padding, row, spacing, text, width)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (VisualTypedValue, nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumPadding, smallSpacing)


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
        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ), [ argValue1, argValue2 ] ) ->
            let
                functionName : String
                functionName =
                    String.join "."
                        [ moduleName |> Path.toString Name.toTitleCase "."
                        , localName |> Name.toCamelCase
                        ]
            in
            inlineBinaryOperators
                |> Dict.get functionName
                |> Maybe.map
                    (\functionText ->
                        row
                            [ width fill
                            , smallSpacing config.state.theme |> spacing
                            ]
                            [ viewValue argValue1
                            , text functionText
                            , viewValue argValue2
                            ]
                    )
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

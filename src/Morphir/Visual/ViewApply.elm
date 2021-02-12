module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, column, fill, moveRight, paddingEach, row, spacing, text, width)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)


view : Config msg -> (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> List (Value ta (Type ta)) -> Element msg
view config viewValue functionValue argValues =
    case ( functionValue, argValues ) of
        ( Value.Reference _ ( _, _, ("is" :: _) as localName ), [ argValue ] ) ->
            row
                [ width fill
                , spacing config.state.theme.smallSpacing
                ]
                [ viewValue argValue
                , text (nameToText localName)
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "negate" ] ), [ argValue ] ) ->
            row [ spacing config.state.theme.smallSpacing ]
                [ text "- ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "abs" ] ), [ argValue ] ) ->
            row [ spacing config.state.theme.smallSpacing ]
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
                            , spacing config.state.theme.smallSpacing
                            ]
                            [ viewValue argValue1
                            , text functionText
                            , viewValue argValue2
                            ]
                    )
                |> Maybe.withDefault
                    (column
                        [ spacing config.state.theme.smallSpacing ]
                        [ viewValue functionValue
                        , column
                            [ paddingEach { left = 10, right = 0, top = 0, bottom = 0 }
                            , spacing config.state.theme.smallSpacing
                            ]
                            (argValues
                                |> List.map viewValue
                            )
                        ]
                    )

        _ ->
            column
                [ spacing config.state.theme.smallSpacing ]
                [ viewValue functionValue
                , column
                    [ moveRight 10
                    , spacing config.state.theme.smallSpacing
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

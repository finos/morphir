module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, centerX, column, el, fill, moveUp, padding, row, spacing, text, width)
import Element.Font as Font
import Morphir.IR.Name as Name
import Morphir.IR as IR
import Morphir.IR.Path as Path
import Morphir.IR.Value as Value
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)
import Morphir.IR.Type as Type
import Morphir.Visual.Components.FieldList as FieldList


view : Config msg -> (EnrichedValue -> Element msg) -> EnrichedValue -> List EnrichedValue -> Element msg
view config viewValue functionValue argValues =
    case ( functionValue, argValues ) of
        ( Value.Constructor _ ((_, _, localName) as fQName), _ ) ->
            case config.ir |> IR.lookupTypeSpecification (config.ir |> IR.resolveAliases fQName) of
                Just (Type.TypeAliasSpecification _ (Type.Record _ fields)) ->
                    FieldList.view (List.map2 (\field arg -> ( field.name, Element.el [Element.centerX, Element.centerY] (viewValue arg) )) fields argValues)
                _ ->
                    Element.row [ smallSpacing config.state.theme |> spacing] (List.concat [[text <| nameToText localName], argValues |> List.map viewValue] )

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

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], localName ), [ argValue ] ) ->
            row [ smallSpacing config.state.theme |> spacing, smallPadding config.state.theme |> padding ]
                [ text ((localName |> Name.toCamelCase) ++ " (")
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
            if moduleName == [ [ "basics" ] ] && (localName == [ "min" ] || localName == [ "max" ]) then
                row
                    [ smallSpacing config.state.theme |> spacing ]
                    [ viewValue functionValue
                    , text " ("
                    , viewValue argValues1
                    , text ","
                    , viewValue argValues2
                    , text ")"
                    ]

            else if moduleName == [ [ "basics" ] ] && (localName == [ "power" ]) then
                row
                    [ smallSpacing config.state.theme |> spacing ]
                    [ viewValue argValues1
                    , el [ Font.bold, Font.size (ceiling (toFloat config.state.theme.fontSize / 1.3)), moveUp (toFloat (config.state.theme.fontSize // 4)) ] (viewValue argValues2)
                    ]

            else
                row
                    [ smallSpacing config.state.theme |> spacing, smallPadding config.state.theme |> padding ]
                    [ viewValue argValues1
                    , case Dict.get functionName inlineBinaryOperators of
                        Just string ->
                            text string

                        Nothing ->
                            viewValue functionValue
                    , viewValue argValues2
                    ]

        _ ->
            column [ smallSpacing config.state.theme |> spacing ]
                [ column [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
                    [ viewValue functionValue
                    ]
                , column [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
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
        , ( "Basics.notEqual", "≠" )
        , ( "Basics.power", "^" )
        ]

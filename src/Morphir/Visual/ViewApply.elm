module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, centerX, el, fill, link, moveUp, padding, pointer, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html exposing (u)
import Morphir.IR as IR
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (Value(..))
import Morphir.Visual.Common exposing (nameToText, pathToFullUrl)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)


view : Config msg -> (EnrichedValue -> Element msg) -> EnrichedValue -> List EnrichedValue -> Element msg
view config viewValue functionValue argValues =
    let
        styles =
            [ smallSpacing config.state.theme |> spacing, Element.centerY ]

        viewFunctionValue =
            let
                notClickable =
                    el [ Background.color <| config.state.theme.colors.selectionColor, padding 2 ] <| viewValue functionValue
            in
            case functionValue of
                Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ) ->
                    --we are not able to display SDK functions yet
                    notClickable

                Reference _ ( packageName, moduleName, name ) ->
                    if config.standalone == False then
                        link [ Background.color <| config.state.theme.colors.selectionColor, padding 2, pointer ]
                            { url = pathToFullUrl [ packageName, moduleName ] ++ "/" ++ Name.toCamelCase name
                            , label = viewValue functionValue
                            }

                    else
                        notClickable

                _ ->
                    notClickable
    in
    case ( functionValue, argValues ) of
        ( (Value.Constructor _ fQName) as constr, _ ) ->
            case config.ir |> IR.lookupTypeSpecification (config.ir |> IR.resolveAliases fQName) of
                Just (Type.TypeAliasSpecification _ (Type.Record _ fields)) ->
                    FieldList.view
                        (List.map2
                            (\field arg ->
                                ( field.name
                                , Element.el [ smallPadding config.state.theme |> padding, Element.centerY ] (viewValue arg)
                                )
                            )
                            fields
                            argValues
                        )

                _ ->
                    Element.row styles (viewValue constr :: (argValues |> List.map viewValue))

        ( Value.Reference _ ( _, _, ("is" :: _) as localName ), [ argValue ] ) ->
            row
                (width fill :: styles)
                [ viewValue argValue
                , text (nameToText localName)
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "negate" ] ), [ argValue ] ) ->
            row styles
                [ text "- ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "abs" ] ), [ argValue ] ) ->
            row styles
                [ text "abs ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], localName ), [ argValue ] ) ->
            row ((smallPadding config.state.theme |> padding) :: styles)
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
                    styles
                    [ viewFunctionValue
                    , text " ("
                    , viewValue argValues1
                    , text ","
                    , viewValue argValues2
                    , text ")"
                    ]

            else if moduleName == [ [ "basics" ] ] && (localName == [ "power" ]) then
                row
                    styles
                    [ viewValue argValues1
                    , el [ Font.bold, Font.size (ceiling (toFloat config.state.theme.fontSize / 1.3)), moveUp (toFloat (config.state.theme.fontSize // 4)) ] (viewValue argValues2)
                    ]

            else
                case Dict.get functionName inlineBinaryOperators of
                    Just string ->
                        row
                            ((smallPadding config.state.theme |> padding) :: styles)
                            [ viewValue argValues1
                            , text string
                            , viewValue argValues2
                            ]

                    Nothing ->
                        row
                            ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding ] ++ styles)
                            [ viewFunctionValue, viewValue argValues1, viewValue argValues2 ]

        _ ->
            row ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding ] ++ styles)
                [ viewFunctionValue
                , row [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
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

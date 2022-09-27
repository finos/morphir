module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, centerX, centerY, el, fill, moveUp, padding, row, spacing, text, width, above, rgb)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR as IR
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value exposing (RawValue, Value(..), toRawValue)
import Morphir.Type.Infer as Infer
import Morphir.Value.Interpreter exposing (evaluateFunctionValue, evaluateValue)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue, fromRawValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing, borderRounded)
import Morphir.Visual.Common exposing (tooltip)
import Morphir.IR.FQName exposing (FQName)
import Svg.Attributes exposing (to)
import Morphir.Value.Error as Error exposing (Error(..))


view : Config msg -> (EnrichedValue -> Element msg) -> EnrichedValue -> List EnrichedValue -> Element msg
view config viewValue functionValue argValues =
    let
        styles =
            [ smallSpacing config.state.theme |> spacing, Element.centerY ]

        viewFunctionValue fqName =
            el [ Background.color <| config.state.theme.colors.selectionColor, padding 2, tooltip above (functionOutput fqName) ] <| viewValue functionValue

        viewRawValue : RawValue -> Element msg
        viewRawValue rawValue =
            case fromRawValue config.ir rawValue of
                Ok typedValue ->
                    el [ centerY ] (viewValue typedValue)

                Err error ->
                    el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

        functionOutput : FQName -> Element msg
        functionOutput fqName =
            let
                maybeInputs =
                    List.map (\inputName -> Dict.get inputName config.state.variables) (Dict.keys config.state.variables)

                popupstyles =  [ Background.color config.state.theme.colors.lightest
                            , Font.bold
                            , Font.center
                            , borderRounded
                            , Border.width 1
                            , smallPadding config.state.theme |> padding]
            in
            case evaluateFunctionValue config.nativeFunctions config.ir fqName maybeInputs of
                Ok value ->
                    viewRawValue value

                Err firstError ->
                    case firstError of
                        ReferenceNotFound _ ->
                            case evaluateValue config.nativeFunctions config.ir config.state.variables (List.map toRawValue argValues) (toRawValue functionValue) of
                                Ok value ->
                                    el popupstyles (viewRawValue value)

                                Err err ->
                                    el ((Font.color <| rgb 0.8 0 0) :: popupstyles) (text <| Error.toString err)
                        _ ->
                            el popupstyles (text <| "Could not evaluate this function. (" ++ (Error.toString firstError)  ++ ")")
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
        ( Value.Reference _ (( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) as fqName), [ argValues1, argValues2 ] ) ->
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
                    [ viewFunctionValue fqName
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
                            [ viewFunctionValue fqName, viewValue argValues1, viewValue argValues2 ]

        ( Value.Reference _ fqName, _ ) ->
            row ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding ] ++ styles)
                [ viewFunctionValue fqName
                , row [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
                    (argValues
                        |> List.map viewValue
                    )
                ]

        _ ->
            row ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding ] ++ styles)
                [ viewFunctionValue ([], [], [])
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

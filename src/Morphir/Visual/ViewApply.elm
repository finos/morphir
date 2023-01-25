module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, above, centerX, centerY, el, fill, moveUp, padding, paddingEach, rgb, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html.Attributes exposing (value)
import Morphir.IR as IR
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value(..), toRawValue)
import Morphir.Type.Infer as Infer
import Morphir.Value.Error as Error exposing (Error(..))
import Morphir.Value.Interpreter exposing (evaluateFunctionValue, evaluateValue)
import Morphir.Visual.Common exposing (nameToText, tooltip)
import Morphir.Visual.Components.DrillDownPanel as DrillDownPanel exposing (Depth)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config, DrillDownFunctions(..), drillDownContains, evalIfPathTaken)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue, fromRawValue, getId)
import Morphir.Visual.Theme exposing (borderRounded, smallPadding, smallSpacing)


view : Config msg -> (Config msg -> Value.Definition () (Type ()) -> Element msg) -> (EnrichedValue -> Element msg) -> EnrichedValue -> List EnrichedValue -> Element msg
view config viewDefinitionBody viewValue functionValue argValues =
    let
        styles : List (Element.Attribute msg)
        styles =
            [ smallSpacing config.state.theme |> spacing, Element.centerY ]

        drillDownPanel : FQName -> Depth -> Element msg -> Element msg -> Element msg -> Bool -> Element msg
        drillDownPanel fqName depth closedElement openHeader openElement isOpen =
            DrillDownPanel.drillDownPanel config.state.theme
                { openMsg = config.handlers.onReferenceClicked fqName (getId functionValue) config.nodePath
                , closeMsg = config.handlers.onReferenceClose fqName (getId functionValue) config.nodePath
                , depth = depth
                , closedElement = closedElement
                , openElement = openElement
                , openHeader = openHeader
                , isOpen = isOpen
                }

        viewFunctionValue : FQName -> Element msg
        viewFunctionValue fqName =
            el [ tooltip above (functionOutput fqName) ] <| viewValue functionValue

        functionOutput : FQName -> Element msg
        functionOutput fqName =
            let
                variables : List (Maybe RawValue)
                variables =
                    case Dict.get fqName config.ir.valueDefinitions of
                        Just valueDef ->
                            Dict.fromList (List.map2 (\( name, _, _ ) argValue -> ( name, argValue |> evalIfPathTaken config )) valueDef.inputTypes argValues) |> Dict.values

                        Nothing ->
                            []

                viewRawValue : RawValue -> Element msg
                viewRawValue rawValue =
                    case fromRawValue config.ir rawValue of
                        Ok typedValue ->
                            el [ centerY ] (viewValue typedValue)

                        Err error ->
                            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

                popupstyles : List (Element.Attribute msg)
                popupstyles =
                    [ Background.color config.state.theme.colors.lightest
                    , Font.bold
                    , Font.center
                    , config.state.theme |> borderRounded
                    , Border.width 1
                    , smallPadding config.state.theme |> padding
                    ]
            in
            case evaluateFunctionValue config.nativeFunctions config.ir fqName variables of
                Ok value ->
                    el popupstyles (viewRawValue value)

                Err firstError ->
                    case firstError of
                        ReferenceNotFound _ ->
                            case evaluateValue config.nativeFunctions config.ir config.state.variables (List.map toRawValue argValues) (toRawValue functionValue) of
                                Ok value ->
                                    el popupstyles (viewRawValue value)

                                Err err ->
                                    Element.none

                        _ ->
                            Element.none
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
            let
                argList : Element msg
                argList =
                    row [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
                        (argValues
                            |> List.map viewValue
                        )

                drillDown : DrillDownFunctions -> List Int -> Maybe (Value.Definition () (Type ()))
                drillDown dict nodePath =
                    if drillDownContains dict (getId functionValue) nodePath then
                        Dict.get fqName config.ir.valueDefinitions

                    else
                        Nothing

                ( _, _, valueName ) =
                    fqName

                closedElement =
                    row [ smallSpacing config.state.theme |> spacing ]
                        [ el [ Background.color <| config.state.theme.colors.selectionColor, smallPadding config.state.theme |> padding ] (text (nameToText valueName))
                        , argList
                        ]

                openElement =
                    case drillDown config.state.drillDownFunctions config.nodePath of
                        Just valueDef ->
                            let
                                variables =
                                    Dict.fromList (List.map2 (\( name, _, _ ) argValue -> ( name, argValue |> evalIfPathTaken config |> Maybe.withDefault (Value.Unit ()) )) valueDef.inputTypes argValues)

                                visualState : Morphir.Visual.Config.VisualState
                                visualState =
                                    config.state
                            in
                            viewDefinitionBody { config | state = { visualState | variables = variables }, nodePath = config.nodePath ++ [ getId functionValue ] } { valueDef | body = Value.rewriteMaybeToPatternMatch valueDef.body }

                        Nothing ->
                            Element.none

                openHeader =
                    row [ smallSpacing config.state.theme |> spacing ]
                        [ el [ Background.color <| config.state.theme.colors.selectionColor, smallPadding config.state.theme |> padding ] (text (nameToText valueName))
                        , argList

                        --, text "="
                        ]
            in
            drillDownPanel fqName (List.length config.nodePath) closedElement openHeader openElement (drillDownContains config.state.drillDownFunctions (getId functionValue) config.nodePath)

        _ ->
            row ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding, config.state.theme |> borderRounded ] ++ styles)
                [ viewFunctionValue ( [], [], [] )
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
